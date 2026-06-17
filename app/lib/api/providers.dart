import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider lives in the legacy export under Riverpod 3.
import 'package:flutter_riverpod/legacy.dart';

import 'api_client.dart';
import 'demo_data.dart';
import 'models.dart';

/// Minimal Riverpod surface: one client, a few async providers that fall back
/// to demo data when the backend is down. ponytail: no repositories/usecases.

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

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

final dueCardsProvider = FutureProvider.autoDispose<List<ReviewCard>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final cards = await api.due();
    return cards.isEmpty ? Demo.due : cards;
  } on ApiException {
    return Demo.due;
  }
});
