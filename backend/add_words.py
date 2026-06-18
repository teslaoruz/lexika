"""Additively add a batch of words to a deck, due for review now.

Unlike seed.py this never wipes — re-runnable, skips words already in the deck.
Run: `uv run python add_words.py`. Edit WORDS / DECK_NAME to taste.
"""
import httpx

from db import SessionLocal
from models import Deck, DeckCard, CardProgress, utcnow
from lookup import get_or_fetch_word, WordNotFound

USER_ID = 1
DECK_NAME = "Academic & advanced"
WORDS = [
    "diligent", "coherent", "ambiguous", "pragmatic", "meticulous", "profound",
    "prevalent", "robust", "deliberate", "intricate", "concise", "redundant",
    "feasible", "nuance", "arbitrary", "ephemeral", "resilient", "scarce",
    "vivid", "prominent", "candid", "subtle", "inevitable", "tedious",
]


def main():
    db = SessionLocal()
    client = httpx.Client(timeout=20)
    try:
        deck = db.query(Deck).filter_by(user_id=USER_ID, name=DECK_NAME).first()
        if not deck:
            deck = Deck(user_id=USER_ID, name=DECK_NAME)
            db.add(deck)
            db.commit()
            db.refresh(deck)
            print(f"created deck {DECK_NAME!r}")

        added = 0
        for w in WORDS:
            try:
                word = get_or_fetch_word(db, w, client=client)
            except (WordNotFound, Exception) as e:  # noqa: BLE001 - network may fail
                print(f"  skip {w!r}: {type(e).__name__}")
                db.rollback()
                continue
            if db.query(DeckCard).filter_by(deck_id=deck.id, word_id=word.id).first():
                continue  # already in this deck
            db.add(DeckCard(deck_id=deck.id, word_id=word.id))
            if not db.query(CardProgress).filter_by(user_id=USER_ID, word_id=word.id).first():
                db.add(CardProgress(user_id=USER_ID, word_id=word.id, next_review_at=utcnow()))
            db.commit()
            added += 1
            print(f"  + {word.headword}  ({word.cefr_level or '-'})")
        print(f"done — added {added} new word(s) to {DECK_NAME!r}.")
    finally:
        client.close()
        db.close()


if __name__ == "__main__":
    main()
