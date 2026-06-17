import 'dart:ui';

import 'package:flutter/material.dart';

/// Apple-style liquid-glass material. Frosted backdrop blur + a translucent
/// fill, a bright top-edge highlight, and a soft inner sheen.
///
/// ponytail: chrome-only by design — wrap nav bars / overlays / badges, NOT
/// content cards (glass over the flat lavender bg reads weakly; it shines over
/// gradients and scrolling content). One widget, reused everywhere glass is
/// wanted. Tint defaults to white; pass a color to match a surface.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = 18,
    this.tint = Colors.white,
    this.opacity = 0.55,
    this.padding,
    this.shadow,
  });

  final Widget child;
  final double radius;
  final double blur;
  final Color tint;
  final double opacity;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    final border = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: border,
        boxShadow: shadow,
      ),
      child: ClipRRect(
        borderRadius: border,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: border,
              // Translucent fill with a top-to-bottom sheen.
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  tint.withValues(alpha: opacity + 0.12),
                  tint.withValues(alpha: opacity - 0.08),
                ],
              ),
              // Bright top-edge highlight — the liquid-glass tell.
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.55),
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
