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


def setup():
    Base.metadata.create_all(engine)
    s = TestSession()
    s.add(User(id=1, native_language="ru", current_level="B1"))
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

    weak = c.get("/words/weak").json()
    assert [w["headword"] for w in weak] == ["aberration"], weak  # only the <2.5-ease, attempted word
    assert weak[0]["accuracy"] == 0.25, weak

    sugg = c.get("/words/suggested").json()
    heads = [w["headword"] for w in sugg]
    assert "cat" not in heads and "aberration" not in heads, heads  # seen words excluded
    assert heads[0] == "ubiquitous", heads  # B1 (my level) + academic ranks above A1 apple
    print("ok:", weak, sugg)


if __name__ == "__main__":
    main_test()
