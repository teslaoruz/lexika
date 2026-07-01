"""ponytail self-check for the multi-class + shared-deck changes:
- a student can belong to several classes,
- a deck is shared *to a class* (not copied), seen live by current and future
  members, and teacher edits (new words) propagate,
- delete-word, leave-class, and delete-class do what they say.
Run: uv run python test_classes.py
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
db.engine = engine
db.SessionLocal = sessionmaker(bind=engine)

import main  # noqa: E402  (after engine swap)
from models import Word  # noqa: E402


def _h(tok):
    return {"Authorization": f"Bearer {tok}"}


def _reg(c, email):
    return c.post("/auth/register", json={"email": email, "password": "pw123456"}).json()["token"]


def main_test():
    Base.metadata.create_all(engine)
    c = TestClient(main.app)
    teacher, s1, s2 = _reg(c, "t@x.io"), _reg(c, "s1@x.io"), _reg(c, "s2@x.io")

    s = db.SessionLocal()
    s.add(Word(id=1, headword="alpha", definition_en="a"))
    s.add(Word(id=2, headword="beta", definition_en="b"))
    s.commit()
    s.close()

    # teacher makes a deck with one word
    deck = c.post("/decks", headers=_h(teacher), json={"name": "Unit 1"}).json()
    did = deck["id"]
    c.post(f"/decks/{did}/cards", headers=_h(teacher), json={"word_id": 1})

    # two classes; a student can be in both
    ca = c.post("/cohorts", headers=_h(teacher), json={"name": "A"}).json()
    cb = c.post("/cohorts", headers=_h(teacher), json={"name": "B"}).json()
    assert c.post("/cohorts/join", headers=_h(s1), json={"code": ca["join_code"]}).status_code == 200
    assert c.post("/cohorts/join", headers=_h(s1), json={"code": cb["join_code"]}).status_code == 200
    assert len(c.get("/cohorts/mine", headers=_h(s1)).json()["classes"]) == 2

    # share the deck to class A → s1 (already a member) sees it live & read-only
    r = c.post(f"/cohorts/{ca['id']}/decks", headers=_h(teacher), json={"deck_id": did})
    assert r.status_code == 200 and r.json()["shared_to"] == 1, r.text
    s1_decks = c.get("/decks", headers=_h(s1)).json()
    shared = next(d for d in s1_decks if d["id"] == did)
    assert shared["is_shared"] and shared["is_system_deck"], shared
    # seeded into review queue
    assert any(rc["word_id"] == 1 for rc in c.get("/review/due", headers=_h(s1)).json())

    # s2 joins class A *after* sharing → still sees the deck + its word
    c.post("/cohorts/join", headers=_h(s2), json={"code": ca["join_code"]})
    assert any(d["id"] == did for d in c.get("/decks", headers=_h(s2)).json())
    assert any(rc["word_id"] == 1 for rc in c.get("/review/due", headers=_h(s2)).json())

    # teacher edits the shared deck (adds beta) → propagates to members
    c.post(f"/decks/{did}/cards", headers=_h(teacher), json={"word_id": 2})
    assert any(rc["word_id"] == 2 for rc in c.get("/review/due", headers=_h(s1)).json())
    assert any(rc["word_id"] == 2 for rc in c.get("/review/due", headers=_h(s2)).json())

    # delete a word from the deck (teacher only, own deck)
    assert c.delete(f"/decks/{did}/cards/2", headers=_h(teacher)).status_code == 204
    assert all(w["word_id"] != 2 for w in c.get(f"/decks/{did}/cards", headers=_h(teacher)).json())
    # a student can't delete words from a shared deck
    assert c.delete(f"/decks/{did}/cards/1", headers=_h(s1)).status_code == 404

    # leave one class → left with one; teacher can't leave own class
    assert c.post(f"/cohorts/{cb['id']}/leave", headers=_h(s1)).status_code == 204
    assert len(c.get("/cohorts/mine", headers=_h(s1)).json()["classes"]) == 1
    assert c.post(f"/cohorts/{ca['id']}/leave", headers=_h(teacher)).status_code == 400

    # class detail shows members + shared decks
    detail = c.get(f"/cohorts/{ca['id']}", headers=_h(teacher)).json()
    assert detail["is_teacher"] and len(detail["decks"]) == 1
    assert {m["display_name"] for m in detail["members"]} == {"t", "s1", "s2"}

    # delete the class → gone, members no longer see it
    assert c.delete(f"/cohorts/{ca['id']}", headers=_h(teacher)).status_code == 204
    assert c.get(f"/cohorts/{ca['id']}", headers=_h(teacher)).status_code == 404
    assert c.get("/cohorts/mine", headers=_h(s2)).json()["classes"] == []

    # delete account wipes the user
    assert c.delete("/auth/me", headers=_h(s2)).status_code == 204
    assert c.get("/auth/me", headers=_h(s2)).status_code == 401

    print("classes + shared-deck self-check ok")


if __name__ == "__main__":
    main_test()
