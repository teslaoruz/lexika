"""One-time: fill translation_ru/kk on already-cached `words` rows (the demo decks
seeded before translation was wired in). Safe to re-run — only touches null rows.
Run after seeding: `uv run python backfill_translations.py`.
"""
from sqlalchemy import select, or_

from db import SessionLocal
from models import Word
from translate import translate


def main():
    db = SessionLocal()
    try:
        rows = db.scalars(
            select(Word).where(
                or_(Word.translation_ru.is_(None), Word.translation_kk.is_(None))
            )
        ).all()
        print(f"backfilling {len(rows)} word(s)...")
        for w in rows:
            if w.translation_ru is None:
                w.translation_ru = translate(w.headword, "ru")
            if w.translation_kk is None:
                w.translation_kk = translate(w.headword, "kk")
            print(f"  {w.headword}: ru={w.translation_ru!r} kk={w.translation_kk!r}")
        db.commit()
        print("done.")
    finally:
        db.close()


if __name__ == "__main__":
    main()
