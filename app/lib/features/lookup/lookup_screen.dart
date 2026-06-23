import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/bounce_press.dart';
import '../../widgets/fade_up.dart';
import 'entry_card.dart';

class LookupScreen extends ConsumerStatefulWidget {
  const LookupScreen({super.key});

  @override
  ConsumerState<LookupScreen> createState() => _LookupScreenState();
}

class _LookupScreenState extends ConsumerState<LookupScreen> {
  late final TextEditingController _ctrl =
      TextEditingController(text: ref.read(currentWordProvider));

  Timer? _debounce;
  List<String> _suggestions = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _lookup(String word) {
    final w = word.trim().toLowerCase();
    if (w.isEmpty) return;
    _ctrl.text = w;
    // Chosen / submitted: hide suggestions.
    _debounce?.cancel();
    if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
    ref.read(currentWordProvider.notifier).state = w;
  }

  // Live autocomplete: debounce keystrokes, then fetch headword suggestions.
  void _onChanged(String value) {
    final q = value.trim();
    _debounce?.cancel();
    if (q.isEmpty) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () => _fetchSuggestions(q));
  }

  Future<void> _fetchSuggestions(String query) async {
    try {
      final results = await ref.read(apiClientProvider).suggest(query);
      if (!mounted) return;
      // Drop stale results if the box changed since the request started.
      if (_ctrl.text.trim() != query) return;
      setState(() => _suggestions = results);
    } catch (_) {
      // Never crash the screen on a suggest failure — just show nothing.
      if (mounted && _suggestions.isNotEmpty) {
        setState(() => _suggestions = const []);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentWord = ref.watch(currentWordProvider).trim();
    final lookup = ref.watch(lookupProvider);
    final relations = ref.watch(relationsProvider);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Search box.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppColors.shadowSm,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.violetLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.search_rounded,
                      size: 18, color: AppColors.violet),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    textInputAction: TextInputAction.search,
                    onChanged: _onChanged,
                    onSubmitted: _lookup,
                    style: AppTheme.quick(
                        size: 16,
                        weight: FontWeight.w600,
                        color: AppColors.ink),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Type any English word…',
                      hintStyle: AppTheme.quick(
                          size: 16,
                          weight: FontWeight.w500,
                          color: AppColors.inkFaint),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Autocomplete dropdown — tappable headword suggestions.
        if (_suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppColors.shadowSm,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final s in _suggestions)
                    BouncePress(
                      onTap: () => _lookup(s),
                      pressedScale: 0.98,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 13),
                        child: Row(
                          children: [
                            Icon(Icons.north_west_rounded,
                                size: 15, color: AppColors.inkFaint),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(s,
                                  style: AppTheme.quick(
                                      size: 15,
                                      weight: FontWeight.w600,
                                      color: AppColors.ink)),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        // Entry.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: currentWord.isEmpty
              ? const _SearchPrompt()
              : lookup.when(
            loading: () => const _LoadingCard(),
            error: (e, _) => _ErrorCard(word: currentWord),
            data: (entry) => FadeUp(
              key: ValueKey(entry.headword),
              child: EntryCard(
                entry: entry,
                relations: relations.value ?? const WordRelations(),
                relationsLoading: relations.isLoading,
                onLookup: _lookup,
                onSave: () {},
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchPrompt extends StatelessWidget {
  const _SearchPrompt();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: AppColors.shadowMd,
        ),
        child: Column(
          children: [
            const Text('🔍', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text('Search any English word',
                style: AppTheme.baloo(size: 17, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'See its definition, examples, synonyms and a translation in your language.',
              textAlign: TextAlign.center,
              style: AppTheme.quick(
                  size: 13.5,
                  weight: FontWeight.w500,
                  height: 1.5,
                  color: AppColors.inkFaint),
            ),
          ],
        ),
      );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) => Container(
        height: 280,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: AppColors.shadowMd,
        ),
        child: const Center(
            child: CircularProgressIndicator(color: AppColors.violet)),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.word});
  final String word;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: AppColors.shadowMd,
        ),
        child: Column(
          children: [
            const Text('🙈', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text("Couldn't find \"$word\"",
                style:
                    AppTheme.baloo(size: 17, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              "Check the spelling, or the server may be offline.",
              textAlign: TextAlign.center,
              style: AppTheme.quick(
                  size: 13.5,
                  weight: FontWeight.w500,
                  height: 1.5,
                  color: AppColors.inkFaint),
            ),
          ],
        ),
      );
}
