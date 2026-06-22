import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_chip.dart';
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

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _lookup(String word) {
    final w = word.trim().toLowerCase();
    if (w.isEmpty) return;
    _ctrl.text = w;
    ref.read(currentWordProvider.notifier).state = w;
    // Push to front of recent searches.
    final recents = ref.read(recentSearchesProvider);
    if (!recents.contains(w)) {
      ref.read(recentSearchesProvider.notifier).state = [w, ...recents].take(8).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lookup = ref.watch(lookupProvider);
    final relations = ref.watch(relationsProvider);
    final recents = ref.watch(recentSearchesProvider);

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
        // Recent chips.
        SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
            itemCount: recents.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => AppChip(
              label: recents[i],
              fontSize: 12.5,
              shadow: AppColors.shadowSm,
              onTap: () => _lookup(recents[i]),
            ),
          ),
        ),
        // Entry.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: lookup.when(
            loading: () => const _LoadingCard(),
            error: (e, _) => _ErrorCard(word: ref.read(currentWordProvider)),
            data: (entry) => FadeUp(
              key: ValueKey(entry.headword),
              child: EntryCard(
                entry: entry,
                relations: relations.maybeWhen(
                  data: (r) => r,
                  orElse: () => const WordRelations(),
                ),
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
              "Check the spelling, or the server may be offline. Try \"ubiquitous\" for the demo.",
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
