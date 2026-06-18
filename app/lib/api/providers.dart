import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider lives in the legacy export under Riverpod 3.
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'demo_data.dart';
import 'models.dart';

/// Minimal Riverpod surface: one client, a few async providers that fall back
/// to demo data when the backend is down. ponytail: no repositories/usecases.

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// Auth session. `user == null` means signed out → the app shows the sign-in
/// screen. The token lives on [ApiClient]; this just drives the gate + UI.
/// ponytail: session is in-memory (re-login on restart); persist with
/// shared_preferences when staying-logged-in matters.
class AuthState {
  final bool loading;
  final Map<String, dynamic>? user;
  const AuthState({this.loading = false, this.user});
  bool get signedIn => user != null;
}

const _tokenKey = 'lexika_token';

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    _restore(); // starts loading=true, resolves to signed in/out
    return const AuthState(loading: true);
  }

  /// Restore a saved session on launch: load the token, validate it via
  /// /auth/me. Stale/absent token → signed out. ponytail: validate rather than
  /// trust the cached token so a rotated/expired one doesn't strand the UI.
  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null) {
      state = const AuthState();
      return;
    }
    final api = ref.read(apiClientProvider);
    api.token = token;
    try {
      final user = await api.me();
      state = AuthState(user: user);
    } on ApiException {
      api.token = null;
      await prefs.remove(_tokenKey);
      state = const AuthState();
    }
  }

  Future<void> login(String email, String password) =>
      _run(() => ref.read(apiClientProvider).login(email, password));

  Future<void> register(String email, String password, String nativeLanguage,
          {String? displayName}) =>
      _run(() => ref.read(apiClientProvider).register(email, password,
          nativeLanguage: nativeLanguage, displayName: displayName));

  Future<void> _run(Future<Map<String, dynamic>> Function() call) async {
    state = const AuthState(loading: true);
    try {
      final r = await call();
      final token = r['token'] as String;
      ref.read(apiClientProvider).token = token;
      (await SharedPreferences.getInstance()).setString(_tokenKey, token);
      _invalidateUserData(); // drop any stale (demo / previous-user) data
      state = AuthState(user: (r['user'] as Map).cast<String, dynamic>());
    } catch (_) {
      state = const AuthState();
      rethrow;
    }
  }

  Future<void> logout() async {
    ref.read(apiClientProvider).token = null;
    (await SharedPreferences.getInstance()).remove(_tokenKey);
    _invalidateUserData();
    state = const AuthState();
  }

  // Non-autoDispose, user-specific providers — reset them on session change.
  void _invalidateUserData() {
    ref.invalidate(statsProvider);
    ref.invalidate(cohortProvider);
    ref.invalidate(leaderboardProvider);
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Recent search chips (client-side only for now).
final recentSearchesProvider =
    StateProvider<List<String>>((ref) => List.of(Demo.recent));

/// The word currently shown on the Look up screen.
final currentWordProvider = StateProvider<String>((ref) => 'ubiquitous');

/// Lookup result for [currentWordProvider]. Falls back to demo content if the
/// server can't be reached (so the prototype still renders).
final lookupProvider = FutureProvider.autoDispose<WordEntry>((ref) async {
  final word = ref.watch(currentWordProvider);
  final api = ref.watch(apiClientProvider);
  try {
    return await api.lookup(word);
  } on ApiException {
    if (word == 'ubiquitous') return Demo.ubiquitous;
    rethrow; // real 404 / other word with no server -> show error state
  }
});

final relationsProvider =
    FutureProvider.autoDispose<WordRelations>((ref) async {
  final word = ref.watch(currentWordProvider);
  final api = ref.watch(apiClientProvider);
  try {
    return await api.relations(word);
  } on ApiException {
    if (word == 'ubiquitous') return Demo.ubiquitousRelations;
    return const WordRelations();
  }
});

final decksProvider = FutureProvider.autoDispose<List<Deck>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    return await api.decks();
  } on ApiException {
    return Demo.decks;
  }
});

/// Gamification totals (streak/XP/words). Not autoDispose — the top bar always
/// wants it. Demo fallback keeps the prototype's 12-day streak when offline.
final statsProvider = FutureProvider<UserStats>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    return await api.stats();
  } on ApiException {
    return const UserStats(
        currentStreak: 12, longestStreak: 21, totalXp: 1840, totalWordsLearned: 87);
  }
});

final dueCardsProvider = FutureProvider.autoDispose<List<ReviewCard>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final cards = await api.due();
    return cards.isEmpty ? Demo.due : cards;
  } on ApiException {
    return Demo.due;
  }
});

/// Phase 5: words the learner struggles with (low SM-2 ease) and words to try
/// next. Empty list is a valid, expected state (nothing weak yet / all started).
final weakWordsProvider = FutureProvider.autoDispose<List<WordTip>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    return await api.weakWords();
  } on ApiException {
    return Demo.weakWords;
  }
});

final suggestedWordsProvider =
    FutureProvider.autoDispose<List<WordTip>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    return await api.suggested();
  } on ApiException {
    return Demo.suggestedWords;
  }
});

/// Phase 7: the user's class (null = not joined) and its weekly leaderboard.
/// No demo fallback — these are real, user-specific, and fine to be empty.
final cohortProvider = FutureProvider<Cohort?>((ref) async {
  return ref.watch(apiClientProvider).myCohort();
});

final leaderboardProvider =
    FutureProvider<List<LeaderboardEntry>>((ref) async {
  return ref.watch(apiClientProvider).leaderboard();
});
