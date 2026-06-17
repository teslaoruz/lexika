import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'bounce_press.dart';
import 'glass_surface.dart';

/// Wordmark + streak pill (prototype `.topbar`).
class TopBar extends StatelessWidget {
  const TopBar({super.key, this.streakDays = 12});

  final int streakDays;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Transform.rotate(
                angle: -0.105, // -6deg
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.coral, AppColors.pink],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: AppColors.shadowCoral,
                  ),
                  child: const Text('📖', style: TextStyle(fontSize: 15)),
                ),
              ),
              const SizedBox(width: 6),
              Text('Lexika',
                  style: AppTheme.baloo(size: 24, weight: FontWeight.w700)),
            ],
          ),
          BouncePress(
            onTap: () {},
            pressedScale: 0.94,
            child: GlassSurface(
              radius: 100,
              tint: AppColors.amber,
              opacity: 0.32,
              shadow: AppColors.shadowSm,
              padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
              child: Text('🔥 $streakDays day streak',
                  style: AppTheme.baloo(
                      size: 14,
                      weight: FontWeight.w700,
                      color: AppColors.amberDark)),
            ),
          ),
        ],
      ),
    );
  }
}
