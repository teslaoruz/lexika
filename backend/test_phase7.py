"""ponytail self-check for Phase 7: create a cohort, join by code, and a weekly
leaderboard scoped to members with XP recomputed from review_log.
Run: uv run python test_phase7.py"""
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
from models import Word, CardProgress  # noqa: E402


def _h(tok):
    return {"Authorization": f"Bearer {tok}"}


def _register(c, email):
    return c.post("/auth/register", json={"email": email, "password": "pw123456"}).json()["token"]


def main_test():
    Base.metadata.create_all(engine)
    c = TestClient(main.app)
    a, b, lone = _register(c, "a@x.io"), _register(c, "b@x.io"), _register(c, "c@x.io")

    # a B2 word (good=18 XP, hard=5 XP per gamify.xp_for) + progress rows for the
    # two students, exactly as the app sets up via add_card before reviewing.
    s = db.SessionLocal()
    s.add(Word(id=1, headword="ubiquitous", definition_en="everywhere", cefr_level="B2"))
    s.add_all([CardProgress(user_id=1, word_id=1), CardProgress(user_id=2, word_id=1)])
    s.commit()
    s.close()

    # A creates a class (and is auto-joined); B joins with the code
    co = c.post("/cohorts", headers=_h(a), json={"name": "Class A"})
    assert co.status_code == 201, co.text
    cid, code = co.json()["id"], co.json()["join_code"]
    assert co.json()["member_count"] == 1
    assert c.post("/cohorts/join", headers=_h(b), json={"code": code.lower()}).json()["member_count"] == 2
    assert c.post("/cohorts/join", headers=_h(b), json={"code": "ZZZZZZ"}).status_code == 404
    mine = c.get("/cohorts/mine", headers=_h(a)).json()["classes"]
    assert len(mine) == 1 and mine[0]["member_count"] == 2

    # earn XP on the B2 word: A good = round(10*1.8)=18, B hard = round(5*1.8)=9
    c.post("/review/submit", headers=_h(a), json={"word_id": 1, "grade": "good"})
    c.post("/review/submit", headers=_h(b), json={"word_id": 1, "grade": "hard"})

    lb = c.get(f"/cohorts/{cid}/leaderboard", headers=_h(a)).json()
    assert lb["cohort"]["member_count"] == 2
    rows = lb["entries"]
    assert [r["rank"] for r in rows] == [1, 2]
    assert rows[0]["display_name"] == "a" and rows[0]["weekly_xp"] == 18 and rows[0]["is_me"]
    assert rows[1]["display_name"] == "b" and rows[1]["weekly_xp"] == 9 and not rows[1]["is_me"]

    # a user not in the class can't see its leaderboard
    assert c.get(f"/cohorts/{cid}/leaderboard", headers=_h(lone)).status_code == 403

    # teacher dashboard: only the creator (A) may view students; B (a member)
    # and lone (no class) are both forbidden.
    ts = c.get(f"/cohorts/{cid}/students", headers=_h(a))
    assert ts.status_code == 200, ts.text
    data = ts.json()
    assert data["cohort"]["member_count"] == 2
    rows = data["students"]
    assert [r["weekly_xp"] for r in rows] == [18, 9]  # sorted desc, same window as leaderboard
    teacher = next(r for r in rows if r["display_name"] == "a")
    assert teacher["is_teacher"] and teacher["total_xp"] == 18
    assert next(r for r in rows if r["display_name"] == "b")["is_teacher"] is False
    assert c.get(f"/cohorts/{cid}/students", headers=_h(b)).status_code == 403  # member, not teacher
    assert c.get(f"/cohorts/{cid}/students", headers=_h(lone)).status_code == 403  # no class
    print("phase 7 self-check ok")


if __name__ == "__main__":
    main_test()
