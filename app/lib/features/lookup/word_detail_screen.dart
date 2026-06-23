import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'entry_card.dart';

/// Full entry for a single word — definition, translation, examples, and
/// relations — opened by tapping a word in a deck. Tapping a related word opens
/// its own detail page.
class WordDetailScreen extends ConsumerWidget {
  const WordDetailScreen({super.key, required this.word});

  final String word;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(wordEntryProvider(word));
    final relations = ref.watch(wordRelationsProvider(word));
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        foregroundColor: AppColors.ink,
        title: Text(word,
            style: AppTheme.baloo(size: 18, weight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: entry.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.violet)),
          error: (_, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text("Couldn't load this word.",
                  textAlign: TextAlign.center,
                  style: AppTheme.quick(size: 14, color: AppColors.inkFaint)),
            ),
          ),
          data: (e) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              EntryCard(
                entry: e,
                relations: relations.value ?? const WordRelations(),
                relationsLoading: relations.isLoading,
                onLookup: (w) => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => WordDetailScreen(word: w)),
                ),
                onSave: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}
