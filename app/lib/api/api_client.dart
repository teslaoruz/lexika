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

  Future<WordEntry> lookup(String word) async {
    final j = await _get(_u('/words/lookup', {'word': word}));
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

  Future<void> addCard(int deckId, int wordId) =>
      _post(_u('/decks/$deckId/cards'), {'word_id': wordId});

  Future<List<DeckWord>> deckCards(int deckId) async {
    final j = await _get(_u('/decks/$deckId/cards'));
    return (j as List)
        .map((e) => DeckWord.fromJson(e as Map<String, dynamic>))
        .toList();
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

  // ---- Phase 7: cohorts + leaderboard ----
  Future<Cohort?> myCohort() async {
    final j = await _get(_u('/cohort')) as Map<String, dynamic>;
    return j['cohort'] == null
        ? null
        : Cohort.fromJson(j['cohort'] as Map<String, dynamic>);
  }

  Future<Cohort> createCohort(String name) async =>
      Cohort.fromJson(await _post(_u('/cohorts'), {'name': name})
          as Map<String, dynamic>);

  Future<Cohort> joinCohort(String code) async =>
      Cohort.fromJson(await _post(_u('/cohorts/join'), {'code': code})
          as Map<String, dynamic>);

  /// Teacher dashboard: per-student progress for the teacher's class.
  /// Throws ApiException(403) if the caller isn't the class teacher.
  Future<List<StudentProgress>> cohortStudents() async {
    final j = await _get(_u('/cohort/students')) as Map<String, dynamic>;
    return ((j['students'] as List?) ?? [])
        .map((e) => StudentProgress.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<LeaderboardEntry>> leaderboard() async {
    final j = await _get(_u('/leaderboard')) as Map<String, dynamic>;
    return ((j['entries'] as List?) ?? [])
        .map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
