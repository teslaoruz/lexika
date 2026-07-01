import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';

/// The list behind the "words learned" tile on Progress: every word the user has
/// learned (survived enough reviews), newest first. ponytail: one screen reading
/// [learnedWordsProvider] — reuses the WordTip row shape.
class LearnedWordsScreen extends ConsumerWidget {
  const LearnedWordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final learned = ref.watch(learnedWordsProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: Text('Words you learned',
            style: AppTheme.baloo(size: 18, weight: FontWeight.w800)),
      ),
      body: learned.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.violet)),
        error: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load your learned words',
                style: AppTheme.quick(size: 14, color: AppColors.inkFaint)),
          ),
        ),
        data: (list) => list.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Nothing here yet — review a word a few times and it lands '
                    'here once you’ve learned it. ✅',
                    textAlign: TextAlign.center,
                    style: AppTheme.quick(
                        size: 14, height: 1.5, color: AppColors.inkFaint),
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _row(list[i]),
              ),
      ),
    );
  }

  Widget _row(WordTip w) => AppCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: Row(
          children: [
            const Text('✅', style: TextStyle(fontSize: 18)),
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
                  if (w.translation != null)
                    Text(w.translation!,
                        style: AppTheme.quick(
                            size: 12.5,
                            weight: FontWeight.w500,
                            color: AppColors.inkFaint)),
                ],
              ),
            ),
          ],
        ),
      );
}
