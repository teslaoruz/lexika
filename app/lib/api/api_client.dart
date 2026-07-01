import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'models.dart';

/// Thin client over the Lexika backend (CONTRACT.md). No repository/DI layer —
/// Riverpod providers call this directly. ponytail: single shared base URL,
/// short timeouts, throws [ApiException] on any failure so the UI can fall
/// back to demo content gracefully.
class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, {this.status});
  @override
  String toString() => 'ApiException($status): $message';
}

class ApiClient {
  // Override per platform with --dart-define=API_BASE=... e.g. the Android
  // emulator reaches the host backend at 10.0.2.2, a physical phone at the
  // host's LAN IP. ponytail: one env knob beats a build flavor matrix.
  static const _envBase = String.fromEnvironment('API_BASE');

  /// The base URL used when no override is passed. If API_BASE wasn't supplied
  /// at build time, pick a sane per-platform default instead of bare
  /// `localhost` — on a phone/emulator `localhost` resolves to the *device*,
  /// not the dev machine, which is exactly why auth failed silently. The
  /// Android emulator reaches the host at 10.0.2.2; a physical phone still
  /// needs `--dart-define=API_BASE=http://<LAN-IP>:8000` (no way to guess it).
  static String get _defaultBase {
    if (_envBase.isNotEmpty) return _envBase;
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }

