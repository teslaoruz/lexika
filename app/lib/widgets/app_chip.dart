import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'bounce_press.dart';

/// Pill chip with bounce press. Used for recent searches, synonyms/antonyms.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.bg = AppColors.white,
    this.fg = AppColors.inkSoft,
    this.onTap,
    this.fontSize = 13,
    this.shadow = const [],
    this.useBaloo = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
  });

  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback? onTap;
  final double fontSize;
  final List<BoxShadow> shadow;
  final bool useBaloo;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final style = useBaloo
        ? AppTheme.baloo(size: fontSize, weight: FontWeight.w700, color: fg)
        : AppTheme.quick(size: fontSize, weight: FontWeight.w600, color: fg);
    return BouncePress(
      onTap: onTap,
      pressedScale: 0.92,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(100),
          boxShadow: shadow,
        ),
        child: Text(label, style: style),
      ),
    );
  }
}
