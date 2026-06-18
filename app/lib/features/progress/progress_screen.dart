import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/section_label.dart';
import 'class_module.dart';

/// Phase 3 dashboard + Phase 5 modules: live streak / XP / words-learned tiles,
/// then "work on these" (weak words) and "try next" (suggested words).
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);
    final weak = ref.watch(weakWordsProvider);
    final suggested = ref.watch(suggestedWordsProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        stats.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: CircularProgressIndicator(color: AppColors.violet)),
          ),
          error: (_, _) => _centered('Could not load progress'),
          data: _tiles,
        ),
        const SizedBox(height: 20),
        const SectionLabel('Work on these'),
        const SizedBox(height: 10),
        _tipList(weak, '🎯',
            empty: 'No weak words yet — keep reviewing and they’ll surface here.',
            trailing: (w) => w.accuracy == null
                ? null
                : '${(w.accuracy! * 100).round()}%'),
        const SizedBox(height: 20),
        const SectionLabel('Try these next'),
        const SizedBox(height: 10),
        _tipList(suggested, '✨',
            empty: 'Look up some words to get suggestions.',
            trailing: (w) => w.isAcademic ? 'academic' : null),
        const SizedBox(height: 20),
        const ClassModule(),
      ],
    );
  }

  Widget _centered(String text) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(text,
              style: AppTheme.quick(
                  size: 14, weight: FontWeight.w500, color: AppColors.inkFaint)),
        ),
      );

  Widget _tipList(AsyncValue<List<WordTip>> tips, String emoji,
      {required String empty, required String? Function(WordTip) trailing}) {
    return tips.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
            child: CircularProgressIndicator(color: AppColors.violet)),
      ),
      error: (_, _) => _centered('Could not load'),
      data: (list) {
        if (list.isEmpty) {
          return AppCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(empty,
                  style: AppTheme.quick(
                      size: 13,
                      weight: FontWeight.w500,
                      height: 1.4,
                      color: AppColors.inkFaint)),
            ),
          );
        }
        return Column(
          children: [
            for (final w in list) ...[
              _tipCard(w, emoji, trailing(w)),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }

  Widget _tipCard(WordTip w, String emoji, String? trailing) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(w.headword,
                        style: AppTheme.baloo(
                            size: 16,
                            weight: FontWeight.w700,
                            color: AppColors.ink)),
                  ),
                  if (w.cefrLevel != null) ...[
                    const SizedBox(width: 8),
                    Text(w.cefrLevel!,
                        style: AppTheme.quick(
                            size: 11,
                            weight: FontWeight.w700,
                            color: AppColors.violet)),
                  ],
                ]),
                if (w.definitionEn != null)
                  Text(w.definitionEn!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.quick(
                          size: 12.5,
                          weight: FontWeight.w500,
                          height: 1.35,
                          color: AppColors.inkSoft)),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            Text(trailing,
                style: AppTheme.quick(
                    size: 12,
                    weight: FontWeight.w700,
                    color: AppColors.inkFaint)),
          ],
        ],
      ),
    );
  }

  Widget _tiles(UserStats s) {
    return Column(
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
