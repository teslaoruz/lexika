"""SQLAlchemy models for the MVP slice (build-plan section 4).
Tables: users, words, word_family, word_metadata, decks, deck_cards,
card_progress, review_log. game_sessions/user_stats skipped — ponytail,
no games yet; add when Phase 3/4 land.

ponytail: synonyms/antonyms stored as JSON columns on `words` instead of a
join table — they come as a list straight from the Dictionary API and we only
ever read them whole. Normalize if we ever need to query by synonym.
"""
from datetime import datetime, timezone
from sqlalchemy import (
    Integer, String, Text, Boolean, Float, DateTime, ForeignKey, JSON
)
from sqlalchemy.orm import Mapped, mapped_column
from db import Base


def utcnow():
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str | None] = mapped_column(String, nullable=True)
    display_name: Mapped[str | None] = mapped_column(String, nullable=True)
    auth_provider: Mapped[str | None] = mapped_column(String, nullable=True)
    native_language: Mapped[str | None] = mapped_column(String, nullable=True)
    current_level: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class WordMetadata(Base):
    """CEFR-J + AWL join table. Keyed by lowercase headword."""
    __tablename__ = "word_metadata"
    word: Mapped[str] = mapped_column(String, primary_key=True)
    cefr_level: Mapped[str | None] = mapped_column(String, nullable=True)
    is_academic: Mapped[bool] = mapped_column(Boolean, default=False)
    frequency_rank: Mapped[int | None] = mapped_column(Integer, nullable=True)


class Word(Base):
    """Cache of every word ever looked up."""
    __tablename__ = "words"
    id: Mapped[int] = mapped_column(primary_key=True)
    headword: Mapped[str] = mapped_column(String, unique=True, index=True)
    phonetic: Mapped[str | None] = mapped_column(String, nullable=True)
    audio_url: Mapped[str | None] = mapped_column(String, nullable=True)
    part_of_speech: Mapped[str | None] = mapped_column(String, nullable=True)
    definition_en: Mapped[str | None] = mapped_column(Text, nullable=True)
    example_en: Mapped[str | None] = mapped_column(Text, nullable=True)
    cefr_level: Mapped[str | None] = mapped_column(String, nullable=True)
    is_academic: Mapped[bool] = mapped_column(Boolean, default=False)
    translation_ru: Mapped[str | None] = mapped_column(String, nullable=True)
    translation_kk: Mapped[str | None] = mapped_column(String, nullable=True)
    synonyms_json: Mapped[list] = mapped_column(JSON, default=list)
    antonyms_json: Mapped[list] = mapped_column(JSON, default=list)
    source: Mapped[str | None] = mapped_column(String, nullable=True)
    fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class WordFamily(Base):
    """Curated word-family / nominalization rows."""
    __tablename__ = "word_family"
    id: Mapped[int] = mapped_column(primary_key=True)
    base_word: Mapped[str] = mapped_column(String, index=True)
    related_word: Mapped[str] = mapped_column(String)
    relation_type: Mapped[str] = mapped_column(String)  # noun_form/verb_form/adj_form/adv_form/synonym/antonym
    example_sentence: Mapped[str | None] = mapped_column(Text, nullable=True)
    word_family_group_id: Mapped[int | None] = mapped_column(Integer, nullable=True)


class Deck(Base):
    __tablename__ = "decks"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    name: Mapped[str] = mapped_column(String)
    is_system_deck: Mapped[bool] = mapped_column(Boolean, default=False)
    cefr_level: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class DeckCard(Base):
    __tablename__ = "deck_cards"
    id: Mapped[int] = mapped_column(primary_key=True)
    deck_id: Mapped[int] = mapped_column(ForeignKey("decks.id"), index=True)
    word_id: Mapped[int] = mapped_column(ForeignKey("words.id"))
    added_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class CardProgress(Base):
    """Per-user SM-2 state per word."""
    __tablename__ = "card_progress"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    word_id: Mapped[int] = mapped_column(ForeignKey("words.id"), index=True)
    ease_factor: Mapped[float] = mapped_column(Float, default=2.5)
    interval_days: Mapped[float] = mapped_column(Float, default=0.0)
    repetitions: Mapped[int] = mapped_column(Integer, default=0)
    next_review_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    last_result: Mapped[str | None] = mapped_column(String, nullable=True)
    consecutive_correct: Mapped[int] = mapped_column(Integer, default=0)
    total_correct: Mapped[int] = mapped_column(Integer, default=0)
    total_attempts: Mapped[int] = mapped_column(Integer, default=0)
    last_reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class ReviewLog(Base):
    """Append-only review history."""
    __tablename__ = "review_log"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    word_id: Mapped[int] = mapped_column(ForeignKey("words.id"))
    game_type: Mapped[str] = mapped_column(String, default="flashcard")
    result: Mapped[str | None] = mapped_column(String, nullable=True)
    response_time_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    reviewed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
