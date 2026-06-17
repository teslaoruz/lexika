import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Segmented tabs with a sliding ink-colored pill that animates between
/// positions (prototype `.mode-tabs`), rather than an instant swap.
class ModeTabs extends StatelessWidget {
  const ModeTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.bgSoft,
          borderRadius: BorderRadius.circular(18),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final n = labels.length;
            final tabW = c.maxWidth / n;
            return Stack(
              children: [
                // Sliding pill.
                AnimatedAlign(
                  alignment: Alignment(n == 1 ? 0 : (index / (n - 1)) * 2 - 1, 0),
                  duration: const Duration(milliseconds: 280),
                  curve: kEaseBounce,
                  child: Container(
                    width: tabW,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.ink,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: AppColors.shadowMd,
                    ),
                  ),
                ),
                Row(
                  children: List.generate(n, (i) {
                    final active = i == index;
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(i),
                        child: SizedBox(
                          height: 42,
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 250),
                              style: AppTheme.baloo(
                                size: 13.5,
                                weight: FontWeight.w700,
                                color: active
                                    ? AppColors.white
                                    : AppColors.inkFaint,
                              ),
                              child: Text(labels[i]),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
