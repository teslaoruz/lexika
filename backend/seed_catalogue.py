"""Seed ONLY the reference word catalogue — no demo user, no demo decks.

Run once against a fresh database (creates tables if missing):

    DATABASE_URL="postgresql://...?sslmode=require" uv run python seed_catalogue.py

Loads the CEFR/AWL word list (for autocomplete + level tagging) and the curated
word families. Safe to re-run: existing rows are skipped.
"""
from db import SessionLocal, Base, engine
from seed import load_metadata, load_families

Base.metadata.create_all(engine)
db = SessionLocal()
try:
    load_metadata(db)
    load_families(db)
finally:
    db.close()
print("catalogue seeded.")
