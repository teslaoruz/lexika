import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../api/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../lookup/word_detail_screen.dart';
import '../review/review_screen.dart';
import '../share/qr_share.dart';

/// Lists the words saved in a single deck and lets you practise just that deck.
/// Reachable by tapping a deck on the Decks screen — this is where a
/// freshly-saved word shows up.
class DeckDetailScreen extends ConsumerWidget {
  const DeckDetailScreen({super.key, required this.deck});

  final Deck deck;

  void _practice(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReviewScreen(deckId: deck.id),
    ));
  }

  // Only the user's own decks are editable; shared/system decks are read-only.
  bool get _editable => !deck.isShared && !deck.isSystemDeck;

  Future<void> _deleteWord(
      BuildContext context, WidgetRef ref, DeckWord w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        title: Text('Remove word?',
            style: AppTheme.baloo(size: 18, weight: FontWeight.w800)),
        content: Text('Remove “${w.headword}” from this deck?',
            style: AppTheme.quick(size: 14, color: AppColors.inkSoft)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).deleteCard(deck.id, w.wordId);
      ref.invalidate(deckCardsProvider(deck.id));
      ref.invalidate(decksProvider);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(deckCardsProvider(deck.id));
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        foregroundColor: AppColors.ink,
        title: Text(deck.name,
            style: AppTheme.baloo(size: 18, weight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Share deck',
            icon: const Icon(Icons.qr_code_rounded),
            onPressed: () => showQrDialog(
              context,
              data: deckQrData(deck.id),
              title: 'Share “${deck.name}”',
              subtitle: 'Have a classmate scan this in Lexika to get a copy.',
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: cards.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.violet)),
          error: (_, _) => _centered('Could not load this deck'),
          data: (words) => words.isEmpty
              ? _empty()
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: AppButton(
                        label: 'Practice this deck',
                        icon: Icons.school_rounded,
                        bg: AppColors.violet,
                        shadow: AppColors.shadowViolet,
                        onTap: () => _practice(context),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                      child: Row(
                        children: [
                          Text('${words.length} word${words.length == 1 ? '' : 's'}',
                              style: AppTheme.baloo(
                                  size: 14,
                                  weight: FontWeight.w700,
                                  color: AppColors.inkSoft)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: words.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (ctx, i) => _wordTile(ctx, ref, words[i]),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _wordTile(BuildContext context, WidgetRef ref, DeckWord w) => AppCard(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => WordDetailScreen(word: w.headword)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(w.headword,
                      style:
                          AppTheme.baloo(size: 16, weight: FontWeight.w800)),
                  if (w.definitionEn != null) ...[
                    const SizedBox(height: 4),
                    Text(w.definitionEn!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.quick(
                            size: 13, color: AppColors.inkSoft)),
                  ],
                ],
              ),
            ),
            if (w.cefrLevel != null) ...[
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.violetLight,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(w.cefrLevel!,
                    style: AppTheme.baloo(
                        size: 12,
                        weight: FontWeight.w700,
                        color: AppColors.violet)),
              ),
            ],
            if (_editable) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Remove word',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline_rounded,
                    color: AppColors.inkFaint),
                onPressed: () => _deleteWord(context, ref, w),
              ),
            ],
          ],
        ),
      );

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('📭', style: TextStyle(fontSize: 44)),
              const SizedBox(height: 12),
              Text('No words yet',
                  style: AppTheme.baloo(size: 18, weight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Look up a word and tap “Save to deck” to add it here.',
                  textAlign: TextAlign.center,
                  style: AppTheme.quick(size: 14, color: AppColors.inkFaint)),
            ],
          ),
        ),
      );

  Widget _centered(String text) => Center(
        child: Text(text,
            style: AppTheme.quick(size: 14, color: AppColors.inkFaint)),
      );
}
