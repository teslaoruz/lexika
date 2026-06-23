import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'bounce_press.dart';

/// Rounded action button (14–18px radius) with bounce press and an optional
/// leading icon. Baloo 2 label per design system.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.bg,
    this.fg,
    this.shadow = AppColors.shadowCoral,
    this.expand = true,
    this.radius = 18,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? bg;
  final Color? fg;
  final List<BoxShadow> shadow;
  final bool expand;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bg = this.bg ?? AppColors.coral;
    final fg = this.fg ?? AppColors.onAccent;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 7),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.baloo(size: 14.5, weight: FontWeight.w700, color: fg),
          ),
        ),
      ],
    );

    return BouncePress(
      onTap: onTap,
      pressedScale: 0.95,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: kEaseBounce,
        width: expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: shadow,
        ),
        child: content,
      ),
    );
  }
}
