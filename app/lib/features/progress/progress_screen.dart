import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// Wireframe-only empty state (prototype `.empty-state`). ponytail: charts are
/// a later phase.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.violetLight,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.show_chart_rounded,
                  size: 32, color: AppColors.violet),
            ),
            const SizedBox(height: 18),
            Text('Progress view',
                style: AppTheme.baloo(size: 17, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Charts of words mastered, streaks, and accuracy by level would live here — wireframe only for now.',
              textAlign: TextAlign.center,
              style: AppTheme.quick(
                  size: 13.5,
                  weight: FontWeight.w500,
                  height: 1.6,
                  color: AppColors.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}
