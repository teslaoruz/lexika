import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Small uppercase-ish Baloo label used above each entry section
/// (prototype `.section-label` / `.relations-label`).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: AppTheme.baloo(
            size: 11, weight: FontWeight.w700, color: color ?? AppColors.inkFaint),
      ),
    );
  }
}
