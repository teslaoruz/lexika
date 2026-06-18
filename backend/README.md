# Lexika backend

FastAPI + PostgreSQL + SQLAlchemy backend for the Lexika vocab app.
Implements the MVP slice in `../CONTRACT.md` (Phase 0+1+2): dictionary lookup
with caching, word relations, decks, and SM-2 flashcard review.

No auth in this slice — every request acts as the seeded `user_id = 1`.

## Stack

- FastAPI + uvicorn (Python 3.14, managed by `uv`)
- PostgreSQL via SQLAlchemy 2.x (sync engine)
- httpx for the Free Dictionary API (`api.dictionaryapi.dev`)
- Tables created with SQLAlchemy `create_all` on startup
  (ponytail: Alembic is the upgrade path once the schema must change against real data)

## Files

| file | what |
|---|---|
| `db.py` | engine + session + `Base` |
| `models.py` | tables: users, words, word_metadata, word_family, decks, deck_cards, card_progress, review_log |
| `lookup.py` | cache-check → Dictionary API → metadata join → cache write (shared by endpoint + seed) |
| `sm2.py` | SM-2 scheduler + assert-based self-check (`uv run python sm2.py`) |
| `main.py` | FastAPI app + all endpoints |
| `seed.py` | loads sample CEFR/AWL data, word families, user 1, demo decks |
| `sample_words.csv` | committed ~160-row CEFR + academic sample (drop-in for real CEFR-J/AWL CSVs) |

## Setup

DB assumed running at `postgresql://lexika:lexika@localhost:5432/lexika`
(override with `DATABASE_URL`). The repo's `docker-compose.yml` starts it.

```sh
cd backend
uv sync                       # install deps into .venv
uv run python sm2.py          # SM-2 self-check (should print "all assertions passed")
uv run python seed.py         # create tables + seed metadata, families, user 1, demo decks
uv run python -m uvicorn main:app --reload   # serve on http://localhost:8000
```

## Endpoints (curl)

```sh
# Lookup (cache hit if seeded, else live fetch + cache). 404 for non-words.
curl "http://localhost:8000/words/lookup?word=ubiquitous"

# Relations: synonyms/antonyms (from cache) + word family / nominalization (curated table)
curl "http://localhost:8000/words/ubiquitous/relations"

# Decks for user 1
curl "http://localhost:8000/decks"

# Create a deck
curl -X POST "http://localhost:8000/decks" \
  -H "Content-Type: application/json" -d '{"name":"My deck","cefr_level":null}'

# Add a word (by id) to a deck -> 201 {"ok":true}
curl -X POST "http://localhost:8000/decks/1/cards" \
  -H "Content-Type: application/json" -d '{"word_id":2}'

# Cards due for review now
curl "http://localhost:8000/review/due?limit=20"

# Submit a grade (again|hard|good|easy) -> next_review_at + interval_days
curl -X POST "http://localhost:8000/review/submit" \
  -H "Content-Type: application/json" -d '{"word_id":2,"grade":"good"}'
```

## Deliberate shortcuts (ponytail ceilings)

- **No auth** — hardcoded `user_id = 1`. Add Firebase token verification when >1 user exists.
- **`translation_ru` / `translation_kk` / `review.translation` return `null`** — live
  RU/KK translation (Google Cloud Translate) needs a billing key; columns are in the
  schema, wire them up when a key exists.
- **`create_all` instead of Alembic** — fine for a single dev with no data to migrate.
- **synonyms/antonyms stored as JSON on `words`** — they arrive as a whole list from the
  API and are only ever read whole; normalize only if we need to query by synonym.
- **`sample_words.csv` is a hand-rolled stand-in** for the real CEFR-J + AWL datasets
  (same columns: `word,cefr_level,is_academic,frequency_rank`) — drop the real files in place.
- **game_sessions / user_stats tables skipped** — no games in this slice; add in Phase 3/4.
