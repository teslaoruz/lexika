import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Wraps any child with springy press feedback: scales down on tap-down,
/// springs back with an elastic/bounce ease on release. This is the single
/// motion primitive every interactive element reuses (prototype's
/// `:active { transform: scale(...) }` with `--ease-bounce`).
class BouncePress extends StatefulWidget {
  const BouncePress({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.93,
    this.rotateOnPress = 0.0,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  /// Optional rotation (radians) applied while pressed — used by the play
  /// button (`scale(0.88) rotate(-4deg)` in the prototype).
  final double rotateOnPress;

  @override
  State<BouncePress> createState() => _BouncePressState();
}

class _BouncePressState extends State<BouncePress> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        duration: Duration(milliseconds: _down ? 100 : 300),
        // Spring back out with the bouncy curve; quick scale-in on press.
        curve: _down ? kEaseSmooth : kEaseBounce,
        child: AnimatedRotation(
          turns: _down ? widget.rotateOnPress : 0.0,
          duration: const Duration(milliseconds: 150),
          child: widget.child,
        ),
      ),
    );
  }
}
