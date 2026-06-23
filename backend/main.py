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
from sqlalchemy import select, func, text
from sqlalchemy.orm import Session

from db import engine, Base, get_db
import models
from models import (
    User, Word, WordFamily, Deck, DeckCard, CardProgress, ReviewLog, UserStats,
    Cohort,
)
from lookup import get_or_fetch_word, WordNotFound, fetch_examples
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
def _user_out(u: User) -> dict:
    return {
        "id": u.id,
        "email": u.email,
        "display_name": u.display_name,
        "native_language": u.native_language,
        "current_level": u.current_level,
        "avatar": u.avatar,
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


@app.get("/auth/me")
def me(user: User = Depends(current_user)):
    return _user_out(user)


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
    # `correct` enables typo-correction for the search box. Taps on words that are
    # already real (synonyms, deck cards) pass correct=false so a word the free
    # dictionary happens to lack (e.g. "saltiness") returns 404 instead of being
    # silently swapped for a wrong near-spelling.
    try:
        w = get_or_fetch_word(db, word, correct=correct)
    except WordNotFound:
        raise HTTPException(status_code=404, detail=f"'{word}' is not a real word")
    return word_to_lookup(w)


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


# -------------------------------------------------------------------- /decks
@app.get("/decks")
def list_decks(user: User = Depends(current_user), db: Session = Depends(get_db)):
    decks = db.scalars(
        select(Deck).where((Deck.user_id == user.id) | (Deck.user_id.is_(None)))
    ).all()
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
        out.append({
            "id": d.id,
            "name": d.name,
            "card_count": card_count or 0,
            "due_count": due_count or 0,
            "is_system_deck": d.is_system_deck,
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
        db.commit()
    return {"ok": True}


@app.get("/decks/{deck_id}/cards")
def deck_cards(deck_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Words saved in a deck (newest first), for the deck-detail view."""
    deck = db.get(Deck, deck_id)
    if not deck or (deck.user_id is not None and deck.user_id != user.id):
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
    deck = db.get(Deck, deck_id)
    if not deck or (deck.user_id is not None and deck.user_id != user.id):
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
# ponytail: one cohort per student (cohort_id on the user), join by short code.
# A join table would let a student be in several classes — add it then.
_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no I/O/0/1 ambiguity


def _new_join_code(db: Session) -> str:
    for _ in range(10):
        code = "".join(secrets.choice(_CODE_ALPHABET) for _ in range(6))
        if not db.scalar(select(Cohort).where(Cohort.join_code == code)):
            return code
    raise HTTPException(500, "could not allocate a join code")  # ~never at this scale


def _cohort_out(c: Cohort, member_count: int, viewer_id: int | None = None) -> dict:
    return {
        "id": c.id, "name": c.name, "join_code": c.join_code,
        "member_count": member_count,
        "is_teacher": viewer_id is not None and c.created_by == viewer_id,
    }


def _member_count(db: Session, cohort_id: int) -> int:
    return db.scalar(select(func.count(User.id)).where(User.cohort_id == cohort_id)) or 0


class CohortCreate(BaseModel):
    name: str


@app.post("/cohorts", status_code=201)
def create_cohort(body: CohortCreate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    name = body.name.strip()
    if not name:
        raise HTTPException(422, "name required")
    c = Cohort(name=name, join_code=_new_join_code(db), created_by=user.id)
    db.add(c)
    db.commit()
    db.refresh(c)
    user.cohort_id = c.id  # creator joins their own class
    db.commit()
    return _cohort_out(c, _member_count(db, c.id), user.id)


class CohortJoin(BaseModel):
    code: str


@app.post("/cohorts/join")
def join_cohort(body: CohortJoin, user: User = Depends(current_user), db: Session = Depends(get_db)):
    c = db.scalar(select(Cohort).where(Cohort.join_code == body.code.strip().upper()))
    if not c:
        raise HTTPException(404, "no class with that code")
    user.cohort_id = c.id
    db.commit()
    return _cohort_out(c, _member_count(db, c.id), user.id)


@app.get("/cohort")
def my_cohort(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """The current user's class, or null if they haven't joined one."""
    if not user.cohort_id:
        return {"cohort": None}
    c = db.get(Cohort, user.cohort_id)
    return {"cohort": _cohort_out(c, _member_count(db, c.id), user.id) if c else None}


@app.get("/leaderboard")
def leaderboard(days: int = Query(7, ge=1, le=365), user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Weekly XP ranking scoped to the user's cohort. ponytail: weekly XP is
    recomputed from review_log (grade + word CEFR via gamify.xp_for) over the
    window — no stored per-period XP, no game_sessions table. Aggregated in
    Python (O(rows)); fine at ~100 users — push to a SQL CASE sum if it grows."""
    if not user.cohort_id:
        return {"cohort": None, "entries": []}
    c = db.get(Cohort, user.cohort_id)
    members = db.scalars(select(User).where(User.cohort_id == user.cohort_id)).all()
    names = {m.id: (m.display_name or (m.email.split("@")[0] if m.email else None) or f"User {m.id}") for m in members}
    xp = {m.id: 0 for m in members}

    since = now() - timedelta(days=days)
    rows = db.execute(
        select(ReviewLog.user_id, ReviewLog.result, Word.cefr_level)
        .join(Word, Word.id == ReviewLog.word_id)
        .where(ReviewLog.user_id.in_(list(xp.keys())))
        .where(ReviewLog.reviewed_at >= since)
    ).all()
    for uid, result, cefr in rows:
        xp[uid] += gamify.xp_for(result, cefr)

    entries = sorted(
        ({"user_id": uid, "display_name": names[uid], "weekly_xp": pts,
          "is_me": uid == user.id} for uid, pts in xp.items()),
        key=lambda e: e["weekly_xp"], reverse=True,
    )
    for i, e in enumerate(entries, 1):
        e["rank"] = i
    return {"cohort": _cohort_out(c, len(members)) if c else None, "entries": entries}


@app.get("/cohort/students")
def cohort_students(days: int = Query(7, ge=1, le=365), user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Teacher view: per-student progress across the teacher's own class.
    Only the cohort's creator may call it. ponytail: reuses the leaderboard's
    weekly-XP recompute and the /stats counters; no new tables, no roles system
    beyond cohort.created_by == teacher."""
    c = db.get(Cohort, user.cohort_id) if user.cohort_id else None
    if not c or c.created_by != user.id:
        raise HTTPException(403, "only the class teacher can view students")

    members = db.scalars(select(User).where(User.cohort_id == c.id)).all()
    ids = [m.id for m in members]

    stats = {s.user_id: s for s in db.scalars(select(UserStats).where(UserStats.user_id.in_(ids))).all()}
    learned = dict(db.execute(
        select(CardProgress.user_id, func.count(CardProgress.id))
        .where(CardProgress.user_id.in_(ids))
        .where(CardProgress.repetitions >= LEARNED_REPS)
        .group_by(CardProgress.user_id)
    ).all())

    weekly = {i: 0 for i in ids}
    since = now() - timedelta(days=days)
    rows = db.execute(
        select(ReviewLog.user_id, ReviewLog.result, Word.cefr_level)
        .join(Word, Word.id == ReviewLog.word_id)
        .where(ReviewLog.user_id.in_(ids))
        .where(ReviewLog.reviewed_at >= since)
    ).all()
    for uid, result, cefr in rows:
        weekly[uid] += gamify.xp_for(result, cefr)

    students = [
        {
            "user_id": m.id,
            "display_name": m.display_name or (m.email.split("@")[0] if m.email else None) or f"User {m.id}",
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
