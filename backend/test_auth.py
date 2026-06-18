"""ponytail self-check for auth: register -> token works on a gated endpoint,
login rotates the token, and gated endpoints 401 without a valid bearer token.
Runs against in-memory SQLite. Run: uv run python test_auth.py"""
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

import main  # noqa: E402  (after the engine swap)
from models import Word  # noqa: E402


def main_test():
    Base.metadata.create_all(engine)
    c = TestClient(main.app)

    # gated endpoint refuses an anonymous request
    assert c.get("/stats").status_code == 401
    assert c.get("/stats", headers={"Authorization": "Bearer nope"}).status_code == 401

    # register -> token unlocks the gated endpoint, scoped to the new user
    r = c.post("/auth/register", json={"email": "A@x.io", "password": "pw123456"})
    assert r.status_code == 200, r.text
    tok = r.json()["token"]
    assert r.json()["user"]["email"] == "a@x.io"  # normalized lowercase
    assert c.get("/stats", headers={"Authorization": f"Bearer {tok}"}).status_code == 200

    # duplicate email rejected
    assert c.post("/auth/register", json={"email": "a@x.io", "password": "pw123456"}).status_code == 409

    # password floor (< 8 chars) rejected at the trust boundary
    assert c.post("/auth/register", json={"email": "short@x.io", "password": "1234567"}).status_code == 422

    # wrong password rejected; correct login rotates the token (old one dies)
    assert c.post("/auth/login", json={"email": "a@x.io", "password": "bad"}).status_code == 401
    tok2 = c.post("/auth/login", json={"email": "a@x.io", "password": "pw123456"}).json()["token"]
    assert tok2 != tok
    assert c.get("/stats", headers={"Authorization": f"Bearer {tok}"}).status_code == 401  # rotated out
    assert c.get("/stats", headers={"Authorization": f"Bearer {tok2}"}).status_code == 200

    # decks are per-user: a second user starts empty
    tok_b = c.post("/auth/register", json={"email": "b@x.io", "password": "pw123456"}).json()["token"]
    c.post("/decks", headers={"Authorization": f"Bearer {tok2}"}, json={"name": "Mine"})
    a_decks = c.get("/decks", headers={"Authorization": f"Bearer {tok2}"}).json()
    b_decks = c.get("/decks", headers={"Authorization": f"Bearer {tok_b}"}).json()
    assert any(d["name"] == "Mine" for d in a_decks)
    assert not any(d["name"] == "Mine" for d in b_decks)

    # IDOR: user B cannot add a card to user A's deck (hidden as 404)
    s = db.SessionLocal()
    s.add(Word(id=1, headword="cat", definition_en="an animal"))
    s.commit()
    s.close()
    deck = c.post("/decks", headers={"Authorization": f"Bearer {tok2}"}, json={"name": "A deck"}).json()
    r = c.post(f"/decks/{deck['id']}/cards", headers={"Authorization": f"Bearer {tok_b}"}, json={"word_id": 1})
    assert r.status_code == 404, r.text
    owned = c.post(f"/decks/{deck['id']}/cards", headers={"Authorization": f"Bearer {tok2}"}, json={"word_id": 1})
    assert owned.status_code == 201, owned.text

    # brute-force throttle: 5 failed logins, then 429
    for _ in range(5):
        assert c.post("/auth/login", json={"email": "throttle@x.io", "password": "bad"}).status_code == 401
    assert c.post("/auth/login", json={"email": "throttle@x.io", "password": "bad"}).status_code == 429
    print("auth endpoint self-check ok")


if __name__ == "__main__":
    main_test()
