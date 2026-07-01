import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../api/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/bounce_press.dart';
import '../../widgets/section_label.dart';
import '../share/qr_share.dart';

/// Everything about one class, opened by tapping a class card: members, the
/// weekly leaderboard, the decks shared to it, and (for the teacher) tools to
/// share a deck, see per-student progress, and delete the class. Students get a
/// "leave class" action. ponytail: one screen reading /cohorts/{id} + the
/// per-class leaderboard/students providers — no new state store.
class ClassDetailScreen extends ConsumerWidget {
  const ClassDetailScreen({super.key, required this.cohortId});

  final int cohortId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(cohortDetailProvider(cohortId));
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: Text(
          detail.maybeWhen(data: (d) => d.name, orElse: () => 'Class'),
          style: AppTheme.baloo(size: 18, weight: FontWeight.w800),
        ),
      ),
      body: detail.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.violet)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              e is ApiException ? e.message : 'Could not load this class',
              textAlign: TextAlign.center,
              style: AppTheme.quick(size: 14, color: AppColors.inkFaint),
            ),
          ),
        ),
        data: (d) => _Body(cohortId: cohortId, detail: d),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.cohortId, required this.detail});
  final int cohortId;
  final CohortDetail detail;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _busy = false;

  CohortDetail get d => widget.detail;
  int get cid => widget.cohortId;

  void _refresh() {
    ref.invalidate(cohortDetailProvider(cid));
    ref.invalidate(myCohortsProvider);
    ref.invalidate(teachingClassesProvider);
    ref.invalidate(leaderboardProvider(cid));
    ref.invalidate(cohortStudentsProvider(cid));
    ref.invalidate(decksProvider);
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        _header(),
        const SizedBox(height: 20),
        const SectionLabel('This week'),
        const SizedBox(height: 10),
        _leaderboard(),
        const SizedBox(height: 20),
        SectionLabel('Shared decks (${d.decks.length})'),
        const SizedBox(height: 10),
        _decks(),
        const SizedBox(height: 20),
        SectionLabel('Members (${d.members.length})'),
        const SizedBox(height: 10),
        _members(),
        if (d.isTeacher) ...[
          const SizedBox(height: 20),
          const SectionLabel('Teacher tools'),
          const SizedBox(height: 10),
          _teacherTools(),
        ] else ...[
          const SizedBox(height: 24),
          AppButton(
            label: 'Leave class',
            icon: Icons.logout_rounded,
            bg: AppColors.coral,
            shadow: AppColors.shadowCoral,
            onTap: _busy ? null : _leave,
          ),
        ],
      ],
    );
  }

  Widget _header() => AppCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.name,
                      style: AppTheme.baloo(size: 20, weight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    '${d.memberCount} member${d.memberCount == 1 ? '' : 's'}'
                    '${d.teacherName != null ? ' • teacher: ${d.teacherName}' : ''}',
                    style: AppTheme.quick(size: 12.5, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('CODE',
                    style: AppTheme.quick(
                        size: 10,
                        weight: FontWeight.w700,
                        color: AppColors.inkFaint)),
                SelectableText(d.joinCode,
                    style: AppTheme.baloo(
                        size: 18,
                        weight: FontWeight.w800,
                        color: AppColors.violet,
                        letterSpacing: 1.5)),
                const SizedBox(height: 4),
                BouncePress(
                  onTap: () => showQrDialog(
                    context,
                    data: classQrData(d.joinCode),
                    title: 'Join “${d.name}”',
                    subtitle: 'Scan in Lexika to join — or enter ${d.joinCode}.',
                  ),
                  pressedScale: 0.9,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.qr_code_rounded,
                          size: 15, color: AppColors.violet),
                      const SizedBox(width: 4),
                      Text('Show QR',
                          style: AppTheme.quick(
                              size: 12,
                              weight: FontWeight.w700,
                              color: AppColors.violet)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _leaderboard() {
    final lb = ref.watch(leaderboardProvider(cid));
    return lb.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(color: AppColors.violet)),
      ),
      error: (_, _) => const Text('Could not load the leaderboard'),
      data: (rows) => rows.isEmpty
          ? _emptyCard('No XP earned this week yet — go review some words!')
          : Column(
              children: [
                for (final e in rows) ...[
                  _lbRow(e),
                  const SizedBox(height: 8),
                ],
              ],
            ),
    );
  }

  Widget _lbRow(LeaderboardEntry e) {
    final medal = switch (e.rank) { 1 => '🥇', 2 => '🥈', 3 => '🥉', _ => null };
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: e.isMe ? AppColors.violetLight : AppColors.white,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: medal != null
                ? Text(medal, style: const TextStyle(fontSize: 18))
                : Text('${e.rank}',
                    style: AppTheme.baloo(
                        size: 15,
                        weight: FontWeight.w700,
                        color: AppColors.inkFaint)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(e.isMe ? '${e.displayName} (you)' : e.displayName,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.baloo(
                    size: 15,
                    weight: FontWeight.w700,
                    color: e.isMe ? AppColors.violetDark : AppColors.ink)),
          ),
          Text('${e.weeklyXp} XP',
              style: AppTheme.quick(
                  size: 13.5, weight: FontWeight.w700, color: AppColors.violet)),
        ],
      ),
    );
  }

  Widget _decks() {
    if (d.decks.isEmpty) {
      return _emptyCard(d.isTeacher
          ? 'Share a deck below — every member (including new ones) will see it.'
          : 'Your teacher hasn’t shared any decks yet.');
    }
    return Column(
      children: [
        for (final deck in d.decks) ...[
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.folder_shared_rounded,
                    size: 18, color: AppColors.violet),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(deck.name,
                      style: AppTheme.baloo(size: 15, weight: FontWeight.w700)),
                ),
                Text('${deck.cardCount} word${deck.cardCount == 1 ? '' : 's'}',
                    style:
                        AppTheme.quick(size: 12.5, color: AppColors.inkFaint)),
                if (d.isTeacher)
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: AppColors.coralDark),
                    tooltip: 'Stop sharing',
                    onPressed: _busy ? null : () => _unshare(deck),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _members() => Column(
        children: [
          for (final m in d.members) ...[
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              color: AppColors.bgSoft,
              child: Row(
                children: [
                  Icon(Icons.person_rounded,
                      size: 18, color: AppColors.inkSoft),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(m.displayName,
                        overflow: TextOverflow.ellipsis,
                        style:
                            AppTheme.baloo(size: 15, weight: FontWeight.w700)),
                  ),
                  if (m.isTeacher)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.violetLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('teacher',
                          style: AppTheme.quick(
                              size: 11,
                              weight: FontWeight.w700,
                              color: AppColors.violetDark)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      );

  Widget _teacherTools() {
    final students = ref.watch(cohortStudentsProvider(cid));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          label: 'Share a deck',
          icon: Icons.send_rounded,
          bg: AppColors.mint,
          shadow: AppColors.shadowMint,
          onTap: _busy ? null : _shareDeck,
        ),
        const SizedBox(height: 14),
        AppCard(
          padding: EdgeInsets.zero,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              title: Text('Student progress',
                  style: AppTheme.baloo(size: 15, weight: FontWeight.w700)),
              children: [
                students.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(
                        child:
                            CircularProgressIndicator(color: AppColors.violet)),
                  ),
                  error: (_, _) => const Text('Could not load students'),
                  data: (list) => Column(
                    children: [
                      for (final s in list) ...[
                        _studentRow(s),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        AppButton(
          label: 'Delete class',
          icon: Icons.delete_outline_rounded,
          bg: AppColors.coral,
          shadow: AppColors.shadowCoral,
          onTap: _busy ? null : _deleteClass,
        ),
      ],
    );
  }

  Widget _studentRow(StudentProgress s) {
    final name = s.isTeacher ? '${s.displayName} (you)' : s.displayName;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      color: AppColors.bgSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.baloo(size: 15, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _stat('${s.weeklyXp} XP', 'this week'),
              _stat('${s.totalXp} XP', 'total'),
              _stat('🔥 ${s.currentStreak}', 'streak'),
              _stat('✅ ${s.wordsLearned}', 'learned'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => RichText(
        text: TextSpan(children: [
          TextSpan(
              text: '$value ',
              style: AppTheme.quick(
                  size: 13, weight: FontWeight.w700, color: AppColors.ink)),
          TextSpan(
              text: label,
              style: AppTheme.quick(
                  size: 11.5,
                  weight: FontWeight.w500,
                  color: AppColors.inkFaint)),
        ]),
      );

  Widget _emptyCard(String text) => AppCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(text,
              style: AppTheme.quick(
                  size: 13,
                  weight: FontWeight.w500,
                  height: 1.4,
                  color: AppColors.inkFaint)),
        ),
      );

  // ---- actions ----
  Future<void> _shareDeck() async {
    final api = ref.read(apiClientProvider);
    List<Deck> decks;
    try {
      decks = (await api.decks())
          .where((x) => !x.isSystemDeck && !x.isShared)
          .toList();
    } on ApiException catch (e) {
      _snack(e.message);
      return;
    }
    if (!mounted) return;
    if (decks.isEmpty) {
      _snack('Make a deck first, then share it with your class.');
      return;
    }
    final deck = await showModalBottomSheet<Deck>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('Share which deck with “${d.name}”?',
                    style: AppTheme.baloo(size: 17, weight: FontWeight.w700)),
              ),
              for (final deck in decks)
                BouncePress(
                  onTap: () => Navigator.of(ctx).pop(deck),
                  pressedScale: 0.98,
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.bgSoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_rounded,
                            size: 18, color: AppColors.violet),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(deck.name,
                              style: AppTheme.baloo(
                                  size: 15, weight: FontWeight.w700)),
                        ),
                        Text('${deck.cardCount}',
                            style: AppTheme.quick(
                                size: 13, color: AppColors.inkFaint)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (deck == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await api.shareDeckToClass(cid, deck.id);
      _refresh();
      _snack('Shared “${deck.name}” with the class '
          '(${r.sharedTo} member${r.sharedTo == 1 ? '' : 's'}).');
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unshare(ClassDeck deck) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).unshareDeck(cid, deck.id);
      _refresh();
      _snack('Stopped sharing “${deck.name}”.');
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (!await _confirm('Leave “${d.name}”?',
        'You can rejoin later with the class code.')) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).leaveCohort(cid);
      ref.invalidate(myCohortsProvider);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      _snack(e.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteClass() async {
    if (!await _confirm('Delete “${d.name}”?',
        'This removes the class for everyone. Decks and progress are kept.')) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).deleteCohort(cid);
      ref.invalidate(myCohortsProvider);
      ref.invalidate(teachingClassesProvider);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      _snack(e.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(title,
            style: AppTheme.baloo(size: 18, weight: FontWeight.w700)),
        content: Text(body,
            style: AppTheme.quick(size: 14, height: 1.4, color: AppColors.inkSoft)),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style: AppTheme.quick(size: 14, color: AppColors.inkFaint)),
          ),
          AppButton(
            label: 'Confirm',
            expand: false,
            bg: AppColors.coral,
            shadow: AppColors.shadowCoral,
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}
