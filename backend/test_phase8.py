"""ponytail self-check for Phase 8: autocomplete (/words/suggest) + lookup
enrichment (examples/synonyms + CEFR/word-family heuristics). Runs the real
query logic against an in-memory SQLite — no network. Run:
    uv run python test_phase8.py
"""
from sqlalchemy import create_engine
from sqlalchemy.pool import StaticPool
from sqlalchemy.orm import sessionmaker
from fastapi.testclient import TestClient

import db
from db import Base

engine = create_engine(
    "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
)
TestSession = sessionmaker(bind=engine)
db.engine = engine
db.SessionLocal = TestSession

import main  # noqa: E402  (must follow the engine swap)
import lookup  # noqa: E402
from models import Word, WordMetadata, WordFamily  # noqa: E402


def setup():
    Base.metadata.create_all(engine)
    s = TestSession()
    # A known, fully-enriched seeded word (as lookup.py would persist it).
    s.add(Word(
        id=1, headword="ubiquitous", definition_en="found everywhere",
        example_en="Smartphones are ubiquitous in classrooms.",
        cefr_level="B2",
        synonyms_json=["omnipresent", "pervasive"], antonyms_json=["rare", "scarce"],
    ))
    s.add(Word(id=2, headword="aberration", definition_en="a departure"))
    s.add_all([
        WordMetadata(word="ubiquitous", frequency_rank=5000),
        WordMetadata(word="aberration", frequency_rank=8000),
        WordMetadata(word="aberrant", frequency_rank=9000),
        WordMetadata(word="abet", frequency_rank=100),  # different prefix bucket
    ])
    s.add(WordFamily(base_word="ubiquitous", related_word="ubiquity", relation_type="related"))
    s.commit()
    s.close()


def main_test():
    setup()
    c = TestClient(main.app)

    # ---- /words/suggest: prefix match, ordering, limit, empty query ----
    # Local catalogue words come first and keep their freq_rank order; Datamuse may
    # append more real completions (network-dependent), so assert on the prefix.
    sugg = c.get("/words/suggest", params={"q": "aber"}).json()
    assert sugg[:2] == ["aberration", "aberrant"], sugg  # freq_rank order, local-first

    assert c.get("/words/suggest", params={"q": ""}).json() == []  # blank -> []
    assert c.get("/words/suggest", params={"q": "   "}).json() == []  # whitespace -> []

    capped = c.get("/words/suggest", params={"q": "a", "limit": 2}).json()
    assert len(capped) == 2, capped  # honours limit
    assert c.get("/words/suggest", params={"q": "a", "limit": 99}).status_code == 422  # max 20

    # case-insensitive
    assert c.get("/words/suggest", params={"q": "ABER"}).json()[:2] == ["aberration", "aberrant"]

    # ordering: ubiquitous(5000) before aberration(8000) when both match "a"? no shared
    # prefix; check rank ordering within the 'aber' set already covered. Now whole-set:
    alls = c.get("/words/suggest", params={"q": "a"}).json()
    assert alls[0] == "abet", alls  # rank 100 ranks first

    # ---- lookup enrichment surfaces for a known seeded word ----
    look = c.get("/words/lookup", params={"word": "ubiquitous"}).json()
    assert look["example_en"], look           # example sentence present
    assert "omnipresent" in look["synonyms"]  # synonyms present
    assert "rare" in look["antonyms"]
    assert look["cefr_level"] == "B2"

    rel = c.get("/words/ubiquitous/relations").json()
    assert rel["synonyms"] == ["omnipresent", "pervasive"], rel
    assert any(f["word"] == "ubiquity" for f in rel["word_family"]), rel  # derived family surfaces

    # ---- CEFR-from-frequency heuristic ----
    assert lookup._cefr_from_freq(500) == "A1"
    assert lookup._cefr_from_freq(0.05) == "C2"
    assert lookup._cefr_from_freq(None) is None

    print("ok: suggest + enrichment self-check passed")


if __name__ == "__main__":
    main_test()
