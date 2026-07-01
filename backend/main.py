"""Lexika backend — FastAPI app implementing the CONTRACT.md MVP slice.

Token-bearer auth (see auth.py); tables are created with create_all on startup.
ponytail: create_all instead of Alembic for this single-dev MVP. Alembic is the
upgrade path once the schema needs to change against real data.
"""
import os
import secrets
import time
from collections import defaultdict
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone

from fastapi import FastAPI, Depends, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr
from sqlalchemy import select, func, text, delete
from sqlalchemy.orm import Session

from db import engine, Base, get_db
import models
from models import (
    User, Word, WordFamily, Deck, DeckCard, CardProgress, ReviewLog, UserStats,
    Cohort, CohortMember, CohortDeck,
)
from lookup import (
    get_or_fetch_word, WordNotFound, fetch_examples, suggest_spelling, autocomplete,
)
from auth import current_user, hash_password, verify_password, new_token
import sm2
import gamify

# A word counts as "learned" once it survives this many SM-2 repetitions.
# ponytail: single threshold knob; build-plan ties badges to reps>=3, learned is
# a softer bar. Tune here.
LEARNED_REPS = 2


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(engine)
    # ponytail: tiny idempotent migration — create_all won't add a column to an
    # existing table. One ALTER beats pulling in Alembic for a single field.
    with engine.begin() as conn:
        conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar VARCHAR"))
        # Hot analytical queries (leaderboard, teacher dashboard) scan
        # review_log by user over a time window, and filter users by cohort.
        # create_all won't add indexes to existing tables, so do it idempotently.
        conn.execute(text(
            "CREATE INDEX IF NOT EXISTS ix_review_log_user_time "
            "ON review_log (user_id, reviewed_at)"))
        conn.execute(text(
            "CREATE INDEX IF NOT EXISTS ix_users_cohort_id ON users (cohort_id)"))
        # Backfill the old single users.cohort_id into the new multi-class
        # membership table (idempotent — only inserts pairs not already present).
        conn.execute(text(
            "INSERT INTO cohort_members (user_id, cohort_id, joined_at) "
            "SELECT id, cohort_id, now() FROM users u "
            "WHERE cohort_id IS NOT NULL AND NOT EXISTS ("
            "  SELECT 1 FROM cohort_members m "
            "  WHERE m.user_id = u.id AND m.cohort_id = u.cohort_id)"))
    yield


app = FastAPI(title="Lexika API", lifespan=lifespan)
# Allowed web origins. Defaults cover local Flutter-web dev; set
# LEXIKA_ALLOWED_ORIGINS (comma-separated) to your app origin(s) in production.
# ponytail: env list beats a hardcoded "*" — no new config system needed.
_origins = os.getenv(
    "LEXIKA_ALLOWED_ORIGINS",
    "http://localhost:8080,http://127.0.0.1:8080",
).split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in _origins if o.strip()],
    allow_methods=["*"],
    allow_headers=["*"],
)


def now():
    return datetime.now(timezone.utc)


@app.get("/health")
def health(db: Session = Depends(get_db)):
    """Liveness + DB readiness probe for hosting platforms."""
    db.execute(text("SELECT 1"))
    return {"status": "ok"}


# --------------------------------------------------------------------- /auth
# Admins can see everyone (the /admin dashboard). ponytail: membership is an env
# allowlist of emails, not a DB role column — set LEXIKA_ADMIN_EMAILS=a@x,b@y.
_ADMIN_EMAILS = {
    e.strip().lower() for e in os.getenv("LEXIKA_ADMIN_EMAILS", "").split(",") if e.strip()
}


def _is_admin(u: User) -> bool:
    return bool(u.email and u.email.lower() in _ADMIN_EMAILS)


def require_admin(user: User = Depends(current_user)) -> User:
    if not _is_admin(user):
        raise HTTPException(403, "admin only")
    return user


def _user_out(u: User) -> dict:
    return {
        "id": u.id,
        "email": u.email,
        "display_name": u.display_name,
        "native_language": u.native_language,
        "current_level": u.current_level,
        "avatar": u.avatar,
        "is_admin": _is_admin(u),
    }


MIN_PASSWORD_LEN = 8

# ponytail: in-memory login throttle — per-process, resets on restart. Good
# enough for ~100 users on one worker; move to Redis if you run several. Keyed
# by email; a determined attacker can lock a known victim's email for the window
# (accepted at this scale — switch to IP+email keying if it matters).
_FAIL_MAX, _FAIL_WINDOW = 5, 300  # 5 failures per 5 minutes
_login_fails: dict[str, list[float]] = defaultdict(list)


def _throttle_check(email: str):
    cutoff = time.time() - _FAIL_WINDOW
    recent = [t for t in _login_fails[email] if t > cutoff]
    _login_fails[email] = recent
    if len(recent) >= _FAIL_MAX:
        raise HTTPException(429, "too many attempts — try again in a few minutes")


class Register(BaseModel):
    email: EmailStr
    password: str
    display_name: str | None = None
    native_language: str = "ru"
    current_level: str | None = None


@app.post("/auth/register")
def register(body: Register, db: Session = Depends(get_db)):
    email = body.email.strip().lower()
    if not email or not body.password:
        raise HTTPException(422, "email and password required")
    if len(body.password) < MIN_PASSWORD_LEN:
        raise HTTPException(422, f"password must be at least {MIN_PASSWORD_LEN} characters")
    if db.scalar(select(User).where(User.email == email)):
        raise HTTPException(409, "email already registered")
    u = User(
        email=email,
        password_hash=hash_password(body.password),
        display_name=body.display_name,
        native_language=body.native_language,
        current_level=body.current_level,
        auth_provider="password",
        token=new_token(),
    )
    db.add(u)
    db.commit()
    db.refresh(u)
    return {"token": u.token, "user": _user_out(u)}


class Login(BaseModel):
    email: EmailStr
    password: str


@app.post("/auth/login")
def login(body: Login, db: Session = Depends(get_db)):
    email = body.email.strip().lower()
    _throttle_check(email)
    u = db.scalar(select(User).where(User.email == email))
    if not u or not u.password_hash or not verify_password(body.password, u.password_hash):
        _login_fails[email].append(time.time())
        raise HTTPException(401, "wrong email or password")  # generic: no enumeration
    _login_fails.pop(email, None)  # clear on success
    u.token = new_token()  # rotate the token on each login
    db.commit()
    return {"token": u.token, "user": _user_out(u)}


