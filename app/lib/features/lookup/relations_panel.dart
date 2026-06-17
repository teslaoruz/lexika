import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_chip.dart';
import '../../widgets/bounce_press.dart';
import '../../widgets/section_label.dart';

/// Synonyms / antonyms / word-family / nominalization panel
/// (prototype `.relations-panel`). Each item tappable to re-lookup.
class RelationsPanel extends StatelessWidget {
  const RelationsPanel({
    super.key,
    required this.relations,
    required this.onLookup,
  });

  final WordRelations relations;
  final void Function(String word) onLookup;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    if (relations.synonyms.isNotEmpty) {
      rows.add(_row(
        '🟢 Synonyms',
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: relations.synonyms
              .map((s) => AppChip(
                    label: s,
                    bg: AppColors.mintLight,
                    fg: AppColors.mintDark,
                    onTap: () => onLookup(s),
                  ))
              .toList(),
        ),
      ));
    }

    if (relations.antonyms.isNotEmpty) {
      rows.add(_row(
        '🔴 Antonyms',
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: relations.antonyms
              .map((s) => AppChip(
                    label: s,
                    bg: AppColors.pinkLight,
                    fg: AppColors.antText,
                    onTap: () => onLookup(s),
                  ))
              .toList(),
        ),
      ));
    }

    if (relations.wordFamily.isNotEmpty) {
      rows.add(_row(
        '👨‍👩‍👧 Word family',
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: relations.wordFamily.map(_wfItem).toList(),
        ),
      ));
    }

    if (relations.nominalization != null) {
      rows.add(_row('🔄 Nominalization', _nominal(relations.nominalization!),
          last: true));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
  }

  Widget _row(String label, Widget content, {bool last = false}) => Padding(
        padding: EdgeInsets.only(bottom: last ? 6 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: SectionLabel(label),
            ),
            content,
          ],
        ),
      );

  Widget _wfItem(WordFamilyItem item) => BouncePress(
        onTap: () => onLookup(item.word),
        pressedScale: 0.94,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.violetLight,
            borderRadius: BorderRadius.circular(14),
          ),
          child: RichText(
            text: TextSpan(children: [
              TextSpan(
                text: '${item.pos.toUpperCase()}  ',
                style: AppTheme.baloo(
                    size: 9.5, weight: FontWeight.w700, color: AppColors.violet),
              ),
              TextSpan(
                text: item.word,
                style: AppTheme.baloo(
                    size: 14.5, weight: FontWeight.w600, color: AppColors.ink),
              ),
            ]),
          ),
        ),
      );

  Widget _nominal(Nominalization n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.bgSoft,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _nominalLine('adj', n.baseExample, AppColors.amberLight,
                AppColors.amberDark),
            const SizedBox(height: 9),
            _nominalLine('noun', n.nounExample, AppColors.mintLight,
                AppColors.mintDark),
          ],
        ),
      );

  Widget _nominalLine(String tag, String text, Color tagBg, Color tagFg) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 1),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: tagBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(tag.toUpperCase(),
                style: AppTheme.baloo(
                    size: 9.5, weight: FontWeight.w700, color: tagFg)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: AppTheme.quick(
                    size: 13.5,
                    weight: FontWeight.w500,
                    color: AppColors.inkSoft,
                    height: 1.6)),
          ),
        ],
      );
}
