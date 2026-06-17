import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/play_button.dart';

/// Real 3D Y-axis flip card. Front = English headword, back = translation.
/// Tap to flip; uses Matrix4 rotateY with perspective entry (not a crossfade).
class FlipCard extends StatefulWidget {
  const FlipCard({super.key, required this.card});

  final ReviewCard card;

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  late final Animation<double> _anim =
      CurvedAnimation(parent: _c, curve: kEaseBounce);

  @override
  void didUpdateWidget(covariant FlipCard old) {
    super.didUpdateWidget(old);
    // New card -> reset to the English front.
    if (old.card.headword != widget.card.headword) {
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _flip() {
    if (_c.value < 0.5) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _flip,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          final t = _anim.value; // 0 front .. 1 back
          final angle = t * math.pi;
          final showBack = angle > math.pi / 2;
          final matrix = Matrix4.identity()
            ..setEntry(3, 2, 0.0014) // perspective
            ..rotateY(angle);
          return Transform(
            alignment: Alignment.center,
            transform: matrix,
            child: showBack
                // Counter-rotate the back so its content isn't mirrored.
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: _face(back: true),
                  )
                : _face(back: false),
          );
        },
      ),
    );
  }

  Widget _face({required bool back}) {
    final c = widget.card;
    final label = back ? 'Russian' : 'English';
    final word = back ? (c.translation ?? '—') : c.headword;
    final hint = back ? 'Tap card to flip back' : 'Tap card to reveal translation';
    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(
              color: Color(0x4D000000), blurRadius: 60, offset: Offset(0, 24)),
        ],
      ),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Stack(
          children: [
            Positioned(
              top: 22,
              left: 22,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.violetLight,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(label,
                    style: AppTheme.baloo(
                        size: 11,
                        weight: FontWeight.w700,
                        color: AppColors.violet)),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(word,
                        textAlign: TextAlign.center,
                        style: AppTheme.baloo(
                            size: 36, weight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 20),
                  // Always speaks the English headword, even on the back face.
                  PlayButton(word: widget.card.headword),
                ],
              ),
            ),
            Positioned(
              bottom: 22,
              left: 0,
              right: 0,
              child: Text(hint,
                  textAlign: TextAlign.center,
                  style: AppTheme.quick(
                      size: 12,
                      weight: FontWeight.w600,
                      color: AppColors.inkFaint)),
            ),
          ],
        ),
      ),
    );
  }
}
