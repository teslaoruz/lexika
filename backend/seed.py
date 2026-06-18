"""Seed script — run once: `uv run python seed.py`.

Loads:
  - sample_words.csv (CEFR + AWL flags) -> word_metadata
  - a handful of curated word_family rows -> word_family
  - user_id=1 (native_language='ru')
  - 2-3 demo decks populated with real looked-up words (calls the live lookup
    logic so the frontend isn't empty on first run)

ponytail: sample_words.csv is a committed ~160-row stand-in. Drop the real
CEFR-J + AWL CSVs (same columns) in its place for full coverage.
"""
import csv
import os

from sqlalchemy import select

from db import engine, Base, SessionLocal
from models import User, WordMetadata, WordFamily, Deck, DeckCard, CardProgress, utcnow
from lookup import get_or_fetch_word, WordNotFound

HERE = os.path.dirname(os.path.abspath(__file__))

# Curated word families (base_word -> related forms), AWL-style groupings.
# Each tuple: (base, related, relation_type, example_sentence)
WORD_FAMILIES = [
    # decide / decision / decisive / decisively
    ("decide", "decide", "verb_form", "The committee will decide tomorrow."),
    ("decide", "decision", "noun_form", "The committee's decision is expected tomorrow."),
    ("decide", "decisive", "adj_form", "She gave a decisive answer."),
    ("decide", "decisively", "adv_form", "He acted decisively."),
    # analyse / analysis / analytical
    ("analyse", "analyse", "verb_form", "Researchers analyse the data carefully."),
    ("analyse", "analysis", "noun_form", "The analysis of the data took weeks."),
    ("analyse", "analytical", "adj_form", "She has an analytical mind."),
    # ubiquitous / ubiquity / ubiquitously
    ("ubiquitous", "ubiquitous", "adj_form", "Smartphones are ubiquitous in classrooms now."),
    ("ubiquitous", "ubiquity", "noun_form", "The ubiquity of smartphones changed classrooms."),
    ("ubiquitous", "ubiquitously", "adv_form", "Plastic is used ubiquitously."),
    # important / importance
    ("important", "important", "adj_form", "This step is important."),
    ("important", "importance", "noun_form", "The importance of this step is clear."),
]

DEMO_DECKS = [
    ("Social media unit", ["candid", "ubiquitous", "subtle", "famous", "comment"]),
    ("Academic writing B2", ["analyse", "significant", "framework", "hypothesis", "derive"]),
    ("Everyday words", ["water", "house", "friend", "happy", "decide"]),
]


def load_metadata(db):
    path = os.path.join(HERE, "sample_words.csv")
    with open(path) as f:
        reader = csv.DictReader(f)
        count = 0
        for row in reader:
            w = row["word"].strip().lower()
            if db.get(WordMetadata, w):
                continue
            db.add(WordMetadata(
                word=w,
                cefr_level=row["cefr_level"] or None,
                is_academic=row["is_academic"] in ("1", "true", "True"),
                frequency_rank=int(row["frequency_rank"]) if row["frequency_rank"] else None,
            ))
            count += 1
    db.commit()
    print(f"  word_metadata: +{count} rows")


def load_families(db):
    if db.query(WordFamily).count():
        print("  word_family: already seeded, skipping")
        return
    for base, rel, rtype, ex in WORD_FAMILIES:
        db.add(WordFamily(base_word=base, related_word=rel, relation_type=rtype, example_sentence=ex))
    db.commit()
    print(f"  word_family: +{len(WORD_FAMILIES)} rows")


def ensure_user(db):
    """Demo login so existing decks/progress are reachable. Returns the user id.
    ponytail: don't hardcode id=1 — an explicit PK doesn't advance the SERIAL
    sequence, so the first real /auth/register would collide on id=1. Let it
    autoincrement and key the demo user by email instead."""
    from auth import hash_password, new_token
    u = db.scalar(select(User).where(User.email == "demo@lexika.app"))
    if not u:
        u = db.get(User, 1)  # legacy pre-auth seeded user (no email)
    if not u:
        u = User(
            display_name="Test User", native_language="ru", current_level="B1",
            email="demo@lexika.app", auth_provider="password",
            password_hash=hash_password("demo1234"), token=new_token(),
        )
        db.add(u)
        db.commit()
        db.refresh(u)
        print(f"  users: created demo user id={u.id}  (demo@lexika.app / demo1234)")
    elif not u.password_hash:  # backfill login onto a pre-auth seeded user
        u.email = u.email or "demo@lexika.app"
        u.auth_provider = "password"
        u.password_hash = hash_password("demo1234")
        u.token = new_token()
        db.commit()
        print(f"  users: added demo login to user id={u.id}  (demo@lexika.app / demo1234)")
    else:
        print(f"  users: demo user id={u.id} already exists")
    return u.id


def seed_decks(db, user_id):
    import httpx
    if db.query(Deck).count():
        print("  decks: already seeded, skipping")
        return
    client = httpx.Client(timeout=20)
    try:
        for name, words in DEMO_DECKS:
            deck = Deck(user_id=user_id, name=name)
            db.add(deck)
            db.commit()
            db.refresh(deck)
            added = 0
            for w in words:
                try:
                    word = get_or_fetch_word(db, w, client=client)
                except (WordNotFound, Exception) as e:  # noqa: BLE001 - network may fail offline
                    print(f"    skip {w!r}: {type(e).__name__}")
                    db.rollback()
                    continue
                db.add(DeckCard(deck_id=deck.id, word_id=word.id))
                # make it reviewable immediately
                if not db.query(CardProgress).filter_by(user_id=user_id, word_id=word.id).first():
                    db.add(CardProgress(user_id=user_id, word_id=word.id, next_review_at=utcnow()))
                db.commit()
                added += 1
            print(f"  deck {name!r}: {added} cards")
    finally:
        client.close()


def main():
    Base.metadata.create_all(engine)
    db = SessionLocal()
    try:
        print("Seeding Lexika...")
        load_metadata(db)
        load_families(db)
        uid = ensure_user(db)
        seed_decks(db, uid)
        print("Done.")
    finally:
        db.close()


if __name__ == "__main__":
    main()
