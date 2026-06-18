import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/bounce_press.dart';
import '../../widgets/play_button.dart';
import '../../widgets/section_label.dart';
import 'relations_panel.dart';

/// Full dictionary entry card + relations + actions (prototype `.entry-card`).
class EntryCard extends StatefulWidget {
  const EntryCard({
    super.key,
    required this.entry,
    required this.relations,
    required this.onLookup,
    required this.onSave,
  });

  final WordEntry entry;
  final WordRelations relations;
  final void Function(String word) onLookup;
  final VoidCallback onSave;

  @override
  State<EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<EntryCard> {
  String? _lang; // selected extra-translation language code (null if none)
  bool _saved = false;

  /// Available translation languages for this word, stable order.
  List<String> get _langs => widget.entry.translations.keys.toList()..sort();

  String get _effectiveLang =>
      (_lang != null && _langs.contains(_lang)) ? _lang! : _langs.first;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppColors.shadowMd,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head(e),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (e.definitionEn != null) ...[
                  const SectionLabel('✨ Definition'),
                  Text(e.definitionEn!,
                      style: AppTheme.quick(
                          size: 16,
                          weight: FontWeight.w500,
                          height: 1.6,
                          color: AppColors.ink)),
                  const SizedBox(height: 20),
                ],
                _translationBlock(e),
                if (e.exampleEn != null) ...[
                  const SectionLabel('💬 Example'),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.amberLight,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(e.exampleEn!,
                        style: AppTheme.quick(
                            size: 14.5,
                            weight: FontWeight.w500,
                            height: 1.6,
                            color: AppColors.inkSoft)),
                  ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
          RelationsPanel(
              relations: widget.relations, onLookup: widget.onLookup),
          _actions(),
        ],
      ),
    );
  }

  Widget _head(WordEntry e) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 28, 100, 20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.violetLight, AppColors.bgSoft],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (e.cefrLevel != null)
                    _badge('🎯 ${e.cefrLevel} level', AppColors.mintLight,
                        AppColors.mintDark),
                  if (e.isAcademic)
                    _badge('🎓 Academic word', AppColors.coralLight,
                        AppColors.coralDark),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(e.headword,
                        style: AppTheme.baloo(
                            size: 32, weight: FontWeight.w700, height: 1)),
                  ),
                  const SizedBox(width: 12),
                  PlayButton(word: e.headword),
                ],
              ),
              if (e.phonetic != null) ...[
                const SizedBox(height: 8),
                Text(e.phonetic!,
                    style: AppTheme.quick(
                        size: 14,
                        weight: FontWeight.w600,
                        color: AppColors.inkSoft)),
              ],
              if (e.partOfSpeech != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(e.partOfSpeech!,
                      style: AppTheme.quick(
                          size: 12,
                          weight: FontWeight.w700,
                          color: AppColors.violet)),
                ),
              ],
            ],
          ),
        ),
        if (_langs.isNotEmpty)
          Positioned(top: 20, right: 20, child: _langToggle()),
      ],
    );
  }

  Widget _badge(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
        child: Text(text,
            style:
                AppTheme.baloo(size: 11, weight: FontWeight.w700, color: fg)),
      );

  // Dynamic over whatever languages the word has — add "fa" etc. backend-side
  // and a chip appears here automatically.
  Widget _langToggle() {
    Widget btn(String code) {
      final active = _effectiveLang == code;
      return BouncePress(
        onTap: () => setState(() => _lang = code),
        pressedScale: 0.92,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: kEaseSmooth,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.violet : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
            boxShadow: active ? AppColors.shadowViolet : const [],
          ),
          child: Text(code.toUpperCase(),
              style: AppTheme.baloo(
                  size: 11.5,
                  weight: FontWeight.w700,
                  color: active ? AppColors.white : AppColors.inkFaint)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.bgSoft,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: _langs.map(btn).toList()),
    );
  }

  /// Translation is a secondary extra — a compact muted line under the
  /// definition, only when one exists. The English definition stays the focus.
  Widget _translationBlock(WordEntry e) {
    if (_langs.isEmpty) return const SizedBox.shrink();
    final word = e.translations[_effectiveLang];
    if (word == null || word.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.skyLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text('🌐 ${_effectiveLang.toUpperCase()}',
              style: AppTheme.baloo(
                  size: 11, weight: FontWeight.w700, color: AppColors.inkFaint)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(word,
                style: AppTheme.baloo(
                    size: 15, weight: FontWeight.w700, color: AppColors.inkSoft)),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 26),
      child: Row(
        children: [
          Expanded(
            child: AppButton(
              label: 'More examples',
              icon: Icons.nightlight_round,
              bg: AppColors.bgSoft,
              fg: AppColors.inkSoft,
              shadow: const [],
              onTap: () {},
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            // Save button: pops to mint + "Saved!" on tap.
            child: _SavePopButton(
              saved: _saved,
              onTap: () {
                if (_saved) return;
                setState(() => _saved = true);
                widget.onSave();
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Save button with scale-pop overshoot to 1.08 then settle, recoloring to mint.
class _SavePopButton extends StatefulWidget {
  const _SavePopButton({required this.saved, required this.onTap});
  final bool saved;
  final VoidCallback onTap;

  @override
  State<_SavePopButton> createState() => _SavePopButtonState();
}

class _SavePopButtonState extends State<_SavePopButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  late final Animation<double> _pop = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.08), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 60),
    // kEaseSmooth (not kEaseBounce): an overshooting curve feeds t>1 into
    // TweenSequence and throws. The 1.08 overshoot is already in the tween.
  ]).animate(CurvedAnimation(parent: _c, curve: kEaseSmooth));

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _pop,
      child: AppButton(
        label: widget.saved ? 'Saved!' : 'Save to deck',
        icon: widget.saved ? Icons.check_rounded : Icons.bookmark_outline_rounded,
        bg: widget.saved ? AppColors.mint : AppColors.coral,
        shadow: widget.saved ? AppColors.shadowMint : AppColors.shadowCoral,
        onTap: () {
          _c.forward(from: 0);
          widget.onTap();
        },
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
}
