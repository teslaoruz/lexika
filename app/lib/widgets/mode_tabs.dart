import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Segmented pill tabs under the top bar (prototype `.mode-tabs` / `.mode-tab`).
/// The active tab gets the dark ink fill + white label; kept in sync with the
/// bottom nav via the shared [index].
class ModeTabs extends StatelessWidget {
  const ModeTabs({super.key, required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const _labels = ['Look up', 'My decks', 'Progress'];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bgSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: List.generate(_labels.length, (i) {
          final active = i == index;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: kEaseSmooth,
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: active ? AppColors.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: active ? AppColors.shadowMd : const [],
                ),
                child: Text(
                  _labels[i],
                  textAlign: TextAlign.center,
                  style: AppTheme.baloo(
                    size: 13.5,
                    weight: FontWeight.w700,
                    color: active ? AppColors.white : AppColors.inkFaint,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
