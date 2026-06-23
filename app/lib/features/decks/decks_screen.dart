import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../api/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/bounce_press.dart';
import 'deck_detail_screen.dart';
import '../share/qr_share.dart';
import '../../widgets/empty_state.dart';
import '../games/games_screen.dart';
import '../review/review_screen.dart';

class DecksScreen extends ConsumerWidget {
  const DecksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(decksProvider);

    return decks.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.violet)),
      error: (_, _) => const Center(
        child: EmptyState(
          emoji: '🙈',
          title: 'Could not load decks',
          subtitle: 'Check your connection and pull back in a moment.',
        ),
      ),
      data: (list) {
        final totalDue = list.fold<int>(0, (a, d) => a + d.dueCount);
        final totalSaved = list.fold<int>(0, (a, d) => a + d.cardCount);
        // Real weak-word count drives the banner; hide it when there's nothing
        // to practise rather than showing a hardcoded number.
        final weakCount = ref.watch(weakWordsProvider).maybeWhen(
              data: (w) => w.length,
              orElse: () => 0,
            );
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: _statBox('$totalDue', 'Cards due today',
                      const [AppColors.coral, Color(0xFFFF8A7A)]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statBox('$totalSaved', 'Words saved',
                      const [AppColors.violet, Color(0xFF8B7EF0)]),
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (weakCount > 0) ...[
              _weakBanner(context, weakCount),
              const SizedBox(height: 22),
            ],
            const GamesSection(),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Your decks',
                    style: AppTheme.baloo(size: 19, weight: FontWeight.w700)),
                Row(
                  children: [
                    BouncePress(
                      onTap: () => openScanner(context),
                      pressedScale: 0.9,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.mintLight,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: const Icon(Icons.qr_code_scanner_rounded,
                            size: 18, color: AppColors.mintDark),
                      ),
                    ),
                    const SizedBox(width: 8),
                    BouncePress(
                      onTap: () => _openNewDeck(context, ref),
                      pressedScale: 0.94,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.violetLight,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text('+ New deck',
                            style: AppTheme.baloo(
                                size: 12.5,
                                weight: FontWeight.w700,
                                color: AppColors.violet)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (list.isEmpty)
              const EmptyState(
                emoji: '🗂️',
                title: 'No decks yet',
                subtitle:
                    'Look up a word and tap “Save to deck” to start your first one.',
              )
            else ...[
              for (final d in list) ...[
                _deckCard(context, ref, d),
                const SizedBox(height: 10),
              ],
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Tip: long-press a deck to delete it.',
                    style: AppTheme.quick(
                        size: 12,
                        weight: FontWeight.w500,
                        color: AppColors.inkFaint)),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _statBox(String num, String label, List<Color> colors) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppColors.shadowSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(num,
                style: AppTheme.baloo(
                    size: 28,
                    weight: FontWeight.w800,
                    height: 1,
                    color: AppColors.onAccent)),
            const SizedBox(height: 5),
            Text(label,
                style: AppTheme.quick(
                    size: 12,
                    weight: FontWeight.w600,
                    color: AppColors.onAccent.withValues(alpha: 0.85))),
          ],
        ),
      );

  Widget _weakBanner(BuildContext context, int count) => BouncePress(
        onTap: () => _openReview(context),
        pressedScale: 0.97,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.pink, Color(0xFFFF6FA0)],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppColors.shadowPink,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.onAccent.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text('💪', style: TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Practice your weak words',
                        style: AppTheme.baloo(
                            size: 15,
                            weight: FontWeight.w700,
                            color: AppColors.onAccent)),
                    const SizedBox(height: 2),
                    Text('$count word${count == 1 ? '' : 's'} need extra attention',
                        style: AppTheme.quick(
                            size: 12,
                            weight: FontWeight.w600,
                            color: AppColors.onAccent.withValues(alpha: 0.85))),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _deckCard(BuildContext context, WidgetRef ref, Deck d) {
    final initials = _initials(d.name);
    final (bg, fg) = _deckColors(d);
    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DeckDetailScreen(deck: d)),
      ),
      // System decks can't be deleted.
      onLongPress: d.isSystemDeck ? null : () => _confirmDelete(context, ref, d),
      radius: 22,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(initials,
                style: AppTheme.baloo(
                    size: 16, weight: FontWeight.w700, color: fg)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.quick(
                        size: 15, weight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text('${d.cardCount} cards',
                    style: AppTheme.quick(
                        size: 12,
                        weight: FontWeight.w500,
                        color: AppColors.inkFaint)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: d.dueCount == 0 ? AppColors.mintLight : AppColors.pinkLight,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(d.dueCount == 0 ? 'All done' : '${d.dueCount} due',
                style: AppTheme.baloo(
                    size: 11.5,
                    weight: FontWeight.w700,
                    color: d.dueCount == 0
                        ? AppColors.mintDark
                        : AppColors.antText)),
          ),
        ],
      ),
    );
  }

  void _openReview(BuildContext context) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, a, _) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: kEaseSmooth)),
          child: const ReviewScreen(),
        ),
      ),
    ));
  }

  void _openNewDeck(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => _NewDeckDialog(ref: ref),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Deck d) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Delete “${d.name}”?',
            style: AppTheme.baloo(size: 18, weight: FontWeight.w700)),
        content: Text(
            'This removes the deck and its ${d.cardCount} saved '
            'word${d.cardCount == 1 ? '' : 's'}. Your review progress is kept.',
            style: AppTheme.quick(size: 14, height: 1.5, color: AppColors.inkSoft)),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: AppTheme.baloo(
                    size: 14,
                    weight: FontWeight.w700,
                    color: AppColors.inkSoft)),
          ),
          AppButton(
            label: 'Delete',
            bg: AppColors.coral,
            shadow: AppColors.shadowCoral,
            expand: false,
            onTap: () async {
              Navigator.of(ctx).pop();
              try {
                await ref.read(apiClientProvider).deleteDeck(d.id);
                ref.invalidate(decksProvider);
              } on ApiException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.message)));
                }
              }
            },
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  (Color, Color) _deckColors(Deck d) {
    // Cycle the palette by deck id, mirroring the prototype's varied icons.
    final palette = [
      (AppColors.amberLight, AppColors.amberDark),
      (AppColors.mintLight, AppColors.mintDark),
      (AppColors.skyLight, const Color(0xFF0288A8)),
      (AppColors.pinkLight, AppColors.antText),
    ];
    return palette[d.id % palette.length];
  }
}

/// Small branded dialog to create a deck. Stateful so the confirm button can
/// be loading-guarded while [ApiClient.createDeck] is in flight.
class _NewDeckDialog extends StatefulWidget {
  const _NewDeckDialog({required this.ref});

  final WidgetRef ref;

  @override
  State<_NewDeckDialog> createState() => _NewDeckDialogState();
}

class _NewDeckDialogState extends State<_NewDeckDialog> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.ref.read(apiClientProvider).createDeck(name);
      widget.ref.invalidate(decksProvider);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('New deck',
          style: AppTheme.baloo(size: 19, weight: FontWeight.w700)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        enabled: !_busy,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        style: AppTheme.quick(size: 15, weight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: 'Deck name',
          hintStyle: AppTheme.quick(
              size: 15, weight: FontWeight.w500, color: AppColors.inkFaint),
          filled: true,
          fillColor: AppColors.violetLight,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        AppButton(
          label: _busy ? 'Creating…' : 'Create deck',
          bg: AppColors.violet,
          shadow: AppColors.shadowSm,
          onTap: _busy ? null : _submit,
        ),
      ],
    );
  }
}
