# Lexika

English-vocab learning app (Duolingo-style) for Russian/Kazakh students.
Flutter client + FastAPI/Postgres backend. See `lexika-build-plan.md` for the
full plan and `CONTRACT.md` for the API.

## What's built (Phase 0 + 1 + 2 — the running core loop)
Dictionary lookup (cache → Free Dictionary API → CEFR/AWL tag), word-relations
panel, decks, and SM-2 flashcard review. Design system + bounce motion + 3D flip
card, with Apple liquid-glass material on the chrome (nav, streak pill, review
overlay) over the playful opaque cards.

## Run it (3 terminals)
```sh
# 1. Postgres
docker compose up -d

# 2. Backend  (first run: seed the DB)
cd backend && uv sync && uv run python seed.py && uv run uvicorn main:app --port 8000

# 3. Flutter web client
cd app && flutter run -d chrome
```

## Deferred on purpose (ponytail — add when the core loop is proven)
Firebase auth (single seeded user_id=1 for now) · RU/KK translation (needs a
Google Translate key) · the 4-game suite · gamification/XP/streaks backend ·
leaderboards · TTS audio · progress charts · Redis · Alembic. Schema columns and
UI slots for translations already exist and return null gracefully.
