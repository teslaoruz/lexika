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
    final accuracy = ref.watch(accuracyByLevelProvider);
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
        const SectionLabel('Activity'),
        const SizedBox(height: 10),
        _streakCalendar(ref.watch(activityProvider)),
        const SizedBox(height: 20),
        const SectionLabel('Accuracy by level'),
        const SizedBox(height: 10),
        accuracy.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: CircularProgressIndicator(color: AppColors.violet)),
          ),
          error: (_, _) => _centered('Could not load accuracy'),
          data: _accuracyChart,
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

  /// GitHub-style activity grid: the last 13 weeks, one cell per day, filled on
  /// days the user reviewed. Gaps make a broken streak visible at a glance.
  Widget _streakCalendar(AsyncValue<Set<String>> activity) {
    return activity.when(
      loading: () => const AppCard(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(
              child: CircularProgressIndicator(color: AppColors.violet)),
        ),
      ),
      error: (_, _) => _centered('Could not load activity'),
      data: (active) {
        two(int n) => n.toString().padLeft(2, '0');
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        const weeks = 13;
        // Start `weeks*7` days back, aligned to Monday so columns are weeks.
        var start = today.subtract(const Duration(days: weeks * 7 - 1));
        start = start.subtract(Duration(days: start.weekday - 1));

        final columns = <Widget>[];
        for (var day = start;
            !day.isAfter(today);
            day = day.add(const Duration(days: 7))) {
          final cells = <Widget>[];
          for (var d = 0; d < 7; d++) {
            final cellDay = day.add(Duration(days: d));
            if (cellDay.isAfter(today)) {
              cells.add(const SizedBox(width: 13, height: 13));
            } else {
              final iso =
                  '${cellDay.year}-${two(cellDay.month)}-${two(cellDay.day)}';
              final on = active.contains(iso);
              final isToday = cellDay == today;
              cells.add(Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: on ? AppColors.violet : AppColors.bgSoft,
                  borderRadius: BorderRadius.circular(3),
                  border: isToday
                      ? Border.all(color: AppColors.violetDark, width: 1.5)
                      : null,
                ),
              ));
            }
            if (d < 6) cells.add(const SizedBox(height: 3));
          }
          columns.add(Column(mainAxisSize: MainAxisSize.min, children: cells));
          columns.add(const SizedBox(width: 3));
        }

        return AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true, // keep the most recent weeks in view
                child: Row(children: columns),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Less',
                      style: AppTheme.quick(
                          size: 11, color: AppColors.inkFaint)),
                  const SizedBox(width: 6),
                  Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                          color: AppColors.bgSoft,
                          borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 4),
                  Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                          color: AppColors.violet,
                          borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 6),
                  Text('More',
                      style: AppTheme.quick(
                          size: 11, color: AppColors.inkFaint)),
                  const Spacer(),
                  Text('Each square is a day you practised',
                      style: AppTheme.quick(
                          size: 11, color: AppColors.inkFaint)),
                ],
              ),
            ],
          ),
        );
      },
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

  /// Accuracy-by-CEFR bar chart. ponytail: bars are sized Containers, no
  /// chart dependency. Empty bar = no attempts at that level yet.
  Widget _accuracyChart(List<LevelAccuracy> levels) {
    if (levels.every((l) => l.attempts == 0)) {
      return AppCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Review some words and your accuracy per level shows up here.',
            style: AppTheme.quick(
                size: 13,
                weight: FontWeight.w500,
                height: 1.4,
                color: AppColors.inkFaint),
          ),
        ),
      );
    }
    const maxBar = 110.0;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final l in levels)
            Expanded(child: _bar(l, maxBar)),
        ],
      ),
    );
  }

  Widget _bar(LevelAccuracy l, double maxBar) {
    final pct = l.accuracy ?? 0;
    // Red→amber→green as accuracy climbs; faint placeholder when untried.
    final color = l.attempts == 0
        ? AppColors.bgSoft
        : pct >= 0.8
            ? AppColors.mintDark
            : pct >= 0.5
                ? AppColors.amberDark
                : AppColors.coralDark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.accuracy == null ? '—' : '${(pct * 100).round()}%',
            style: AppTheme.quick(
                size: 11,
                weight: FontWeight.w700,
                color: l.attempts == 0 ? AppColors.inkFaint : AppColors.inkSoft)),
        const SizedBox(height: 6),
        Container(
          height: 8 + maxBar * pct,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 8),
        Text(l.level,
            style: AppTheme.quick(
                size: 12, weight: FontWeight.w700, color: AppColors.ink)),
      ],
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
