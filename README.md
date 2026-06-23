# Lexika

A playful, Duolingo-style app for learning English vocabulary, aimed at
Russian / Kazakh / Persian speakers. Look up any English word, save it to a
deck, and lock it in with spaced-repetition flashcards and mini-games.

- **Client** — Flutter (web, iOS, Android from one codebase)
- **Backend** — FastAPI + PostgreSQL
- **API contract** — [`CONTRACT.md`](CONTRACT.md) (also live at `/docs` when the backend runs)

---

## Features

- **Dictionary lookup** — definition, phonetics, audio, examples, synonyms/antonyms,
  CEFR level, and a word-family panel. Results are cached, then enriched from the
  free [Dictionary API](https://dictionaryapi.dev) and [Datamuse](https://datamuse.com).
- **Spelling fallback** — a misspelled search (`recieve`) resolves to the right
  word (`receive`); genuine non-words still return “not found”.
- **Translations** — each word carries a small native-language translation
  (`ru` / `kk` / `fa`), filled automatically. The English definition stays the focus.
- **Decks** — save words into decks, browse a deck's words, and **practice a single
  deck** as a flashcard session.
- **Spaced repetition** — SM-2 scheduling. Review due cards, swipe Again/Good,
  grade Hard/Easy.
- **Mini-games** — matching, listening, typing, and multiple-choice, all feeding the
  same SM-2 + XP pipeline.
- **Gamification** — XP (graded by CEFR level), daily streaks, and a Progress
  dashboard with accuracy-by-level.
- **Classes** — students join a class with a code; the creator (teacher) gets a
  per-student progress dashboard and a weekly-XP leaderboard.
- **Light & dark mode**, plus right-to-left rendering for Persian.

---

## Architecture

```
app/        Flutter client
  lib/
    api/        HTTP client, models, Riverpod providers
    features/   one folder per screen (auth, lookup, decks, review, games, …)
    theme/      colors + typography (light/dark aware)
    widgets/    shared UI

backend/    FastAPI service
  main.py       routes
  models.py     SQLAlchemy ORM
  auth.py       pbkdf2 hashing + bearer-token auth
  lookup.py     dictionary fetch + enrichment + spelling fallback
  translate.py  free EN→ru/kk/fa translation
  sm2.py        spaced-repetition scheduler
  seed.py       loads the word catalogue (CEFR/AWL) from sample_words.csv
```

State is managed with Riverpod on the client. The backend is a thin, synchronous
FastAPI app over SQLAlchemy; the schema is created on startup (no migration tool —
small idempotent `ALTER`/`CREATE INDEX` statements cover the few changes since).

---

## Local development

### Prerequisites
- [Docker](https://docs.docker.com/get-docker/) (for Postgres)
- [uv](https://docs.astral.sh/uv/) (Python deps & runner) — Python ≥ 3.14
- [Flutter](https://docs.flutter.dev/get-started/install)

### Run it
```sh
# 1. Postgres
docker compose up -d

# 2. Backend — first run seeds the word catalogue
cd backend
uv sync
uv run python seed.py          # one-time: load the CEFR word catalogue
uv run python -m uvicorn main:app --port 8000

# 3. Flutter client (new terminal)
cd app
flutter run -d chrome
```

The client defaults to `http://localhost:8000`. Open the Swagger UI at
<http://localhost:8000/docs>.

### Configuration (environment variables)

| Variable | Used by | Default | Notes |
|---|---|---|---|
| `DATABASE_URL` | backend | `postgresql://lexika:lexika@localhost:5432/lexika` | Add `?sslmode=require` for managed Postgres. |
| `LEXIKA_ALLOWED_ORIGINS` | backend | `http://localhost:8080,http://127.0.0.1:8080` | Comma-separated CORS allowlist; set to your web origin in prod. |
| `API_BASE` | Flutter (build-time) | per-platform localhost | Pass at build: `--dart-define=API_BASE=https://api.example.com`. |

### Tests
```sh
cd backend && uv run pytest          # endpoint + auth tests
cd app && flutter analyze            # static analysis
```

---

## API

The full request/response contract lives in [`CONTRACT.md`](CONTRACT.md) and the
interactive Swagger UI is served at `/docs`. Auth is a bearer token issued by
`/auth/register` and `/auth/login`; the client attaches it to every request and
restores the session on launch via `/auth/me`.

---

## Deployment

The Flutter web build is static files (host anywhere); the backend is a container
with a Postgres database. See **Deployment** notes for cheapest hosting options.

---

## License

See [`PRIVACY.md`](PRIVACY.md) and [`TERMS.md`](TERMS.md).
