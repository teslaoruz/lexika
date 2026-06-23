# Lexika — Flutter client

The Flutter client for Lexika. See the [root README](../README.md) for the full
project overview, features, and architecture, and [`CONTRACT.md`](../CONTRACT.md)
for the backend API.

## Run

```bash
cd app
flutter pub get
flutter run -d chrome          # or: flutter run -d <device>
```

The client defaults to `http://localhost:8000`. Point it elsewhere at build time:

```bash
flutter run -d chrome --dart-define=API_BASE=https://api.example.com
```

## Build a release web bundle

```bash
flutter build web --dart-define=API_BASE=https://api.example.com   # output: build/web
```

## Structure

```
lib/
  api/        ApiClient (http), models, Riverpod providers
  theme/      AppColors (light/dark aware) + AppTheme (Baloo 2 / Quicksand)
  widgets/    shared UI + motion (BouncePress, AppButton, AppCard, FlipCard, …)
  features/   one folder per screen: auth, lookup, decks, review, games, progress, profile
  main.dart   app shell: top bar + bottom nav
```

State is managed with Riverpod (`lib/api/providers.dart`). Every networked screen
has explicit loading / empty / error states.
