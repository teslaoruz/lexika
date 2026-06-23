import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'bounce_press.dart';

/// Rounded, soft-shadowed surface. Corner radius 22–32 per design system.
/// If [onTap] is set it gets bounce-press feedback.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.color,
    this.shadow = AppColors.shadowSm,
    this.onTap,
    this.onLongPress,
    this.gradient,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? color;
  final List<BoxShadow> shadow;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Gradient? gradient;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? AppColors.white) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow,
      ),
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      child: child,
    );
    Widget result =
        onTap == null ? box : BouncePress(onTap: onTap, pressedScale: 0.97, child: box);
    if (onLongPress != null) {
      result = GestureDetector(onLongPress: onLongPress, child: result);
    }
    return result;
  }
}
