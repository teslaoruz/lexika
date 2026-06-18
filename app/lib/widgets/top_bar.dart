import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'bounce_press.dart';
import 'glass_surface.dart';
import 'sfx.dart';

/// Wordmark + live streak pill (prototype `.topbar`).
class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Show last-known streak while loading/erroring rather than a spinner.
    final streakDays =
        ref.watch(statsProvider).value?.currentStreak ?? 0;
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
          Row(
            children: [
              // Mute toggle (build-plan 5.8 — non-negotiable for classrooms).
              ValueListenableBuilder<bool>(
                valueListenable: Sfx.muted,
                builder: (context, muted, _) => BouncePress(
                  onTap: () => Sfx.muted.value = !muted,
                  pressedScale: 0.9,
                  child: GlassSurface(
                    radius: 100,
                    tint: AppColors.violet,
                    opacity: 0.18,
                    shadow: AppColors.shadowSm,
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      size: 18,
                      color: AppColors.violet,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
        ],
      ),
    );
  }
}
