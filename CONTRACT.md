# Lexika API Contract (MVP slice — Phase 0+1+2+3 + auth)

Backend base URL: `http://localhost:8000`. All JSON.

**Auth:** email + password. `POST /auth/register` or `/auth/login` returns a
bearer `token`; send it as `Authorization: Bearer <token>` on every user-scoped
request (decks, review, stats, weak, suggested). `/words/lookup` and
`/words/{w}/relations` are open (shared dictionary cache, not per-user).
ponytail: backend-issued opaque token (no JWT lib), one session per user; the
Firebase drop-in point is `auth.current_user` — swap the DB token lookup for
Firebase ID-token verification and no endpoint changes. Seeded demo login:
`demo@lexika.app` / `demo1234` (owns the seeded decks/progress).

CORS: allow all origins (dev only).

## Auth

### POST /auth/register  body `{"email","password","native_language"?,"display_name"?}`
409 if email taken, 422 if email/password blank. → `{"token","user":{id,email,display_name,native_language,current_level}}`
### POST /auth/login  body `{"email","password"}`
401 on bad credentials. Rotates the token. → same shape as register.
### GET /auth/me  → the current user object (requires bearer token).
### POST /auth/profile  body `{"display_name"?,"native_language"?,"avatar"?,"current_level"?}`
Updates only the fields sent (non-null) → returns the updated user object. `avatar`
is a pre-set emoji string chosen client-side (not an upload). The user object now
also carries `avatar`. Translations are generated for `native_language` ∈ {ru, kk, fa}.

## Words

### GET /words/suggest?q={prefix}&limit=8
Autocomplete. Returns a JSON **array of headword strings** prefix-matching `q`
(case-insensitive), ordered by `frequency_rank` (nulls last) then alphabetically,
capped at `limit` (default 8, max 20). Sources `word_metadata` unioned with cached
`words`. Blank/whitespace `q` → `[]`. Open (no auth), like `/words/lookup`.
```json
["aberration", "aberrant"]
```

### GET /words/lookup?word={w}
Cache check (`words` table) → on miss, Free Dictionary API (api.dictionaryapi.dev) →
join `word_metadata` for cefr/academic → **enrich** (see below) → write cache → return.
404 if the word isn't a real word (dictionary API 404).

Enrichment on cache miss (best-effort, never blocks the lookup): `example_en` and
`synonyms`/`antonyms` come from the Dictionary API response; if synonyms/antonyms are
thin or `cefr_level` is unknown, Datamuse (api.datamuse.com, keyless) fills them —
synonyms via `rel_syn`/`rel_ant`, a CEFR estimate from word frequency (`md=f`), and a
word family from stem-filtered `rel_trg`/`sp=word*`. The CEFR estimate is persisted to
`word_metadata` and the derived family to `word_family` (relation_type `"related"`), so
repeat lookups and `/relations` are cheap. ponytail heuristics — see lookup.py.

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
synonyms/antonyms from the cached word row (Dictionary API + Datamuse enrichment);
`word_family` from the curated `word_family` table — curated POS rows (noun_form/
verb_form/...) carry their `pos`, enrichment-derived rows carry `pos: "related"`.
`nominalization` only comes from curated rows (null if not seeded — never invented).

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

### GET /stats/accuracy_by_level  → accuracy per CEFR level (Progress chart)
```json
[{"level":"A1","attempts":3,"accuracy":1.0},{"level":"A2","attempts":0,"accuracy":null}, ...]
```
Always all six levels A1…C2 in order. `accuracy` = sum(total_correct)/sum(total_attempts)
over the user's `card_progress` rows joined to each word's `cefr_level`;
`null` (rendered as an empty bar) when no attempts at that level yet.

## Suggestions (Phase 5 — weakness tracking)

### GET /words/weak?limit=10  → words the user keeps missing
```json
[{"word_id":12,"headword":"arbitrary","definition_en":"...","translation":"...",
  "cefr_level":"B2","ease_factor":1.8,"accuracy":0.33}]
```
Attempted words with SM-2 `ease_factor < 2.5`, hardest (lowest ease) first.
`accuracy` = total_correct / total_attempts. Empty array = nothing weak yet.

### GET /words/suggested?limit=10  → words to learn next
```json
[{"word_id":30,"headword":"coherent","definition_en":"...","translation":"...",
  "cefr_level":"B2","is_academic":true}]
```
Cached words the user hasn't started, ordered: at the user's `current_level`
first, then academic words, then most frequent (`word_metadata.frequency_rank`).

## Cohorts + Leaderboard (Phase 7)

One class per student (`users.cohort_id`); join by a short code. All require auth.

### POST /cohorts  body `{"name":"..."}`  → 201, creator auto-joins
### POST /cohorts/join  body `{"code":"AB3KПР"}`  → joins; 404 if no such code
Both return `{"id","name","join_code","member_count","is_teacher"}`.
`is_teacher` is true when the requesting user created the class.
### GET /cohort  → `{"cohort": {...} | null}`  (null = not in a class)
### GET /leaderboard?days=7  → weekly XP ranking scoped to my cohort
```json
{"cohort": {"id":1,"name":"Class A","join_code":"AB3KPR","member_count":2},
 "entries": [{"rank":1,"user_id":1,"display_name":"alice","weekly_xp":18,"is_me":true}]}
```
`cohort` is null + `entries` empty if the user hasn't joined a class. ponytail:
weekly XP is recomputed from `review_log` (grade + word CEFR via `gamify.xp_for`)
over the window — no stored per-period XP, no `game_sessions` table; aggregated
in Python (fine at ~100 users, push to a SQL CASE-sum if it grows).

### GET /cohort/students?days=7  → teacher dashboard (per-student progress)
```json
{"cohort": {...},
 "students": [{"user_id":1,"display_name":"alice","is_teacher":true,
   "total_xp":120,"current_streak":3,"words_learned":12,"weekly_xp":18,
   "last_active":"2026-06-22"}]}
```
Only the class **creator** may call it (403 otherwise). Sorted by `weekly_xp` desc.
Same window/recompute as `/leaderboard`; `total_xp`/`current_streak`/`words_learned`
come from the same counters `/stats` reads.

## Seed (runs once on `make seed` / startup)
- Load CEFR-J wordlist CSV + AWL list into `word_metadata(word, cefr_level, is_academic, frequency_rank)`.
- Load AWL word-family groupings into `word_family`.
- Create `user_id=1` test user (native_language='ru') and a couple of demo decks so the UI isn't empty.
ponytail: if the CEFR-J / AWL source files aren't bundled, ship a small committed sample
CSV (a few hundred rows) so the app runs offline; full dataset is a drop-in replacement.
