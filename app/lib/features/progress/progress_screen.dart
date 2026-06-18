import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';

/// Phase 3 dashboard: live streak / XP / words-learned tiles. ponytail: charts
/// (accuracy by level) are Phase 5 — these are the real numbers, not a wireframe.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);
    return stats.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.violet)),
      error: (_, _) => _centered('Could not load progress'),
      data: (s) => _dashboard(s),
    );
  }

  Widget _centered(String text) => Center(
        child: Text(text,
            style: AppTheme.quick(
                size: 14, weight: FontWeight.w500, color: AppColors.inkFaint)),
      );

  Widget _dashboard(UserStats s) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Row(children: [
          Expanded(
            child: _tile('🔥', '${s.currentStreak}', 'day streak',
                AppColors.amberLight, AppColors.amberDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _tile('⚡', '${s.totalXp}', 'total XP',
                AppColors.violetLight, AppColors.violet),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _tile('✅', '${s.totalWordsLearned}', 'words learned',
                AppColors.mintLight, AppColors.mintDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _tile('🏆', '${s.longestStreak}', 'longest streak',
                AppColors.coralLight, AppColors.coralDark),
          ),
        ]),
        const SizedBox(height: 20),
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              const Text('📊', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Accuracy-by-level charts arrive in the next phase. Keep reviewing to grow these numbers.',
                  style: AppTheme.quick(
                      size: 13,
                      weight: FontWeight.w500,
                      height: 1.5,
                      color: AppColors.inkFaint),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _tile(String emoji, String value, String label, Color fill,
      Color textOnFill) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 12),
            Text(value,
                style: AppTheme.baloo(
                    size: 26, weight: FontWeight.w800, color: textOnFill)),
            Text(label,
                style: AppTheme.quick(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: AppColors.inkSoft)),
          ],
        ),
      );
  }
}
