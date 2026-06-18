"""Lexika backend — FastAPI app implementing the CONTRACT.md MVP slice.

No auth this slice: every request is the seeded user_id=1.
Tables are created with create_all on startup.
ponytail: create_all instead of Alembic for this single-dev MVP. Alembic is the
upgrade path once the schema needs to change against real data.
"""
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI, Depends, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sqlalchemy import select, func
from sqlalchemy.orm import Session

from db import engine, Base, get_db
import models
from models import (
    User, Word, WordFamily, Deck, DeckCard, CardProgress, ReviewLog, UserStats,
)
from lookup import get_or_fetch_word, WordNotFound
import sm2
import gamify

# A word counts as "learned" once it survives this many SM-2 repetitions.
# ponytail: single threshold knob; build-plan ties badges to reps>=3, learned is
# a softer bar. Tune here.
LEARNED_REPS = 2

USER_ID = 1  # ponytail: hardcoded single user until Firebase auth lands.


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(engine)
    yield


app = FastAPI(title="Lexika API", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # dev only
    allow_methods=["*"],
    allow_headers=["*"],
)


def now():
    return datetime.now(timezone.utc)


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
def lookup(word: str = Query(...), db: Session = Depends(get_db)):
    try:
        w = get_or_fetch_word(db, word)
    except WordNotFound:
        raise HTTPException(status_code=404, detail=f"'{word}' is not a real word")
    return word_to_lookup(w)


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

    word_family = [
        {"word": r.related_word, "pos": _REL_POS.get(r.relation_type, r.relation_type)}
        for r in fam_rows
        if r.relation_type in _REL_POS
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
def list_decks(db: Session = Depends(get_db)):
    decks = db.scalars(
        select(Deck).where((Deck.user_id == USER_ID) | (Deck.user_id.is_(None)))
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
                  & (CardProgress.user_id == USER_ID), isouter=True)
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
def create_deck(body: DeckCreate, db: Session = Depends(get_db)):
    d = Deck(user_id=USER_ID, name=body.name, cefr_level=body.cefr_level)
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
def add_card(deck_id: int, body: CardAdd, db: Session = Depends(get_db)):
    if not db.get(Deck, deck_id):
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
                CardProgress.user_id == USER_ID, CardProgress.word_id == body.word_id
            )
        )
        if not prog:
            db.add(CardProgress(user_id=USER_ID, word_id=body.word_id, next_review_at=now()))
        db.commit()
    return {"ok": True}


# ------------------------------------------------------------------- /review
@app.get("/review/due")
def review_due(limit: int = Query(20, ge=1, le=200), db: Session = Depends(get_db)):
    rows = db.execute(
        select(Word, CardProgress)
        .join(CardProgress, CardProgress.word_id == Word.id)
        .where(CardProgress.user_id == USER_ID)
        .where(CardProgress.next_review_at <= now())
        .order_by(CardProgress.next_review_at.asc())
        .limit(limit)
    ).all()
    # Card content is the English definition; the native-language translation is
    # an optional extra shown underneath (None if we don't have that language).
    user = db.get(User, USER_ID)
    lang = user.native_language if user else None
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
def review_submit(body: ReviewSubmit, db: Session = Depends(get_db)):
    if body.grade not in sm2.GRADES:
        raise HTTPException(422, f"grade must be one of {sm2.GRADES}")
    if body.game_type not in GAME_TYPES:
        raise HTTPException(422, f"game_type must be one of {GAME_TYPES}")
    word = db.get(Word, body.word_id)
    if not word:
        raise HTTPException(404, "word not found")

    prog = db.scalar(
        select(CardProgress).where(
            CardProgress.user_id == USER_ID, CardProgress.word_id == body.word_id
        )
    )
    if not prog:
        prog = CardProgress(user_id=USER_ID, word_id=body.word_id)
        db.add(prog)

    new = sm2.schedule(
        sm2.SM2State(prog.ease_factor, prog.interval_days, prog.repetitions), body.grade
    )
    correct = body.grade in ("good", "easy")

    prog.ease_factor = new.ease_factor
    prog.interval_days = new.interval_days
    prog.repetitions = new.repetitions
    # interval 0 (again) -> re-show in ~1 min; otherwise schedule out by days
    delay_seconds = 60 if new.interval_days == 0 else new.interval_days * 86400
    prog.next_review_at = now() + _seconds(delay_seconds)
    prog.last_result = body.grade
    prog.consecutive_correct = (prog.consecutive_correct + 1) if correct else 0
    prog.total_attempts += 1
    prog.total_correct += 1 if correct else 0
    prog.last_reviewed_at = now()

    db.add(ReviewLog(user_id=USER_ID, word_id=body.word_id, game_type=body.game_type, result=body.grade))

    # Gamification: award XP and roll the daily streak (build-plan 5.4).
    xp = gamify.xp_for(body.grade, word.cefr_level)
    stats = _get_or_create_stats(db)
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


def _get_or_create_stats(db: Session) -> UserStats:
    stats = db.get(UserStats, USER_ID)
    if not stats:
        stats = UserStats(user_id=USER_ID)
        db.add(stats)
    return stats


@app.get("/stats")
def stats(db: Session = Depends(get_db)):
    s = _get_or_create_stats(db)
    words_learned = db.scalar(
        select(func.count(CardProgress.id)).where(
            CardProgress.user_id == USER_ID,
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


def _seconds(s: float):
    from datetime import timedelta
    return timedelta(seconds=s)
