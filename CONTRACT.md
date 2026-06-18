# Lexika API Contract (MVP slice — Phase 0+1+2+3)

Backend base URL: `http://localhost:8000`. All JSON. No auth in this slice —
every request acts as the seeded `user_id = 1`. (ponytail: Firebase auth deferred,
single-user until the core loop is proven. Add when more than the test user exists.)

CORS: allow all origins (dev only).

## Words

### GET /words/lookup?word={w}
Cache check (`words` table) → on miss, Free Dictionary API (api.dictionaryapi.dev) →
join `word_metadata` for cefr/academic → write cache → return.
404 if the word isn't a real word (dictionary API 404).

```json
{
  "id": 12,
  "headword": "ubiquitous",
  "phonetic": "/juːˈbɪk.wɪ.təs/",
  "audio_url": "https://.../ubiquitous.mp3",
  "part_of_speech": "adjective",
  "definition_en": "Present, appearing, or found everywhere...",
  "example_en": "Smartphones have become ubiquitous in modern classrooms.",
  "cefr_level": "B2",          // null if not in word_metadata
  "is_academic": true,
  "translations": {"ru": "повсеместный", "kk": "бәрі жерде кездесетін"},  // extra
  "synonyms": ["omnipresent", "pervasive", "widespread"],
  "antonyms": ["rare", "scarce"]
}
```
The English `definition_en` is the primary content everywhere (cards, games);
`translations` is an *extra* map `{lang_code: text}`, populated free via
deep-translator on lookup. Add a language by appending its ISO code to
`translate.py` TARGET_LANGS (e.g. `"fa"` for Persian) — no schema change — then run
`backfill_translations.py` for already-cached rows.

### GET /words/{word}/relations
synonyms/antonyms from cached dictionary response; word_family + nominalization from
the curated `word_family` table (empty arrays / null if not seeded — never invent).

```json
{
  "synonyms": ["omnipresent", "pervasive"],
  "antonyms": ["rare", "scarce"],
  "word_family": [{"word": "ubiquity", "pos": "noun"}, {"word": "ubiquitously", "pos": "adv"}],
  "nominalization": {            // null if not seeded
    "base_pos": "adj", "base_example": "Smartphones are ubiquitous in classrooms now.",
    "noun_word": "ubiquity",     "noun_example": "The ubiquity of smartphones changed classrooms."
  }
}
```

## Decks

### GET /decks  → array
```json
[{"id":1,"name":"Social media unit","card_count":28,"due_count":18,"is_system_deck":false}]
```
### POST /decks  body `{"name":"...","cefr_level":null}` → created deck object
### POST /decks/{id}/cards  body `{"word_id":12}` → 201, `{"ok":true}`
   (auto-create-by-level deck flow can come later; explicit deck id for now)

## Review (SM-2)

### GET /review/due?limit=20  → array of cards due now (next_review_at <= now), newest words included
`definition_en` is the card's content; `translation` is the user's native-language
extra (null if we don't have that language).
```json
[{"word_id":12,"headword":"candid","phonetic":"/ˈkæn.dɪd/","audio_url":"...",
  "definition_en":"...","translation":"откровенный","example_en":"..."}]
```
### POST /review/submit  body `{"word_id":12,"grade":"good","game_type":"quiz"}`
grade ∈ again|hard|good|easy. `game_type` optional (default `flashcard`), ∈
flashcard|matching|listening|typing|quiz — games map a correct answer to `good`,
a wrong one to `again`, and tag the `review_log` row. 422 on an unknown game_type.
SM-2 update of `card_progress`, plus XP award + daily streak roll (Phase 3).
→ `{"next_review_at":"2026-06-21T...","interval_days":4,"xp_earned":18,"total_xp":45,"current_streak":1}`

ponytail: no separate `game_sessions` table yet — `review_log.game_type` carries the
per-answer signal. Add `game_sessions` when Phase 7 leaderboards need per-session scores.

SM-2 reference: ease starts 2.5; again→reset reps, interval 0 (≈<1m); hard→interval*1.2,
ease-0.15; good→standard sequence (1d, 6d, interval*ease); easy→interval*ease*1.3, ease+0.15.
Ease floor 1.3. Keep it in one well-commented function with an assert-based self-check.

## Stats (Phase 3 — gamification)

### GET /stats  → user's gamification totals
```json
{"current_streak":1,"longest_streak":1,"total_xp":45,"total_words_learned":12}
```
XP per correct review = grade base (again 0 / hard 5 / good 10 / easy 15) × CEFR
multiplier (A1 1.0 … C2 2.6); see `gamify.py`. Streak increments once per calendar
day of review, resets if a day is missed. `total_words_learned` = card_progress rows
with `repetitions >= 2` (computed on read, not stored).

## Seed (runs once on `make seed` / startup)
- Load CEFR-J wordlist CSV + AWL list into `word_metadata(word, cefr_level, is_academic, frequency_rank)`.
- Load AWL word-family groupings into `word_family`.
- Create `user_id=1` test user (native_language='ru') and a couple of demo decks so the UI isn't empty.
ponytail: if the CEFR-J / AWL source files aren't bundled, ship a small committed sample
CSV (a few hundred rows) so the app runs offline; full dataset is a drop-in replacement.