  ApiClient({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? _defaultBase,
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  static const _timeout = Duration(seconds: 6);

  /// Bearer token set by the auth controller after login/register; attached to
  /// every request. Persisted across launches via shared_preferences (see
  /// AuthController._restore).
  String? token;

  Map<String, String> _headers([bool json = false]) {
    final auth = token == null ? null : 'Bearer $token';
    return {
      if (json) 'Content-Type': 'application/json',
      'Authorization': ?auth, // null-aware: omitted when not signed in
    };
  }

  Uri _u(String path, [Map<String, dynamic>? q]) =>
      Uri.parse('$baseUrl$path').replace(
        queryParameters: q?.map((k, v) => MapEntry(k, '$v')),
      );

  Future<dynamic> _get(Uri url) async {
    try {
      final res = await _client.get(url, headers: _headers()).timeout(_timeout);
      if (res.statusCode == 404) {
        throw ApiException('Not found', status: 404);
      }
      if (res.statusCode >= 400) {
        throw ApiException('Server error', status: res.statusCode);
      }
      return jsonDecode(res.body);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(_reachMessage(e));
    }
  }

  /// Turns a raw transport failure into a plain-language reason. Real HTTP
  /// statuses are already rethrown as ApiException upstream, so anything that
  /// lands here is a connectivity failure: SocketException (mobile),
  /// TimeoutException (slow/dead host), or http ClientException "Failed to
  /// fetch" (web). All mean the same thing to the user.
  String _reachMessage(Object e) {
    // ponytail: dev detail (baseUrl, dart-define hint) lives in the comment/
    // network tab, not the user-facing string.
    assert(() {
      // ignore: avoid_print
      print('Network failure hitting $baseUrl: $e');
      return true;
    }());
    return 'No internet connection, or the server is not responding. '
        'Please check your connection and try again.';
  }

  Future<dynamic> _post(Uri url, Map<String, dynamic> body) async {
    try {
      final res = await _client
          .post(url, headers: _headers(true), body: jsonEncode(body))
          .timeout(_timeout);
      if (res.statusCode >= 400) {
        // Surface the server's detail (e.g. wrong password) when present.
        String msg = 'Server error';
        try {
          msg = (jsonDecode(res.body) as Map)['detail']?.toString() ?? msg;
        } catch (_) {}
        throw ApiException(msg, status: res.statusCode);
      }
      return res.body.isEmpty ? null : jsonDecode(res.body);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(_reachMessage(e));
    }
  }

  Future<void> _delete(Uri url) async {
    try {
      final res =
          await _client.delete(url, headers: _headers()).timeout(_timeout);
      if (res.statusCode >= 400) {
        String msg = 'Request failed';
        try {
          msg = (jsonDecode(res.body) as Map)['detail']?.toString() ?? msg;
        } catch (_) {}
        throw ApiException(msg, status: res.statusCode);
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(_reachMessage(e));
    }
  }

  /// Probe `/health`. Used by the startup gate to detect a sleeping free-tier
  /// backend (a cold start can take ~30–50s). Uses a long timeout so a *waking*
  /// server isn't mistaken for a dead one. Returns true only on a 200.
  Future<bool> ping({Duration timeout = const Duration(seconds: 35)}) async {
    try {
      final res = await _client.get(_u('/health')).timeout(timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Auth (CONTRACT.md /auth). Both return the raw `{token, user}` map; the auth
  /// controller stores the token on this client.
  Future<Map<String, dynamic>> register(String email, String password,
          {String nativeLanguage = 'ru', String? displayName}) async =>
      (await _post(_u('/auth/register'), {
        'email': email,
        'password': password,
        'native_language': nativeLanguage,
        'display_name': ?displayName,
      }) as Map)
          .cast<String, dynamic>();

  /// Validates the current token and returns the user (used to restore a saved
  /// session on launch). Throws [ApiException] (401) if the token is stale.
  Future<Map<String, dynamic>> me() async =>
      (await _get(_u('/auth/me')) as Map).cast<String, dynamic>();

  /// Update editable profile fields. Only non-null args are sent (and changed).
  Future<Map<String, dynamic>> updateProfile(
          {String? displayName,
          String? nativeLanguage,
          String? currentLevel,
          String? avatar}) async =>
      (await _post(_u('/auth/profile'), {
        'display_name': ?displayName,
        'native_language': ?nativeLanguage,
        'current_level': ?currentLevel,
        'avatar': ?avatar,
      }) as Map)
          .cast<String, dynamic>();

  Future<Map<String, dynamic>> login(String email, String password) async =>
      (await _post(_u('/auth/login'), {'email': email, 'password': password})
              as Map)
          .cast<String, dynamic>();

  /// Sign in with a Google ID token (from google_sign_in). Backend verifies it
  /// with Google and upserts the user. Returns the same `{token, user}` shape.
  Future<Map<String, dynamic>> authGoogle(String idToken) async =>
      (await _post(_u('/auth/google'), {'id_token': idToken}) as Map)
          .cast<String, dynamic>();

  /// Permanently delete the signed-in account and all its data.
  Future<void> deleteAccount() => _delete(_u('/auth/me'));

  /// [correct] enables typo-correction (search box). Pass false when the word is
  /// already known to be real (synonym/deck taps) so a dictionary miss returns a
  /// "not found" rather than a wrong near-spelling.
  Future<WordEntry> lookup(String word, {bool correct = true}) async {
    final j = await _get(
        _u('/words/lookup', {'word': word, 'correct': correct}));
    return WordEntry.fromJson(j as Map<String, dynamic>);
  }

  /// Extra example sentences for a word. `[]` when none are available.
  Future<List<String>> examples(String word) async {
    final j = await _get(_u('/words/${Uri.encodeComponent(word)}/examples'));
    return (j as List).map((e) => e.toString()).toList();
  }

  Future<WordRelations> relations(String word) async {
    final j = await _get(_u('/words/${Uri.encodeComponent(word)}/relations'));
    return WordRelations.fromJson(j as Map<String, dynamic>);
  }

  Future<List<Deck>> decks() async {
    final j = await _get(_u('/decks'));
    return (j as List)
        .map((e) => Deck.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Deck> createDeck(String name) async => Deck.fromJson(
      await _post(_u('/decks'), {'name': name}) as Map<String, dynamic>);

  Future<void> deleteDeck(int deckId) => _delete(_u('/decks/$deckId'));

  Future<void> addCard(int deckId, int wordId) =>
      _post(_u('/decks/$deckId/cards'), {'word_id': wordId});

  /// Remove one word from one of the user's own decks.
  Future<void> deleteCard(int deckId, int wordId) =>
      _delete(_u('/decks/$deckId/cards/$wordId'));

  /// Copy a shared deck (by id) into a new deck for the current user.
  Future<Deck> importDeck(int deckId) async => Deck.fromJson(
      await _post(_u('/decks/import'), {'deck_id': deckId})
          as Map<String, dynamic>);

  Future<List<DeckWord>> deckCards(int deckId) async {
    final j = await _get(_u('/decks/$deckId/cards'));
    return (j as List)
        .map((e) => DeckWord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Whether the current user already has this word saved in a deck.
  Future<bool> wordSaved(int wordId) async {
    final j = await _get(_u('/words/$wordId/saved'));
    return ((j as Map)['saved'] ?? false) as bool;
  }

  /// All cards in a deck as review cards (for practising one deck).
  Future<List<ReviewCard>> deckReview(int deckId) async {
    final j = await _get(_u('/decks/$deckId/review'));
    return (j as List)
        .map((e) => ReviewCard.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Autocomplete: headword prefix suggestions for the search box.
  /// `GET /words/suggest?q=<prefix>` → `["aberration", ...]`.
  Future<List<String>> suggest(String query, {int limit = 8}) async {
    if (query.trim().isEmpty) return const [];
    final j = await _get(_u('/words/suggest', {'q': query, 'limit': limit}));
    return (j as List).map((e) => e.toString()).toList();
  }

  Future<List<ReviewCard>> due({int limit = 20}) async {
    final j = await _get(_u('/review/due', {'limit': limit}));
    return (j as List)
        .map((e) => ReviewCard.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// All the user's saved words (for games — practice, not spaced repetition).
  Future<List<ReviewCard>> allCards({int limit = 50}) async {
    final j = await _get(_u('/review/all', {'limit': limit}));
    return (j as List)
        .map((e) => ReviewCard.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Submits an SM-2 grade (from a flashcard or a game). Returns XP earned so
  /// the UI can toast it.
  Future<int> submit(int wordId, String grade, {String gameType = 'flashcard'}) async {
    final j = await _post(_u('/review/submit'),
        {'word_id': wordId, 'grade': grade, 'game_type': gameType});
    return ((j as Map?)?['xp_earned'] ?? 0) as int;
  }

  Future<UserStats> stats() async {
    final j = await _get(_u('/stats'));
    return UserStats.fromJson(j as Map<String, dynamic>);
  }

  /// Set of ISO dates (yyyy-MM-dd) the user was active — for the streak calendar.
  Future<Set<String>> activityDates() async {
    final j = await _get(_u('/stats/activity'));
    return ((j as Map)['active_dates'] as List? ?? [])
        .map((e) => e.toString())
        .toSet();
  }

  Future<List<LevelAccuracy>> accuracyByLevel() async {
    final j = await _get(_u('/stats/accuracy_by_level'));
    return (j as List)
        .map((e) => LevelAccuracy.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<WordTip>> weakWords({int limit = 10}) async {
    final j = await _get(_u('/words/weak', {'limit': limit}));
    return (j as List)
        .map((e) => WordTip.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<WordTip>> suggested({int limit = 10}) async {
    final j = await _get(_u('/words/suggested', {'limit': limit}));
    return (j as List)
        .map((e) => WordTip.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The words the user has learned — the list behind the "words learned" tile.
  Future<List<WordTip>> learnedWords() async {
    final j = await _get(_u('/stats/learned'));
    return (j as List)
        .map((e) => WordTip.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- Classes (multi-class): membership, detail, sharing, leaderboards ----

  /// Every class the student is a member of (they can belong to several).
  Future<List<Cohort>> myCohorts() async {
    final j = await _get(_u('/cohorts/mine')) as Map<String, dynamic>;
    return ((j['classes'] as List?) ?? [])
        .map((e) => Cohort.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Full info about one class (members + shared decks) — the tap-through view.
  Future<CohortDetail> cohortDetail(int cohortId) async =>
      CohortDetail.fromJson(
          await _get(_u('/cohorts/$cohortId')) as Map<String, dynamic>);

  Future<Cohort> createCohort(String name) async =>
      Cohort.fromJson(await _post(_u('/cohorts'), {'name': name})
          as Map<String, dynamic>);

  Future<Cohort> joinCohort(String code) async =>
      Cohort.fromJson(await _post(_u('/cohorts/join'), {'code': code})
          as Map<String, dynamic>);

  /// Leave a class (students only; the teacher deletes instead).
  Future<void> leaveCohort(int cohortId) =>
      _post(_u('/cohorts/$cohortId/leave'), const {});

  /// Delete a class the user teaches.
  Future<void> deleteCohort(int cohortId) => _delete(_u('/cohorts/$cohortId'));

  /// Teacher dashboard: per-student progress for one class the teacher owns.
  Future<List<StudentProgress>> cohortStudents(int cohortId) async {
    final j =
        await _get(_u('/cohorts/$cohortId/students')) as Map<String, dynamic>;
    return ((j['students'] as List?) ?? [])
        .map((e) => StudentProgress.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// All classes the current user created (teaches). A teacher can own several.
  Future<List<Cohort>> teachingClasses() async {
    final j = await _get(_u('/cohort/teaching')) as Map<String, dynamic>;
    return ((j['classes'] as List?) ?? [])
        .map((e) => Cohort.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Teacher: share a deck *to a class* (live, not copied). Returns how many
  /// current members were seeded and how many words.
  Future<({int sharedTo, int words})> shareDeckToClass(
      int cohortId, int deckId) async {
    final j = await _post(_u('/cohorts/$cohortId/decks'), {'deck_id': deckId})
        as Map;
    return (
      sharedTo: (j['shared_to'] ?? 0) as int,
      words: (j['words'] ?? 0) as int
    );
  }

  /// Teacher: stop sharing a deck with a class.
  Future<void> unshareDeck(int cohortId, int deckId) =>
      _delete(_u('/cohorts/$cohortId/decks/$deckId'));

  /// Weekly XP leaderboard scoped to one class.
  Future<List<LeaderboardEntry>> leaderboard(int cohortId) async {
    final j = await _get(_u('/cohorts/$cohortId/leaderboard'))
        as Map<String, dynamic>;
    return ((j['entries'] as List?) ?? [])
        .map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- Admin ----
  /// All users with a snapshot of activity. Throws ApiException(403) if the
  /// caller isn't an admin.
  Future<List<AdminUser>> adminUsers() async {
    final j = await _get(_u('/admin/users')) as Map<String, dynamic>;
    return ((j['users'] as List?) ?? [])
        .map((e) => AdminUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
