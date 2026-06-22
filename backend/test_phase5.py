"""ponytail self-check for Phase 5 endpoints. Runs the real query logic against
an in-memory SQLite. Run: uv run python test_phase5.py"""
from sqlalchemy import create_engine
from sqlalchemy.pool import StaticPool
from sqlalchemy.orm import sessionmaker
from fastapi.testclient import TestClient

import db
from db import Base

# Point the app at a throwaway in-memory DB before importing main.
# StaticPool: one shared connection so every session sees the same in-memory DB.
engine = create_engine(
    "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
)
TestSession = sessionmaker(bind=engine)
db.engine = engine
db.SessionLocal = TestSession

import main  # noqa: E402  (must follow the engine swap)
from models import User, Word, WordMetadata, CardProgress  # noqa: E402


AUTH = {"Authorization": "Bearer test-token-1"}  # matches the seeded user below


def setup():
    Base.metadata.create_all(engine)
    s = TestSession()
    s.add(User(id=1, native_language="ru", current_level="B1", token="test-token-1"))
    # easy=hard word (low ease), normal word, a learned word, and unseen words
    s.add_all([
        Word(id=1, headword="aberration", definition_en="a departure", cefr_level="C1"),
        Word(id=2, headword="cat", definition_en="an animal", cefr_level="A1"),
        Word(id=3, headword="ubiquitous", definition_en="everywhere", cefr_level="B1", is_academic=True),
        Word(id=4, headword="apple", definition_en="a fruit", cefr_level="A1"),
    ])
    s.add_all([
        WordMetadata(word="ubiquitous", is_academic=True, frequency_rank=5000),
        WordMetadata(word="apple", frequency_rank=900),
    ])
    # word 1 attempted and hard; word 2 attempted and fine; words 3/4 untouched
    s.add(CardProgress(user_id=1, word_id=1, ease_factor=1.8, total_attempts=4, total_correct=1))
    s.add(CardProgress(user_id=1, word_id=2, ease_factor=2.5, total_attempts=3, total_correct=3))
    s.commit()
    s.close()


def main_test():
    setup()
    c = TestClient(main.app)

    weak = c.get("/words/weak", headers=AUTH).json()
    assert [w["headword"] for w in weak] == ["aberration"], weak  # only the <2.5-ease, attempted word
    assert weak[0]["accuracy"] == 0.25, weak

    sugg = c.get("/words/suggested", headers=AUTH).json()
    heads = [w["headword"] for w in sugg]
    assert "cat" not in heads and "aberration" not in heads, heads  # seen words excluded
    assert heads[0] == "ubiquitous", heads  # B1 (my level) + academic ranks above A1 apple

    acc = c.get("/stats/accuracy_by_level", headers=AUTH).json()
    by = {r["level"]: r for r in acc}
    assert [r["level"] for r in acc] == ["A1", "A2", "B1", "B2", "C1", "C2"], acc  # all six, in order
    assert by["A1"]["accuracy"] == 1.0 and by["A1"]["attempts"] == 3, acc  # word 2: 3/3
    assert by["C1"]["accuracy"] == 0.25 and by["C1"]["attempts"] == 4, acc  # word 1: 1/4
    assert by["B1"]["accuracy"] is None and by["B1"]["attempts"] == 0, acc  # untried level
    print("ok:", weak, sugg, acc)


if __name__ == "__main__":
    main_test()
