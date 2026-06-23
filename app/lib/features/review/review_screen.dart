import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/bounce_press.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/sfx.dart';
import 'flip_card.dart';

/// Fullscreen review modal over the violet gradient (prototype `.review-screen`).
/// With [deckId] set it practises every card in that one deck; otherwise it
/// reviews all cards due across decks.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, this.deckId});

  final int? deckId;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  int _index = 0;
  // Card-swipe animation: horizontal offset as a fraction of card width.
  double _slideX = 0;
  Duration _slideDur = Duration.zero;

  @override
  Widget build(BuildContext context) {
    final source = widget.deckId == null
        ? dueCardsProvider
        : deckReviewProvider(widget.deckId!);
    final due = ref.watch(source);
    final emptyMsg = widget.deckId == null
        ? 'Nothing due — nice work! 🎉'
        : 'This deck has no words yet 🙂';

    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.violetDark, Color(0xFF3D32A8)],
          ),
        ),
        child: SafeArea(
          child: due.when(
            loading: () => Center(
                child: CircularProgressIndicator(color: AppColors.onAccent)),
            error: (_, _) => _message('Could not load cards'),
            data: (cards) {
              if (cards.isEmpty) return _message(emptyMsg);
              final total = cards.length;
              final current = _index.clamp(0, total - 1);
              if (_index >= total) return _message('Review complete! 🎉');
              return _body(cards[current], current, total);
            },
          ),
        ),
      ),
    );
  }

  Widget _message(String text) => Column(
        children: [
          _topBar(0, 0),
          Expanded(
            child: Center(
              child: Text(text,
                  style: AppTheme.baloo(
                      size: 20,
                      weight: FontWeight.w700,
                      color: AppColors.onAccent)),
            ),
          ),
        ],
      );

  Widget _body(ReviewCard card, int current, int total) {
    return Column(
      children: [
        _topBar(current + 1, total),
        Expanded(
          // Mobile gesture: drag the card right = Good, left = Again. The card
          // follows the finger and tilts, then flies off on release. Buttons
          // still cover Hard/Easy. ponytail: two directions, not a 4-way pad.
          child: GestureDetector(
            onHorizontalDragUpdate: (d) {
              final w = MediaQuery.of(context).size.width;
              setState(() {
                _slideDur = Duration.zero; // follow the finger 1:1
                _slideX += d.delta.dx / w;
              });
            },
            onHorizontalDragEnd: (d) => _onDragEnd(card, d.primaryVelocity ?? 0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Center(
                child: AnimatedSlide(
                  offset: Offset(_slideX, 0),
                  duration: _slideDur,
                  curve: kEaseSmooth,
                  child: Transform.rotate(
                    angle: _slideX * 0.18, // subtle tilt in the drag direction
                    child:
                        FlipCard(key: ValueKey(card.headword), card: card),
                  ),
                ),
              ),
            ),
          ),
        ),
        Text('← swipe Again   ·   swipe Good →',
            style: AppTheme.quick(
                size: 11.5,
                weight: FontWeight.w600,
                color: AppColors.onAccent.withValues(alpha: 0.6))),
        const SizedBox(height: 6),
        _grades(card),
      ],
    );
  }

  Widget _topBar(int cur, int total) {
    final pct = total == 0 ? 0.0 : cur / total;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Row(
        children: [
          BouncePress(
            onTap: () => Navigator.of(context).pop(),
            pressedScale: 0.88,
            child: GlassSurface(
              radius: 12,
              tint: AppColors.onAccent,
              opacity: 0.18,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(Icons.close_rounded,
                    size: 18, color: AppColors.onAccent),
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 10,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.onAccent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: LayoutBuilder(
                  builder: (context, c) => AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: kEaseSmooth,
                    width: c.maxWidth * pct,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.amber, Color(0xFFFFE08A)],
                      ),
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Text('$cur / $total',
              style: AppTheme.baloo(
                  size: 13,
                  weight: FontWeight.w700,
                  color: AppColors.onAccent.withValues(alpha: 0.85))),
        ],
      ),
    );
  }

  Widget _grades(ReviewCard card) {
    Widget btn(String label, String time, String grade, Color bg, Color fg) {
      return Expanded(
        child: BouncePress(
          onTap: () => _grade(card, grade),
          pressedScale: 0.9,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Text(label,
                    style: AppTheme.baloo(
                        size: 12.5, weight: FontWeight.w700, color: fg)),
                const SizedBox(height: 4),
                Text(time,
                    style: AppTheme.baloo(
                        size: 10,
                        weight: FontWeight.w600,
                        color: fg.withValues(alpha: 0.75))),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      child: Row(
        children: [
          btn('Again', '<1m', 'again', AppColors.coral, AppColors.onAccent),
          const SizedBox(width: 8),
          btn('Hard', '6m', 'hard', AppColors.amber, const Color(0xFF6B4F00)),
          const SizedBox(width: 8),
          btn('Good', '1d', 'good', AppColors.mint, AppColors.onAccent),
          const SizedBox(width: 8),
          btn('Easy', '4d', 'easy', AppColors.sky, const Color(0xFF00425C)),
        ],
      ),
    );
  }

  /// Release handler for the swipe gesture: fly the card off and grade it, or
  /// snap it back if the drag was too small.
  void _onDragEnd(ReviewCard card, double velocity) {
    final go = _slideX.abs() > 0.22 || velocity.abs() > 600;
    if (!go) {
      setState(() {
        _slideDur = const Duration(milliseconds: 220);
        _slideX = 0; // snap back to center
      });
      return;
    }
    final dir = _slideX != 0 ? _slideX.sign : (velocity < 0 ? -1.0 : 1.0);
    setState(() {
      _slideDur = const Duration(milliseconds: 220);
      _slideX = dir * 1.5; // fling off-screen
    });
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() {
        _slideX = 0; // recenter — the next card mounts via the index change
        _slideDur = Duration.zero;
      });
      _grade(card, dir > 0 ? 'good' : 'again');
    });
  }

  Future<void> _grade(ReviewCard card, String grade) async {
    grade == 'again' ? Sfx.wrong() : Sfx.correct();
    setState(() => _index++); // advance immediately for a snappy feel
    // Submit + award XP in the background; ignore failures so review continues.
    if (card.wordId == 0) return;
    try {
      final xp = await ref.read(apiClientProvider).submit(card.wordId, grade);
      ref.invalidate(statsProvider); // refresh streak/XP in the top bar
      if (mounted && xp > 0) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text('+$xp XP',
                style: AppTheme.baloo(
                    size: 15,
                    weight: FontWeight.w700,
                    color: AppColors.onAccent)),
            duration: const Duration(milliseconds: 900),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.violet,
          ));
      }
    } catch (_) {/* ponytail: offline — review already advanced */}
  }
}
