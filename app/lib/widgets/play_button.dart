import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'tts.dart';

/// Coral play button that wiggles (rotate -6° → 6°) on tap and speaks [word]
/// via device TTS, matching the prototype's `@keyframes wiggle`.
class PlayButton extends StatefulWidget {
  const PlayButton({super.key, this.size = 42, this.word, this.onTap});

  final double size;

  /// Text spoken aloud on tap (the English headword). No speech if null/empty.
  final String? word;
  final VoidCallback? onTap;

  @override
  State<PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<PlayButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  late final Animation<double> _wiggle = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: -0.0167, end: 0.0167), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 0.0167, end: -0.0167), weight: 1),
    // kEaseSmooth (not kEaseBounce): an overshooting curve feeds t>1 into
    // TweenSequence and throws. The wiggle shape is already in the tween.
  ]).animate(CurvedAnimation(parent: _c, curve: kEaseSmooth));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _tap() {
    _c.forward(from: 0);
    if (widget.word != null) ttsSpeak(widget.word!);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.size * 0.38;
    return GestureDetector(
      onTap: _tap,
      child: RotationTransition(
        turns: _wiggle,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: AppColors.coral,
            borderRadius: BorderRadius.circular(r),
            boxShadow: AppColors.shadowCoral,
          ),
          child: Icon(Icons.play_arrow_rounded,
              color: AppColors.white, size: widget.size * 0.55),
        ),
      ),
    );
  }
}