# Google Sign-In: the app sends the Google-issued ID token; we verify it with
# Google (no password, and the email is provider-verified — this is the real fix
# for "any random email works"). ponytail: verify via Google's tokeninfo endpoint
# with stdlib urllib — no google-auth dependency, no local JWKS caching.
_GOOGLE_CLIENT_IDS = {
    c.strip() for c in os.getenv("GOOGLE_CLIENT_IDS", "").split(",") if c.strip()
}


class GoogleAuth(BaseModel):
    id_token: str


@app.post("/auth/google")
def auth_google(body: GoogleAuth, db: Session = Depends(get_db)):
    import json
    import urllib.parse
    import urllib.request

    try:
        url = "https://oauth2.googleapis.com/tokeninfo?" + urllib.parse.urlencode(
            {"id_token": body.id_token}
        )
        with urllib.request.urlopen(url, timeout=6) as resp:  # noqa: S310 (fixed host)
            claims = json.loads(resp.read())
    except Exception:
        raise HTTPException(401, "could not verify Google sign-in")

    # aud must be one of our own client IDs, or anyone could mint a token for a
    # different app and log in here. Skip the check only if none are configured
    # (dev), and say so loudly in the logs.
    aud = claims.get("aud")
    if _GOOGLE_CLIENT_IDS and aud not in _GOOGLE_CLIENT_IDS:
        raise HTTPException(401, "Google sign-in was for a different app")
    if not _GOOGLE_CLIENT_IDS:
        print("WARN: GOOGLE_CLIENT_IDS unset — skipping audience check (dev only)")

    email = (claims.get("email") or "").strip().lower()
    if not email or claims.get("email_verified") not in ("true", True):
        raise HTTPException(401, "Google account has no verified email")

    u = db.scalar(select(User).where(User.email == email))
    if not u:
        u = User(
            email=email,
            display_name=claims.get("name") or claims.get("given_name"),
            native_language="ru",
            auth_provider="google",
            token=new_token(),
        )
        db.add(u)
    else:
        u.token = new_token()  # rotate on each sign-in
        if not u.auth_provider:
            u.auth_provider = "google"
    db.commit()
    db.refresh(u)
    return {"token": u.token, "user": _user_out(u)}


@app.get("/auth/me")
def me(user: User = Depends(current_user)):
    return _user_out(user)


