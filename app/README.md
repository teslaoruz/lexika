# Lexika — Flutter client

English-vocabulary learning app for Russian/Kazakh students. This is the Flutter
client built against the approved `lexika-prototype.html` design and the
`CONTRACT.md` backend API.

## Run

```bash
cd app
flutter pub get
flutter run -d chrome        # or: flutter run -d <device>
```

Build a release web bundle:

```bash
flutter build web            # output in build/web
```

Requires Flutter 3.44+ (Dart 3.12+).

## Backend

The app talks to `http://localhost:8000` (see `CONTRACT.md`). It works **without**
a running backend: every networked screen falls back to the prototype's demo
content if the server is unreachable, and shows a graceful "couldn't find / server
offline" card for real lookup failures.

To point at a different host, change the `baseUrl` default in
`lib/api/api_client.dart`.

## Structure (feature-first)

```
lib/
  theme/        AppColors (exact prototype palette) + AppTheme (Baloo 2 / Quicksand)
  widgets/      shared motion widgets: BouncePress, AppButton, AppCard, AppChip,
                FadeUp, PlayButton, ModeTabs (sliding pill), BottomNav, TopBar
  api/          ApiClient (http), models, demo_data fallback, Riverpod providers
  features/
    lookup/     search + dictionary entry card + relations panel
    decks/      stats, weak-words banner, deck list
    review/     fullscreen modal, 3D flip card, SM-2 grade buttons
    progress/   wireframe empty state
  app_shell.dart  top bar + mode tabs + bottom nav (kept in sync)
  main.dart
```

## Motion (reusable, built once)

- **BouncePress** — scale-to-~0.93 on tap-down, springs back with a bounce curve.
  Used by every button/chip/card.
- **Screen transitions** — fade + ~10px upward slide (`FadeUp`).
- **Mode tabs** — sliding ink pill animates between positions.
- **Card flip** — real 3D Y-axis flip via `Matrix4..rotateY` with perspective.
- **Save button** — scale-pop overshoot to 1.08, recolors to mint, label "Saved!".
- **Play button** — wiggle/rotate on tap.

## Wiring

| Screen | Endpoint |
|---|---|
| Look up | `GET /words/lookup?word=`, `GET /words/{word}/relations` |
| My decks | `GET /decks` |
| Review | `GET /review/due`, `POST /review/submit` |

## Known stubs / deferred (`ponytail:` in code)

- **Translations** (`translation_ru` / `translation_kk`) are `null` in the contract
  slice. The translation block shows "translation coming soon" when null; the demo
  word `ubiquitous` ships RU/KK strings so the toggle demos correctly.
- **Audio / TTS** — the play button only animates; `flutter_tts` is a later phase.
- **Auth** — single seeded user per the contract; no sign-in screen yet.
- **Progress charts** — wireframe empty state only (later phase).
