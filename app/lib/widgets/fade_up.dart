import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Replays the prototype's `@keyframes fadeUp`: fade in + ~10px upward slide,
/// ~300ms. Used on screen switch and entry-card appearance. Keyed by [trigger]
/// so it re-runs when the content identity changes.
class FadeUp extends StatefulWidget {
  const FadeUp({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 320),
  });

  final Widget child;
  final Duration duration;

  @override
  State<FadeUp> createState() => _FadeUpState();
}

class _FadeUpState extends State<FadeUp> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration)..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: kEaseSmooth);
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 10 * (1 - curved.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
