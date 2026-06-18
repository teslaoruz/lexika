import 'dart:convert';

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
  static const _defaultBase =
      String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8000');

  ApiClient({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? _defaultBase,
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  static const _timeout = Duration(seconds: 6);

  /// Bearer token set by the auth controller after login/register; attached to
  /// every request. ponytail: in-memory only (re-login on app restart) — add
  /// shared_preferences to persist the session across launches.
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
      throw ApiException("Couldn't reach server: $e");
    }
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
      throw ApiException("Couldn't reach server: $e");
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

  Future<Map<String, dynamic>> login(String email, String password) async =>
      (await _post(_u('/auth/login'), {'email': email, 'password': password})
              as Map)
          .cast<String, dynamic>();

  Future<WordEntry> lookup(String word) async {
    final j = await _get(_u('/words/lookup', {'word': word}));
    return WordEntry.fromJson(j as Map<String, dynamic>);
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

  Future<void> addCard(int deckId, int wordId) =>
      _post(_u('/decks/$deckId/cards'), {'word_id': wordId});

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

  Future<List<LeaderboardEntry>> leaderboard() async {
    final j = await _get(_u('/leaderboard')) as Map<String, dynamic>;
    return ((j['entries'] as List?) ?? [])
        .map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
