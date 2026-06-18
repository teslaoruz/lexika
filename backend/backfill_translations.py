"""Fill any missing TARGET_LANGS keys in each cached word's `translations` map.

Run after adding a new language to translate.py's TARGET_LANGS (e.g. "fa"), to
populate it for words that were cached before. Safe to re-run — only fetches the
languages a row is missing. Run: `uv run python backfill_translations.py`.
"""
from sqlalchemy import select
from sqlalchemy.orm.attributes import flag_modified

from db import SessionLocal
from models import Word
from translate import TARGET_LANGS, translate


def main():
    db = SessionLocal()
    try:
        rows = db.scalars(select(Word)).all()
        filled = 0
        for w in rows:
            current = dict(w.translations or {})
            missing = [c for c in TARGET_LANGS if c not in current]
            if not missing:
                continue
            for code in missing:
                t = translate(w.headword, code)
                if t:
                    current[code] = t
            w.translations = current
            flag_modified(w, "translations")  # JSON dict mutation isn't auto-tracked
            filled += 1
            print(f"  {w.headword}: {current}")
        db.commit()
        print(f"done — updated {filled} word(s).")
    finally:
        db.close()


if __name__ == "__main__":
    main()
