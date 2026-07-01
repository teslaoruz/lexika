import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/section_label.dart';
import 'class_module.dart';
import 'learned_words_screen.dart';

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
          data: (s) => _tiles(context, s),
        ),
        const SizedBox(height: 20),
        const SectionLabel('Activity'),
        const SizedBox(height: 10),
        const _ActivityCalendar(),
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
        Theme(
          data: Theme.of(context)
              .copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 10),
            title: Text('Try these next ✨',
                style: AppTheme.baloo(
                    size: 15,
                    weight: FontWeight.w700,
                    color: AppColors.inkSoft)),
            iconColor: AppColors.violet,
            collapsedIconColor: AppColors.inkFaint,
            children: [
              _tipList(suggested, '✨',
                  empty: 'Look up some words to get suggestions.',
                  trailing: (w) => w.isAcademic ? 'academic' : null),
            ],
          ),
        ),
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

  Widget _tiles(BuildContext context, UserStats s) {
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
            // Tap to see which words you've actually learned.
            child: _tile('✅', '${s.totalWordsLearned}', 'words learned',
                AppColors.mintLight, AppColors.mintDark,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const LearnedWordsScreen()))),
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
      Color textOnFill, {VoidCallback? onTap}) {
    final card = AppCard(
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
    if (onTap == null) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: card,
    );
  }
}

/// Collapsed summary that expands into a real month calendar. Days the user
/// practised (from [activityProvider]) are highlighted; today gets an outline.
class _ActivityCalendar extends ConsumerStatefulWidget {
  const _ActivityCalendar();

  @override
  ConsumerState<_ActivityCalendar> createState() => _ActivityCalendarState();
}

class _ActivityCalendarState extends ConsumerState<_ActivityCalendar> {
  bool _open = false;
  late DateTime _month; // first day of the shown month

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'
  ];

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(statsProvider);
    final streak = stats.maybeWhen(
        data: (s) => s.currentStreak, orElse: () => 0);

    if (!_open) {
      return AppCard(
        onTap: () => setState(() => _open = true),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Row(
          children: [
            const Text('🔥', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$streak day streak',
                      style: AppTheme.baloo(
                          size: 16,
                          weight: FontWeight.w700,
                          color: AppColors.ink)),
                  Text('View activity calendar',
                      style: AppTheme.quick(
                          size: 12.5,
                          weight: FontWeight.w600,
                          color: AppColors.inkFaint)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.inkFaint),
          ],
        ),
      );
    }

    final activity = ref.watch(activityProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisMonth = DateTime(now.year, now.month);
    final canGoForward = _month.isBefore(thisMonth);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month header with paging arrows.
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() =>
                    _month = DateTime(_month.year, _month.month - 1)),
                child: Icon(Icons.chevron_left, color: AppColors.violet),
              ),
              Expanded(
                child: Text('${_months[_month.month - 1]} ${_month.year}',
                    textAlign: TextAlign.center,
                    style: AppTheme.baloo(
                        size: 16,
                        weight: FontWeight.w700,
                        color: AppColors.ink)),
              ),
              GestureDetector(
                onTap: canGoForward
                    ? () => setState(() =>
                        _month = DateTime(_month.year, _month.month + 1))
                    : null,
                child: Icon(Icons.chevron_right,
                    color: canGoForward
                        ? AppColors.violet
                        : AppColors.inkFaint),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final w in _weekdays)
                Expanded(
                  child: Text(w,
                      textAlign: TextAlign.center,
                      style: AppTheme.quick(
                          size: 11,
                          weight: FontWeight.w700,
                          color: AppColors.inkFaint)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          activity.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.violet)),
            ),
            error: (_, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Could not load activity',
                  style: AppTheme.quick(
                      size: 13, color: AppColors.inkFaint)),
            ),
            data: (active) => _grid(active, today),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                    color: AppColors.violet,
                    borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 6),
              Text('Days you practised',
                  style: AppTheme.quick(
                      size: 11, color: AppColors.inkFaint)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _grid(Set<String> active, DateTime today) {
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = _month.weekday - 1; // Monday = 0 blanks
    final cells = <Widget>[];
    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final d = DateTime(_month.year, _month.month, day);
      final iso = '${d.year}-${_two(d.month)}-${_two(d.day)}';
      final on = active.contains(iso);
      final isToday = d == today;
      cells.add(Container(
        margin: const EdgeInsets.all(3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.violet : null,
          borderRadius: BorderRadius.circular(10),
          border: isToday
              ? Border.all(color: AppColors.violetDark, width: 1.5)
              : null,
        ),
        child: Text('$day',
            style: AppTheme.quick(
                size: 13,
                weight: FontWeight.w600,
                color: on ? AppColors.white : AppColors.inkSoft)),
      ));
    }
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cells,
    );
  }
}