@app.delete("/auth/me", status_code=204)
def delete_account(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Permanently delete the signed-in user and everything owned by them:
    progress, review history, stats, class memberships, their own decks, and any
    classes they teach (with those classes' memberships and shared-deck links)."""
    uid = user.id
    # Classes this user teaches → drop their memberships + shared-deck links first.
    taught = db.scalars(select(Cohort.id).where(Cohort.created_by == uid)).all()
    if taught:
        db.execute(delete(CohortMember).where(CohortMember.cohort_id.in_(taught)))
        db.execute(delete(CohortDeck).where(CohortDeck.cohort_id.in_(taught)))
        db.execute(delete(Cohort).where(Cohort.id.in_(taught)))
    # This user's own decks (+ their cards + any share links pointing at them).
    my_decks = db.scalars(select(Deck.id).where(Deck.user_id == uid)).all()
    if my_decks:
        db.execute(delete(DeckCard).where(DeckCard.deck_id.in_(my_decks)))
        db.execute(delete(CohortDeck).where(CohortDeck.deck_id.in_(my_decks)))
        db.execute(delete(Deck).where(Deck.id.in_(my_decks)))
    db.execute(delete(CohortMember).where(CohortMember.user_id == uid))
    db.execute(delete(CardProgress).where(CardProgress.user_id == uid))
    db.execute(delete(ReviewLog).where(ReviewLog.user_id == uid))
    db.execute(delete(UserStats).where(UserStats.user_id == uid))
    db.delete(user)
    db.commit()


class ProfileUpdate(BaseModel):
    display_name: str | None = None
    native_language: str | None = None
    current_level: str | None = None
    avatar: str | None = None


@app.post("/auth/profile")
def update_profile(body: ProfileUpdate, user: User = Depends(current_user),
                   db: Session = Depends(get_db)):
    # Only fields explicitly sent (non-null) are changed. ponytail: POST not
    # PATCH so the Flutter client reuses its existing _post helper.
    if body.display_name is not None:
        user.display_name = body.display_name.strip() or None
    if body.native_language is not None:
        user.native_language = body.native_language
    if body.current_level is not None:
        user.current_level = body.current_level
    if body.avatar is not None:
        user.avatar = body.avatar
    db.commit()
    db.refresh(user)
    return _user_out(user)


# ---------------------------------------------------------------- serializers
def word_to_lookup(w: Word) -> dict:
    return {
        "id": w.id,
        "headword": w.headword,
        "phonetic": w.phonetic,
        "audio_url": w.audio_url,
        "part_of_speech": w.part_of_speech,
        "definition_en": w.definition_en,  # primary content
        "example_en": w.example_en,
        "cefr_level": w.cefr_level,
        "is_academic": w.is_academic,
        "translations": w.translations or {},  # extra: {lang_code: text}
        "synonyms": w.synonyms_json or [],
        "antonyms": w.antonyms_json or [],
    }


# ------------------------------------------------------------------- /words
@app.get("/words/lookup")
def lookup(
    word: str = Query(...),
    correct: bool = Query(True),
    db: Session = Depends(get_db),
):
    # `correct` enables Google-style spelling help for the search box. Taps on
    # words already known to be real (synonyms, deck cards) pass correct=false so a
    # word the free dictionary happens to lack returns 404 rather than a near-miss.
    original = word.strip().lower()
    try:
        # Exact match first — a real word is shown as-is, never "corrected".
        return word_to_lookup(get_or_fetch_word(db, original, correct=False))
    except WordNotFound:
        pass
    if not correct:
        raise HTTPException(status_code=404, detail=f"'{word}' is not a real word")

    # Misspelled: show the closest real word, but tell the user we corrected it
    # ("Showing results for X — you searched Y"), like a search engine.
    import httpx
    with httpx.Client(timeout=15) as client:
        candidates = suggest_spelling(client, original)
    for sug in candidates:
        try:
            w = get_or_fetch_word(db, sug, correct=False)
        except WordNotFound:
            continue
        out = word_to_lookup(w)
        if w.headword != original:
            out["corrected_from"] = original  # UI shows the "did you mean" note
        return out
    raise HTTPException(status_code=404, detail=f"'{word}' is not a real word")


@app.get("/words/{word}/examples")
def word_examples(word: str):
    """Extra example sentences for a word (Dictionary API). `[]` if none."""
    return fetch_examples(word)


@app.get("/words/suggest")
def suggest(q: str = Query(""), limit: int = Query(8, ge=1, le=20), db: Session = Depends(get_db)):
    """Autocomplete: headword strings prefix-matching `q` (case-insensitive),
    ordered by frequency_rank then alphabetically. Open like /words/lookup.
    Sources word_metadata (the headword catalogue) unioned with cached words,
    so words a user has already looked up also autocomplete."""
    prefix = q.strip().lower()
    if not prefix:
        return []
    like = prefix + "%"
    # left-join cached frequency onto the metadata catalogue, union cached-only words
    rows = db.execute(
        select(models.WordMetadata.word, models.WordMetadata.frequency_rank)
        .where(func.lower(models.WordMetadata.word).like(like))
        .union(
            select(Word.headword, models.WordMetadata.frequency_rank)
            .outerjoin(models.WordMetadata, models.WordMetadata.word == Word.headword)
            .where(func.lower(Word.headword).like(like))
        )
    ).all()
    # dedupe, then rank by frequency_rank (None last) then alphabetically
    best: dict[str, int | None] = {}
    for word, rank in rows:
        if word not in best or (rank is not None and (best[word] is None or rank < best[word])):
            best[word] = rank
    ordered = sorted(best, key=lambda w: (best[w] is None, best[w] if best[w] is not None else 0, w))
    # Words the user already has (catalogue + cache) come first; if that's thin,
    # fill with high-quality Datamuse completions so autocomplete isn't dominated
    # by obscure alphabetically-first words. Best-effort — [] if Datamuse is down.
    if len(ordered) < limit:
        have = set(ordered)
        for w in autocomplete(prefix, limit):
            if w not in have:
                ordered.append(w)
                have.add(w)
    return ordered[:limit]


# POS shorthand for the relations payload (build-plan uses adj/adv/noun/verb)
_REL_POS = {
    "noun_form": "noun", "verb_form": "verb",
    "adj_form": "adj", "adv_form": "adv",
}


@app.get("/words/{word}/relations")
def relations(word: str, db: Session = Depends(get_db)):
    headword = word.strip().lower()
    cached = db.scalar(select(Word).where(Word.headword == headword))
    synonyms = (cached.synonyms_json or []) if cached else []
    antonyms = (cached.antonyms_json or []) if cached else []

    fam_rows = db.scalars(
        select(WordFamily).where(WordFamily.base_word == headword)
    ).all()

    # Curated POS rows (noun_form/verb_form/...) keep their POS; enrichment rows
    # written by lookup.py carry relation_type "related" with no known POS.
    word_family = [
        {"word": r.related_word, "pos": _REL_POS.get(r.relation_type, r.relation_type)}
        for r in fam_rows
        if r.relation_type in _REL_POS or r.relation_type == "related"
    ]

    # Nominalization: the noun_form row, paired with a base example sentence.
    nominalization = None
    noun_row = next((r for r in fam_rows if r.relation_type == "noun_form"), None)
    base_row = next(
        (r for r in fam_rows if r.relation_type in ("verb_form", "adj_form")), None
    )
    if noun_row:
        base_pos = (
            "verb" if base_row and base_row.relation_type == "verb_form"
            else "adj" if base_row and base_row.relation_type == "adj_form"
            else None
        )
        nominalization = {
            "base_pos": base_pos,
            "base_example": base_row.example_sentence if base_row else None,
            "noun_word": noun_row.related_word,
            "noun_example": noun_row.example_sentence,
        }

    return {
        "synonyms": synonyms,
        "antonyms": antonyms,
        "word_family": word_family,
        "nominalization": nominalization,
    }


# ---------------------------------------------------------- class/deck helpers
def _user_cohort_ids(db: Session, uid: int) -> list[int]:
    """Every class the user is a member of."""
    return db.scalars(
        select(CohortMember.cohort_id).where(CohortMember.user_id == uid)
    ).all()


def _shared_deck_ids_for_user(db: Session, uid: int) -> list[int]:
    """Deck ids shared to any class the user belongs to (the live class decks)."""
    cohort_ids = _user_cohort_ids(db, uid)
    if not cohort_ids:
        return []
    return db.scalars(
        select(CohortDeck.deck_id).where(CohortDeck.cohort_id.in_(cohort_ids))
    ).all()


def _seed_progress(db: Session, user_ids, word_ids) -> None:
    """Ensure a card_progress row exists for each (user, word) so the words show
    up in that user's due queue. Idempotent. Caller commits."""
    user_ids, word_ids = list(user_ids), list(word_ids)
    if not user_ids or not word_ids:
        return
    for uid in user_ids:
        have = set(db.scalars(
            select(CardProgress.word_id).where(
                CardProgress.user_id == uid, CardProgress.word_id.in_(word_ids))
        ).all())
        for wid in word_ids:
            if wid not in have:
                db.add(CardProgress(user_id=uid, word_id=wid, next_review_at=now()))


def _accessible_deck(db: Session, user: User, deck_id: int) -> Deck | None:
    """A deck the user may read: their own, a system deck, or one shared to a
    class they're in. Returns None if not accessible."""
    deck = db.get(Deck, deck_id)
    if not deck:
        return None
    if deck.user_id is None or deck.user_id == user.id:
        return deck
    if deck.id in set(_shared_deck_ids_for_user(db, user.id)):
        return deck
    return None


# -------------------------------------------------------------------- /decks
@app.get("/decks")
def list_decks(user: User = Depends(current_user), db: Session = Depends(get_db)):
    shared_ids = set(_shared_deck_ids_for_user(db, user.id))
    # Which class each shared deck came from (for the "from <class>" label).
    deck_class: dict[int, str] = {}
    cohort_ids = _user_cohort_ids(db, user.id)
    if cohort_ids:
        for did, cname in db.execute(
            select(CohortDeck.deck_id, Cohort.name)
            .join(Cohort, Cohort.id == CohortDeck.cohort_id)
            .where(CohortDeck.cohort_id.in_(cohort_ids))
        ).all():
            deck_class.setdefault(did, cname)
    decks = db.scalars(
        select(Deck).where(
            (Deck.user_id == user.id)
            | (Deck.user_id.is_(None))
            | (Deck.id.in_(shared_ids) if shared_ids else False)
        )
    ).all()
    # Name of each shared deck's teacher, for the "from <teacher>" label.
    teacher_names: dict[int, str] = {}
    out = []
    for d in decks:
        card_count = db.scalar(
            select(func.count(DeckCard.id)).where(DeckCard.deck_id == d.id)
        )
        # due = cards in this deck whose progress is due now (or never reviewed)
        due_count = db.scalar(
            select(func.count(DeckCard.id))
            .join(CardProgress, (CardProgress.word_id == DeckCard.word_id)
                  & (CardProgress.user_id == user.id), isouter=True)
            .where(DeckCard.deck_id == d.id)
            .where((CardProgress.id.is_(None)) | (CardProgress.next_review_at <= now()))
        )
        is_shared = d.id in shared_ids and d.user_id != user.id
        shared_by = None
        if is_shared and d.user_id is not None:
            if d.user_id not in teacher_names:
                t = db.get(User, d.user_id)
                teacher_names[d.user_id] = (t.display_name or (t.email.split("@")[0] if t and t.email else None) or "teacher") if t else "teacher"
            shared_by = teacher_names[d.user_id]
        out.append({
            "id": d.id,
            "name": d.name,
            "card_count": card_count or 0,
            "due_count": due_count or 0,
            # Shared class decks are read-only for students (can't add/delete words).
            "is_system_deck": d.is_system_deck or is_shared,
            "is_shared": is_shared,
            "shared_by": shared_by,
            "shared_class": deck_class.get(d.id) if is_shared else None,
        })
    return out


class DeckCreate(BaseModel):
    name: str
    cefr_level: str | None = None


@app.post("/decks")
def create_deck(body: DeckCreate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    d = Deck(user_id=user.id, name=body.name, cefr_level=body.cefr_level)
    db.add(d)
    db.commit()
    db.refresh(d)
    return {
        "id": d.id, "name": d.name, "card_count": 0, "due_count": 0,
        "is_system_deck": d.is_system_deck,
    }


@app.delete("/decks/{deck_id}", status_code=204)
def delete_deck(deck_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Delete one of the user's own decks and its cards. System decks (user_id
    NULL) can't be deleted. Card progress is left intact (it's per word/user)."""
    deck = db.get(Deck, deck_id)
    if not deck or deck.user_id != user.id:
        raise HTTPException(404, "deck not found")
    db.execute(delete(DeckCard).where(DeckCard.deck_id == deck_id))
    db.delete(deck)
    db.commit()


class DeckImport(BaseModel):
    deck_id: int


@app.post("/decks/import", status_code=201)
def import_deck(body: DeckImport, user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Copy a shared deck's words into a new deck for the current user (used by
    QR deck-sharing). ponytail: words aren't private, so any deck id can be
    imported — no share-token table."""
    src = db.get(Deck, body.deck_id)
    if not src:
        raise HTTPException(404, "deck not found")
    word_ids = db.scalars(
        select(DeckCard.word_id).where(DeckCard.deck_id == src.id)
    ).all()
    nd = Deck(user_id=user.id, name=src.name)
    db.add(nd)
    db.flush()
    for wid in word_ids:
        db.add(DeckCard(deck_id=nd.id, word_id=wid))
        if not db.scalar(select(CardProgress.id).where(
                CardProgress.user_id == user.id, CardProgress.word_id == wid)):
            db.add(CardProgress(user_id=user.id, word_id=wid, next_review_at=now()))
    db.commit()
    db.refresh(nd)
    return {
        "id": nd.id, "name": nd.name, "card_count": len(word_ids),
        "due_count": len(word_ids), "is_system_deck": False,
    }


class CardAdd(BaseModel):
    word_id: int


@app.post("/decks/{deck_id}/cards", status_code=201)
def add_card(deck_id: int, body: CardAdd, user: User = Depends(current_user), db: Session = Depends(get_db)):
    deck = db.get(Deck, deck_id)
    # Must be the caller's own deck. 404 (not 403) so we don't leak that a deck
    # id exists for someone else. ponytail: ownership check, no ACL system.
    if not deck or deck.user_id != user.id:
        raise HTTPException(404, "deck not found")
    if not db.get(Word, body.word_id):
        raise HTTPException(404, "word not found")
    # idempotent-ish: don't duplicate the same word in a deck
    exists = db.scalar(
        select(DeckCard).where(DeckCard.deck_id == deck_id, DeckCard.word_id == body.word_id)
    )
    if not exists:
        db.add(DeckCard(deck_id=deck_id, word_id=body.word_id))
        # ensure a card_progress row exists so the word shows up in /review/due
        prog = db.scalar(
            select(CardProgress).where(
                CardProgress.user_id == user.id, CardProgress.word_id == body.word_id
            )
        )
        if not prog:
            db.add(CardProgress(user_id=user.id, word_id=body.word_id, next_review_at=now()))
        # If this deck is shared to any class, push the new word to every member
        # so a teacher's edit shows up live in their students' review queues.
        cohort_ids = db.scalars(
            select(CohortDeck.cohort_id).where(CohortDeck.deck_id == deck_id)
        ).all()
        if cohort_ids:
            members = db.scalars(
                select(CohortMember.user_id)
                .where(CohortMember.cohort_id.in_(cohort_ids))
                .where(CohortMember.user_id != user.id)
            ).all()
            _seed_progress(db, members, [body.word_id])
        db.commit()
    return {"ok": True}


@app.delete("/decks/{deck_id}/cards/{word_id}", status_code=204)
def delete_card(deck_id: int, word_id: int, user: User = Depends(current_user),
                db: Session = Depends(get_db)):
    """Remove a word from one of the user's own decks. ponytail: card_progress is
    left intact (per user/word, may be used by other decks); only the deck link
    goes. Shared/system decks aren't editable here."""
    deck = db.get(Deck, deck_id)
    if not deck or deck.user_id != user.id:
        raise HTTPException(404, "deck not found")
    db.execute(
        delete(DeckCard).where(DeckCard.deck_id == deck_id, DeckCard.word_id == word_id)
    )
    db.commit()


@app.get("/words/{word_id}/saved")
def word_saved(word_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Whether the current user already has this word in any deck — drives the
    'Saved to deck' state on the lookup card."""
    exists = db.scalar(
        select(DeckCard.id)
        .join(Deck, Deck.id == DeckCard.deck_id)
        .where(DeckCard.word_id == word_id)
        .where((Deck.user_id == user.id) | (Deck.user_id.is_(None)))
        .limit(1)
    )
    return {"saved": exists is not None}


@app.get("/decks/{deck_id}/cards")
def deck_cards(deck_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Words saved in a deck (newest first), for the deck-detail view."""
    deck = _accessible_deck(db, user, deck_id)
    if not deck:
        raise HTTPException(404, "deck not found")
    rows = db.scalars(
        select(Word)
        .join(DeckCard, DeckCard.word_id == Word.id)
        .where(DeckCard.deck_id == deck_id)
        .order_by(DeckCard.id.desc())
    ).all()
    return [
        {
            "word_id": w.id,
            "headword": w.headword,
            "definition_en": w.definition_en,
            "cefr_level": w.cefr_level,
        }
        for w in rows
    ]


@app.get("/decks/{deck_id}/review")
def deck_review(deck_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    """All cards in a deck as review cards, for practising one deck end to end
    (not just the due subset). Same shape as /review/due."""
    deck = _accessible_deck(db, user, deck_id)
    if not deck:
        raise HTTPException(404, "deck not found")
    rows = db.scalars(
        select(Word)
        .join(DeckCard, DeckCard.word_id == Word.id)
        .where(DeckCard.deck_id == deck_id)
        .order_by(DeckCard.id.desc())
    ).all()
    lang = user.native_language
    return [
        {
            "word_id": w.id,
            "headword": w.headword,
            "phonetic": w.phonetic,
            "audio_url": w.audio_url,
            "definition_en": w.definition_en,
            "translation": (w.translations or {}).get(lang) if lang else None,
            "example_en": w.example_en,
        }
        for w in rows
    ]


# ------------------------------------------------------------------- /review
@app.get("/review/due")
def review_due(limit: int = Query(20, ge=1, le=200), user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = db.execute(
        select(Word, CardProgress)
        .join(CardProgress, CardProgress.word_id == Word.id)
        .where(CardProgress.user_id == user.id)
        .where(CardProgress.next_review_at <= now())
        .order_by(CardProgress.next_review_at.asc())
        .limit(limit)
    ).all()
    # Card content is the English definition; the native-language translation is
    # an optional extra shown underneath (None if we don't have that language).
    lang = user.native_language
    return [
        {
            "word_id": w.id,
            "headword": w.headword,
            "phonetic": w.phonetic,
            "audio_url": w.audio_url,
            "definition_en": w.definition_en,  # primary
            "translation": (w.translations or {}).get(lang) if lang else None,  # extra
            "example_en": w.example_en,
        }
        for w, _ in rows
    ]


@app.get("/review/all")
def review_all(limit: int = Query(50, ge=1, le=200), user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Every word the user has saved — for the games, which are practice (not
    spaced-repetition) and should stay playable regardless of due dates."""
    rows = db.execute(
        select(Word, CardProgress)
        .join(CardProgress, CardProgress.word_id == Word.id)
        .where(CardProgress.user_id == user.id)
        .order_by(CardProgress.last_reviewed_at.asc().nullsfirst())
        .limit(limit)
    ).all()
    lang = user.native_language
    return [
        {
            "word_id": w.id,
            "headword": w.headword,
            "phonetic": w.phonetic,
            "audio_url": w.audio_url,
            "definition_en": w.definition_en,
            "translation": (w.translations or {}).get(lang) if lang else None,
            "example_en": w.example_en,
        }
        for w, _ in rows
    ]


@app.get("/words/weak")
def weak_words(limit: int = Query(10, ge=1, le=100), user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Words the user keeps struggling with. ponytail: ranked by SM-2 ease_factor
    (lower = harder), which the scheduler already maintains — no extra tracking.
    Only words actually attempted; default ease 2.5 means 'not yet hard'."""
    rows = db.execute(
        select(Word, CardProgress)
        .join(CardProgress, CardProgress.word_id == Word.id)
        .where(CardProgress.user_id == user.id)
        .where(CardProgress.total_attempts > 0)
        .where(CardProgress.ease_factor < 2.5)
        .order_by(CardProgress.ease_factor.asc())
        .limit(limit)
    ).all()
    lang = user.native_language
    return [
        {
            "word_id": w.id,
            "headword": w.headword,
            "definition_en": w.definition_en,
            "translation": (w.translations or {}).get(lang) if lang else None,
            "cefr_level": w.cefr_level,
            "ease_factor": round(p.ease_factor, 2),
            "accuracy": round(p.total_correct / p.total_attempts, 2) if p.total_attempts else None,
        }
        for w, p in rows
    ]


@app.get("/words/suggested")
def suggested_words(limit: int = Query(10, ge=1, le=100), user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Words to learn next: cached words the user hasn't started, at their level,
    academic words first, then most-frequent. ponytail: ranks over already-cached
    words (build-plan 5.1) — no new content pipeline."""
    level = user.current_level
    seen = select(CardProgress.word_id).where(CardProgress.user_id == user.id)
    rows = db.execute(
        select(Word, models.WordMetadata)
        .outerjoin(models.WordMetadata, models.WordMetadata.word == Word.headword)
        .where(Word.id.notin_(seen))
        .where(Word.definition_en.isnot(None))
        .order_by(
            (Word.cefr_level == level).desc(),       # at my level first
            Word.is_academic.desc(),                 # academic words next
            models.WordMetadata.frequency_rank.asc().nulls_last(),  # then most common
        )
        .limit(limit)
    ).all()
    lang = user.native_language
    return [
        {
            "word_id": w.id,
            "headword": w.headword,
            "definition_en": w.definition_en,
            "translation": (w.translations or {}).get(lang) if lang else None,
            "cefr_level": w.cefr_level,
            "is_academic": w.is_academic,
        }
        for w, _ in rows
    ]


# Games map a correct/incorrect answer onto an SM-2 grade and tag the review_log
# row with how it was tested (build-plan 5.3). ponytail: no separate game_sessions
# table — review_log.game_type already carries this; add game_sessions when Phase 7
# leaderboards need per-session score rows.
GAME_TYPES = {"flashcard", "matching", "listening", "typing", "quiz"}


class ReviewSubmit(BaseModel):
    word_id: int
    grade: str  # again|hard|good|easy
    game_type: str = "flashcard"


@app.post("/review/submit")
def review_submit(body: ReviewSubmit, user: User = Depends(current_user), db: Session = Depends(get_db)):
    if body.grade not in sm2.GRADES:
        raise HTTPException(422, f"grade must be one of {sm2.GRADES}")
    if body.game_type not in GAME_TYPES:
        raise HTTPException(422, f"game_type must be one of {GAME_TYPES}")
    word = db.get(Word, body.word_id)
    if not word:
        raise HTTPException(404, "word not found")

    prog = db.scalar(
        select(CardProgress).where(
            CardProgress.user_id == user.id, CardProgress.word_id == body.word_id
        )
    )
    if not prog:
        prog = CardProgress(user_id=user.id, word_id=body.word_id)
        db.add(prog)
        db.flush()  # populate column defaults (ease 2.5 etc.) before we read them

    new = sm2.schedule(
        sm2.SM2State(prog.ease_factor, prog.interval_days, prog.repetitions), body.grade
    )
    correct = body.grade in ("good", "easy")

    prog.ease_factor = new.ease_factor
    prog.interval_days = new.interval_days
    prog.repetitions = new.repetitions
    # interval 0 (again) -> re-show in ~1 min; otherwise schedule out by days
    delay_seconds = 60 if new.interval_days == 0 else new.interval_days * 86400
    prog.next_review_at = now() + timedelta(seconds=delay_seconds)
    prog.last_result = body.grade
    prog.consecutive_correct = (prog.consecutive_correct + 1) if correct else 0
    prog.total_attempts += 1
    prog.total_correct += 1 if correct else 0
    prog.last_reviewed_at = now()

    db.add(ReviewLog(user_id=user.id, word_id=body.word_id, game_type=body.game_type, result=body.grade))

    # Gamification: award XP and roll the daily streak (build-plan 5.4).
    xp = gamify.xp_for(body.grade, word.cefr_level)
    stats = _get_or_create_stats(db, user.id)
    today = now().date()
    stats.current_streak = gamify.next_streak(
        stats.current_streak, stats.last_active_date, today
    )
    stats.longest_streak = max(stats.longest_streak, stats.current_streak)
    stats.total_xp += xp
    stats.last_active_date = today

    db.commit()
    db.refresh(prog)

    return {
        "next_review_at": prog.next_review_at.isoformat(),
        "interval_days": round(prog.interval_days, 4),
        "xp_earned": xp,
        "total_xp": stats.total_xp,
        "current_streak": stats.current_streak,
    }


def _get_or_create_stats(db: Session, user_id: int) -> UserStats:
    stats = db.get(UserStats, user_id)
    if not stats:
        stats = UserStats(user_id=user_id)
        db.add(stats)
        db.flush()  # populate column defaults (streak/xp = 0) before we read them
    return stats


@app.get("/stats/activity")
def stats_activity(days: int = Query(120, ge=7, le=400), user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Distinct calendar days (UTC) the user reviewed something, for the streak
    calendar. Gaps between dates are where a streak was lost."""
    since = now() - timedelta(days=days)
    rows = db.scalars(
        select(ReviewLog.reviewed_at)
        .where(ReviewLog.user_id == user.id, ReviewLog.reviewed_at >= since)
    ).all()
    dates = sorted({r.date().isoformat() for r in rows})
    return {"active_dates": dates}


@app.get("/stats/learned")
def stats_learned(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """The words the user has learned (survived >= LEARNED_REPS repetitions) —
    the tap-through list behind the 'words learned' tile. Newest first."""
    rows = db.scalars(
        select(Word)
        .join(CardProgress, CardProgress.word_id == Word.id)
        .where(CardProgress.user_id == user.id)
        .where(CardProgress.repetitions >= LEARNED_REPS)
        .order_by(CardProgress.last_reviewed_at.desc().nullslast())
    ).all()
    lang = user.native_language
    return [
        {
            "word_id": w.id,
            "headword": w.headword,
            "definition_en": w.definition_en,
            "translation": (w.translations or {}).get(lang) if lang else None,
            "cefr_level": w.cefr_level,
        }
        for w in rows
    ]


@app.get("/stats")
def stats(user: User = Depends(current_user), db: Session = Depends(get_db)):
    s = _get_or_create_stats(db, user.id)
    words_learned = db.scalar(
        select(func.count(CardProgress.id)).where(
            CardProgress.user_id == user.id,
            CardProgress.repetitions >= LEARNED_REPS,
        )
    ) or 0
    db.commit()  # persist a freshly created stats row
    return {
        "current_streak": s.current_streak,
        "longest_streak": s.longest_streak,
        "total_xp": s.total_xp,
        "total_words_learned": words_learned,
    }


# Fixed CEFR axis so the chart always shows all six bars in order, even for
# levels the user hasn't attempted yet. ponytail: accuracy summed from
# card_progress (the same counters /words/weak reads), not recomputed from
# review_log — one GROUP BY, no per-answer scan.
_CEFR_ORDER = ["A1", "A2", "B1", "B2", "C1", "C2"]


@app.get("/stats/accuracy_by_level")
def accuracy_by_level(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = db.execute(
        select(
            Word.cefr_level,
            func.sum(CardProgress.total_correct),
            func.sum(CardProgress.total_attempts),
        )
        .join(Word, Word.id == CardProgress.word_id)
        .where(CardProgress.user_id == user.id)
        .where(Word.cefr_level.in_(_CEFR_ORDER))
        .group_by(Word.cefr_level)
    ).all()
    by_level = {lvl: (correct or 0, attempts or 0) for lvl, correct, attempts in rows}
    return [
        {
            "level": lvl,
            "attempts": by_level.get(lvl, (0, 0))[1],
            "accuracy": round(by_level[lvl][0] / by_level[lvl][1], 2)
            if by_level.get(lvl, (0, 0))[1]
            else None,
        }
        for lvl in _CEFR_ORDER
    ]


# ---------------------------------------------------- /cohorts + /leaderboard
# A student can belong to several classes (cohort_members join table). Classes a
# user teaches are cohorts they created; decks are shared *to a class* (cohort_decks),
# not copied per student, so late joiners and teacher edits are seen live.
_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no I/O/0/1 ambiguity


def _new_join_code(db: Session) -> str:
    for _ in range(10):
        code = "".join(secrets.choice(_CODE_ALPHABET) for _ in range(6))
        if not db.scalar(select(Cohort).where(Cohort.join_code == code)):
            return code
    raise HTTPException(500, "could not allocate a join code")  # ~never at this scale


def _cohort_out(c: Cohort, member_count: int, viewer_id: int | None = None,
                is_member: bool | None = None) -> dict:
    return {
        "id": c.id, "name": c.name, "join_code": c.join_code,
        "member_count": member_count,
        "is_teacher": viewer_id is not None and c.created_by == viewer_id,
        "is_member": is_member,
    }


def _member_count(db: Session, cohort_id: int) -> int:
    return db.scalar(
        select(func.count(CohortMember.id)).where(CohortMember.cohort_id == cohort_id)
    ) or 0


def _is_member(db: Session, uid: int, cohort_id: int) -> bool:
    return db.scalar(select(CohortMember.id).where(
        CohortMember.user_id == uid, CohortMember.cohort_id == cohort_id)) is not None


def _add_member(db: Session, uid: int, cohort_id: int) -> None:
    if not _is_member(db, uid, cohort_id):
        db.add(CohortMember(user_id=uid, cohort_id=cohort_id))


def _member_ids(db: Session, cohort_id: int) -> list[int]:
    return db.scalars(
        select(CohortMember.user_id).where(CohortMember.cohort_id == cohort_id)
    ).all()


def _display_name(m: User) -> str:
    return m.display_name or (m.email.split("@")[0] if m.email else None) or f"User {m.id}"


def _weekly_xp(db: Session, ids: list[int], days: int) -> dict[int, int]:
    """Recompute weekly XP from review_log for a set of users (ponytail: no stored
    per-period XP). Shared by the leaderboard and the teacher dashboard."""
    xp = {i: 0 for i in ids}
    if not ids:
        return xp
    since = now() - timedelta(days=days)
    rows = db.execute(
        select(ReviewLog.user_id, ReviewLog.result, Word.cefr_level)
        .join(Word, Word.id == ReviewLog.word_id)
        .where(ReviewLog.user_id.in_(ids))
        .where(ReviewLog.reviewed_at >= since)
    ).all()
    for uid, result, cefr in rows:
        xp[uid] += gamify.xp_for(result, cefr)
    return xp


class CohortCreate(BaseModel):
    name: str


@app.post("/cohorts", status_code=201)
def create_cohort(body: CohortCreate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    name = body.name.strip()
    if not name:
        raise HTTPException(422, "name required")
    c = Cohort(name=name, join_code=_new_join_code(db), created_by=user.id)
    db.add(c)
    db.flush()
    _add_member(db, user.id, c.id)  # creator joins their own class
    user.cohort_id = c.id  # legacy 'active class' hint
    db.commit()
    db.refresh(c)
    return _cohort_out(c, _member_count(db, c.id), user.id, is_member=True)


class CohortJoin(BaseModel):
    code: str


@app.post("/cohorts/join")
def join_cohort(body: CohortJoin, user: User = Depends(current_user), db: Session = Depends(get_db)):
    c = db.scalar(select(Cohort).where(Cohort.join_code == body.code.strip().upper()))
    if not c:
        raise HTTPException(404, "no class with that code")
    _add_member(db, user.id, c.id)
    user.cohort_id = c.id  # legacy 'active class' hint
    # Seed the class's shared decks into the new member's review queue so they
    # see everything already shared to the class (not just future words).
    deck_ids = db.scalars(
        select(CohortDeck.deck_id).where(CohortDeck.cohort_id == c.id)
    ).all()
    if deck_ids:
        word_ids = db.scalars(
            select(DeckCard.word_id).where(DeckCard.deck_id.in_(deck_ids))
        ).all()
        _seed_progress(db, [user.id], word_ids)
    db.commit()
    return _cohort_out(c, _member_count(db, c.id), user.id, is_member=True)


@app.get("/cohorts/mine")
def my_cohorts(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Every class the student is a member of (they can belong to several)."""
    cohort_ids = _user_cohort_ids(db, user.id)
    cohorts = db.scalars(
        select(Cohort).where(Cohort.id.in_(cohort_ids)).order_by(Cohort.id)
    ).all() if cohort_ids else []
    return {
        "classes": [
            _cohort_out(c, _member_count(db, c.id), user.id, is_member=True)
            for c in cohorts
        ]
    }


@app.get("/cohorts/{cohort_id}")
def cohort_detail(cohort_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Full info about one class: members, the decks shared to it, and (for the
    teacher) whether they own it. Any member or the teacher may view it."""
    c = db.get(Cohort, cohort_id)
    if not c:
        raise HTTPException(404, "class not found")
    is_teacher = c.created_by == user.id
    if not is_teacher and not _is_member(db, user.id, cohort_id):
        raise HTTPException(403, "not a member of this class")

    members = db.scalars(
        select(User).join(CohortMember, CohortMember.user_id == User.id)
        .where(CohortMember.cohort_id == cohort_id)
    ).all()
    deck_rows = db.scalars(
        select(Deck).join(CohortDeck, CohortDeck.deck_id == Deck.id)
        .where(CohortDeck.cohort_id == cohort_id)
    ).all()
    teacher = db.get(User, c.created_by) if c.created_by else None
    return {
        **_cohort_out(c, len(members), user.id, is_member=_is_member(db, user.id, cohort_id)),
        "teacher_name": _display_name(teacher) if teacher else None,
        "members": [
            {"user_id": m.id, "display_name": _display_name(m),
             "is_teacher": m.id == c.created_by}
            for m in members
        ],
        "decks": [
            {"id": d.id, "name": d.name,
             "card_count": db.scalar(
                 select(func.count(DeckCard.id)).where(DeckCard.deck_id == d.id)) or 0}
            for d in deck_rows
        ],
    }


@app.post("/cohorts/{cohort_id}/leave", status_code=204)
def leave_cohort(cohort_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Leave a class. The teacher can't leave their own class — they delete it."""
    c = db.get(Cohort, cohort_id)
    if c and c.created_by == user.id:
        raise HTTPException(400, "the teacher can't leave — delete the class instead")
    db.execute(delete(CohortMember).where(
        CohortMember.user_id == user.id, CohortMember.cohort_id == cohort_id))
    if user.cohort_id == cohort_id:
        user.cohort_id = None
    db.commit()


@app.delete("/cohorts/{cohort_id}", status_code=204)
def delete_cohort(cohort_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Delete a class the user teaches — removes all memberships and shared-deck
    links (the underlying decks and per-user progress are untouched)."""
    c = db.get(Cohort, cohort_id)
    if not c or c.created_by != user.id:
        raise HTTPException(404, "class not found")
    db.execute(delete(CohortMember).where(CohortMember.cohort_id == cohort_id))
    db.execute(delete(CohortDeck).where(CohortDeck.cohort_id == cohort_id))
    db.execute(text("UPDATE users SET cohort_id = NULL WHERE cohort_id = :cid"),
               {"cid": cohort_id})
    db.delete(c)
    db.commit()


@app.get("/cohort/teaching")
def cohort_teaching(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """All classes this user created (teaches). A teacher can own several."""
    cohorts = db.scalars(
        select(Cohort).where(Cohort.created_by == user.id).order_by(Cohort.id)
    ).all()
    return {
        "classes": [_cohort_out(c, _member_count(db, c.id), user.id, is_member=True)
                    for c in cohorts]
    }


def _leaderboard_for(db: Session, c: Cohort, viewer_id: int, days: int) -> dict:
    members = db.scalars(
        select(User).join(CohortMember, CohortMember.user_id == User.id)
        .where(CohortMember.cohort_id == c.id)
    ).all()
    names = {m.id: _display_name(m) for m in members}
    xp = _weekly_xp(db, [m.id for m in members], days)
    entries = sorted(
        ({"user_id": uid, "display_name": names[uid], "weekly_xp": pts,
          "is_me": uid == viewer_id} for uid, pts in xp.items()),
        key=lambda e: e["weekly_xp"], reverse=True,
    )
    for i, e in enumerate(entries, 1):
        e["rank"] = i
    return {"cohort": _cohort_out(c, len(members), viewer_id), "entries": entries}


@app.get("/cohorts/{cohort_id}/leaderboard")
def cohort_leaderboard(cohort_id: int, days: int = Query(7, ge=1, le=365),
                       user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Weekly XP ranking scoped to one class the viewer belongs to (or teaches)."""
    c = db.get(Cohort, cohort_id)
    if not c:
        raise HTTPException(404, "class not found")
    if c.created_by != user.id and not _is_member(db, user.id, cohort_id):
        raise HTTPException(403, "not a member of this class")
    return _leaderboard_for(db, c, user.id, days)


@app.get("/cohorts/{cohort_id}/students")
def cohort_students(cohort_id: int, days: int = Query(7, ge=1, le=365),
                    user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Teacher view: per-student progress for one class the teacher owns.
    ponytail: reuses the weekly-XP recompute and the /stats counters; no new
    tables, no roles beyond cohort.created_by == teacher."""
    c = db.get(Cohort, cohort_id)
    if not c or c.created_by != user.id:
        raise HTTPException(403, "only the class teacher can view students")

    members = db.scalars(
        select(User).join(CohortMember, CohortMember.user_id == User.id)
        .where(CohortMember.cohort_id == cohort_id)
    ).all()
    ids = [m.id for m in members]

    stats = {s.user_id: s for s in db.scalars(select(UserStats).where(UserStats.user_id.in_(ids))).all()}
    learned = dict(db.execute(
        select(CardProgress.user_id, func.count(CardProgress.id))
        .where(CardProgress.user_id.in_(ids))
        .where(CardProgress.repetitions >= LEARNED_REPS)
        .group_by(CardProgress.user_id)
    ).all()) if ids else {}
    weekly = _weekly_xp(db, ids, days)

    students = [
        {
            "user_id": m.id,
            "display_name": _display_name(m),
            "is_teacher": m.id == c.created_by,
            "total_xp": stats[m.id].total_xp if m.id in stats else 0,
            "current_streak": stats[m.id].current_streak if m.id in stats else 0,
            "words_learned": learned.get(m.id, 0),
            "weekly_xp": weekly[m.id],
            "last_active": stats[m.id].last_active_date.isoformat()
            if m.id in stats and stats[m.id].last_active_date else None,
        }
        for m in members
    ]
    students.sort(key=lambda s: s["weekly_xp"], reverse=True)
    return {"cohort": _cohort_out(c, len(members), user.id), "students": students}


class ShareDeck(BaseModel):
    deck_id: int


@app.post("/cohorts/{cohort_id}/decks")
def share_deck(cohort_id: int, body: ShareDeck, user: User = Depends(current_user),
               db: Session = Depends(get_db)):
    """Teacher shares one of their decks *to a class* (not copied). Every member —
    including future joiners — sees the live deck, and the teacher's later edits
    propagate. Seeds the deck's words into current members' review queues."""
    c = db.get(Cohort, cohort_id)
    if not c or c.created_by != user.id:
        raise HTTPException(403, "only the class teacher can share decks")
    deck = db.get(Deck, body.deck_id)
    if not deck or deck.user_id != user.id:
        raise HTTPException(404, "deck not found")

    if not db.scalar(select(CohortDeck.id).where(
            CohortDeck.cohort_id == cohort_id, CohortDeck.deck_id == deck.id)):
        db.add(CohortDeck(cohort_id=cohort_id, deck_id=deck.id))

    word_ids = db.scalars(
        select(DeckCard.word_id).where(DeckCard.deck_id == deck.id)
    ).all()
    members = [i for i in _member_ids(db, cohort_id) if i != user.id]
    _seed_progress(db, members, word_ids)
    db.commit()
    return {"shared_to": len(members), "words": len(word_ids)}


@app.delete("/cohorts/{cohort_id}/decks/{deck_id}", status_code=204)
def unshare_deck(cohort_id: int, deck_id: int, user: User = Depends(current_user),
                 db: Session = Depends(get_db)):
    """Teacher stops sharing a deck with a class. ponytail: only the link is
    removed — members keep any progress they already made on those words."""
    c = db.get(Cohort, cohort_id)
    if not c or c.created_by != user.id:
        raise HTTPException(403, "only the class teacher can manage shared decks")
    db.execute(delete(CohortDeck).where(
        CohortDeck.cohort_id == cohort_id, CohortDeck.deck_id == deck_id))
    db.commit()


# ---------------------------------------------------------------------- /admin
@app.get("/admin/users")
def admin_users(days: int = Query(7, ge=1, le=365),
                admin: User = Depends(require_admin), db: Session = Depends(get_db)):
    """Every user with a snapshot of what they're doing: XP, streak, words
    learned, reviews this week, last active, and the classes they're in.
    ponytail: one pass per aggregate over all users — fine at this scale."""
    users = db.scalars(select(User).order_by(User.id)).all()
    ids = [u.id for u in users]

    stats = {s.user_id: s for s in db.scalars(select(UserStats).where(UserStats.user_id.in_(ids))).all()} if ids else {}
    learned = dict(db.execute(
        select(CardProgress.user_id, func.count(CardProgress.id))
        .where(CardProgress.user_id.in_(ids))
        .where(CardProgress.repetitions >= LEARNED_REPS)
        .group_by(CardProgress.user_id)
    ).all()) if ids else {}
    since = now() - timedelta(days=days)
    reviews = dict(db.execute(
        select(ReviewLog.user_id, func.count(ReviewLog.id))
        .where(ReviewLog.user_id.in_(ids))
        .where(ReviewLog.reviewed_at >= since)
        .group_by(ReviewLog.user_id)
    ).all()) if ids else {}
    # class memberships per user
    classes: dict[int, list[str]] = defaultdict(list)
    for uid, cname in db.execute(
        select(CohortMember.user_id, Cohort.name)
        .join(Cohort, Cohort.id == CohortMember.cohort_id)
    ).all():
        classes[uid].append(cname)

    return {
        "users": [
            {
                "id": u.id,
                "email": u.email,
                "display_name": u.display_name,
                "auth_provider": u.auth_provider,
                "native_language": u.native_language,
                "current_level": u.current_level,
                "is_admin": _is_admin(u),
                "created_at": u.created_at.isoformat() if u.created_at else None,
                "total_xp": stats[u.id].total_xp if u.id in stats else 0,
                "current_streak": stats[u.id].current_streak if u.id in stats else 0,
                "words_learned": learned.get(u.id, 0),
                "reviews_recent": reviews.get(u.id, 0),
                "last_active": stats[u.id].last_active_date.isoformat()
                if u.id in stats and stats[u.id].last_active_date else None,
                "classes": classes.get(u.id, []),
            }
            for u in users
        ],
        "total": len(users),
        "window_days": days,
    }
