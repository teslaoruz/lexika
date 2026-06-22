import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'glass_surface.dart';

/// Bottom nav (prototype `.bottom-nav`) — active item gets coral pill bg.
/// Stays in sync with the mode tabs via shared [index].
class BottomNav extends StatelessWidget {
  const BottomNav({super.key, required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const _items = [
    (Icons.search_rounded, 'Look up'),
    (Icons.view_week_rounded, 'Decks'),
    (Icons.show_chart_rounded, 'Progress'),
    (Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: GlassSurface(
        radius: 24,
        padding: const EdgeInsets.all(6),
        shadow: AppColors.shadowMd,
        child: Row(
        children: List.generate(_items.length, (i) {
          final active = i == index;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: kEaseSmooth,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active ? AppColors.coralLight : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_items[i].$1,
                        size: 20,
                        color:
                            active ? AppColors.coral : AppColors.inkFaint),
                    const SizedBox(height: 3),
                    Text(_items[i].$2,
                        style: AppTheme.baloo(
                            size: 10.5,
                            weight: FontWeight.w700,
                            color: active
                                ? AppColors.coral
                                : AppColors.inkFaint)),
                  ],
                ),
              ),
            ),
          );
        }),
        ),
      ),
    );
  }
}
