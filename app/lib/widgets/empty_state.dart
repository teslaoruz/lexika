import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Centered empty-state block (prototype `.empty-state`): a soft violet emoji
/// tile, a Baloo title, and a muted one-liner. Reused wherever a list/section
/// has nothing to show yet.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    this.padding = const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
  });

  final String emoji;
  final String title;
  final String subtitle;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.violetLight,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 30)),
          ),
          const SizedBox(height: 18),
          Text(title,
              textAlign: TextAlign.center,
              style: AppTheme.baloo(size: 17, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(subtitle,
                textAlign: TextAlign.center,
                style: AppTheme.quick(
                    size: 13.5,
                    weight: FontWeight.w500,
                    height: 1.6,
                    color: AppColors.inkFaint)),
          ),
        ],
      ),
    );
  }
}
