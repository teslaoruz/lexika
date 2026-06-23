import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider lives in the legacy export under Riverpod 3.
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'models.dart';

/// Minimal Riverpod surface: one client, a few async providers that fall back
/// to demo data when the backend is down. ponytail: no repositories/usecases.

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// Auth session. `user == null` means signed out → the app shows the sign-in
/// screen. The token lives on [ApiClient]; this just drives the gate + UI.
/// The token is persisted via shared_preferences and restored on launch.
class AuthState {
  /// A login/register request is in flight (drives the button spinner).
  final bool loading;

  /// Restoring a saved session on launch — the only state that should show the
  /// full-screen splash. Interactive login must NOT replace AuthScreen, or its
  /// local error state is torn down and failures show nothing.
  final bool initializing;
  final Map<String, dynamic>? user;
  const AuthState({this.loading = false, this.initializing = false, this.user});
  bool get signedIn => user != null;
}

const _tokenKey = 'lexika_token';

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    _restore(); // starts initializing=true, resolves to signed in/out
    return const AuthState(initializing: true);
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

  /// Edit profile fields and reflect the result in [state] so the UI (and the
  /// native-language default for translations) updates immediately.
  Future<void> updateProfile(
      {String? displayName, String? nativeLanguage, String? avatar}) async {
    final updated = await ref.read(apiClientProvider).updateProfile(
        displayName: displayName,
        nativeLanguage: nativeLanguage,
        avatar: avatar);
    state = AuthState(user: updated.cast<String, dynamic>());
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
    ref.invalidate(accuracyByLevelProvider);
    ref.invalidate(cohortProvider);
    ref.invalidate(leaderboardProvider);
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

const _darkKey = 'lexika_dark';

/// Dark-mode toggle, persisted across launches. The root reads this to set
/// [AppColors.dark] and the MaterialApp brightness before building.
class ThemeModeController extends Notifier<bool> {
  @override
  bool build() {
    _restore();
    return false;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_darkKey) ?? false;
  }

  Future<void> toggle() async {
    state = !state;
    (await SharedPreferences.getInstance()).setBool(_darkKey, state);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, bool>(ThemeModeController.new);

/// The current search-box query. [correct] enables typo-correction for typed
/// searches; taps on already-real words (synonyms) set it false.
typedef LookupQuery = ({String word, bool correct});

/// The word currently shown on the Look up screen ('' = nothing searched yet).
final currentWordProvider =
    StateProvider<LookupQuery>((ref) => (word: '', correct: true));

/// Lookup result for [currentWordProvider]. No demo fallback — real data or a
/// real error/empty state. Empty word short-circuits (the screen shows a prompt).
final lookupProvider = FutureProvider.autoDispose<WordEntry>((ref) async {
  final q = ref.watch(currentWordProvider);
  final word = q.word.trim();
  if (word.isEmpty) throw ApiException('');
  return ref.watch(apiClientProvider).lookup(word, correct: q.correct);
});

final relationsProvider =
    FutureProvider.autoDispose<WordRelations>((ref) async {
  final word = ref.watch(currentWordProvider).word.trim();
  if (word.isEmpty) return const WordRelations();
  final api = ref.watch(apiClientProvider);
  try {
    return await api.relations(word);
  } on ApiException {
    return const WordRelations(); // secondary content — empty, never blocks
  }
});

/// Look up a specific word by string (for the deck-word detail view), separate
/// from the search-box-driven [lookupProvider].
final wordEntryProvider =
    FutureProvider.autoDispose.family<WordEntry, String>((ref, word) async {
  // Deck words are already real — don't typo-correct them.
  return ref.watch(apiClientProvider).lookup(word, correct: false);
});

/// Relations for a specific word by string. Secondary content — empty on error.
final wordRelationsProvider =
    FutureProvider.autoDispose.family<WordRelations, String>((ref, word) async {
  try {
    return await ref.watch(apiClientProvider).relations(word);
  } on ApiException {
    return const WordRelations();
  }
});

/// Whether a word is already saved in one of the user's decks (drives the
/// 'Saved to deck' state). Invalidated after a save.
final wordSavedProvider =
    FutureProvider.autoDispose.family<bool, int>((ref, wordId) async {
  try {
    return await ref.watch(apiClientProvider).wordSaved(wordId);
  } on ApiException {
    return false;
  }
});

final decksProvider = FutureProvider.autoDispose<List<Deck>>((ref) async {
  return ref.watch(apiClientProvider).decks();
});

/// Words in a single deck (deck-detail view).
final deckCardsProvider =
    FutureProvider.autoDispose.family<List<DeckWord>, int>((ref, deckId) async {
  return ref.watch(apiClientProvider).deckCards(deckId);
});

/// Gamification totals (streak/XP/words). Not autoDispose — the top bar always
/// wants it. Zeroed on error (neutral, not fake) so the bar never breaks.
final statsProvider = FutureProvider<UserStats>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    return await api.stats();
  } on ApiException {
    return const UserStats(
        currentStreak: 0, longestStreak: 0, totalXp: 0, totalWordsLearned: 0);
  }
});

/// Accuracy by CEFR level for the Progress chart. Empty/all-null is a valid
/// state (nothing reviewed yet).
final accuracyByLevelProvider =
    FutureProvider<List<LevelAccuracy>>((ref) async {
  return ref.watch(apiClientProvider).accuracyByLevel();
});

final dueCardsProvider =
    FutureProvider.autoDispose<List<ReviewCard>>((ref) async {
  return ref.watch(apiClientProvider).due();
});

/// All the user's saved words — the pool the games practise from (not limited
/// to SM-2 due cards, so a word stays playable after you get it right).
final allCardsProvider =
    FutureProvider.autoDispose<List<ReviewCard>>((ref) async {
  return ref.watch(apiClientProvider).allCards();
});

/// Weak words shaped as review cards, so games can practise just the hard ones.
final weakReviewProvider =
    FutureProvider.autoDispose<List<ReviewCard>>((ref) async {
  final weak = await ref.watch(weakWordsProvider.future);
  return [
    for (final w in weak)
      ReviewCard(
        wordId: w.wordId,
        headword: w.headword,
        definitionEn: w.definitionEn,
        translation: w.translation,
      ),
  ];
});

/// All cards in one deck, as review cards — for practising a single deck.
final deckReviewProvider =
    FutureProvider.autoDispose.family<List<ReviewCard>, int>((ref, deckId) async {
  return ref.watch(apiClientProvider).deckReview(deckId);
});

/// Phase 5: weak words / words to try next. Empty list is a valid state.
final weakWordsProvider = FutureProvider.autoDispose<List<WordTip>>((ref) async {
  return ref.watch(apiClientProvider).weakWords();
});

final suggestedWordsProvider =
    FutureProvider.autoDispose<List<WordTip>>((ref) async {
  return ref.watch(apiClientProvider).suggested();
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

/// Teacher dashboard: only fetched by the class teacher (the UI gates this on
/// cohort.isTeacher). autoDispose — only the teacher's expanded panel watches it.
final cohortStudentsProvider =
    FutureProvider.autoDispose<List<StudentProgress>>((ref) async {
  return ref.watch(apiClientProvider).cohortStudents();
});

/// All classes the current user teaches (created). Drives the multi-class
/// teacher section.
final teachingClassesProvider = FutureProvider<List<Cohort>>((ref) async {
  return ref.watch(apiClientProvider).teachingClasses();
});
