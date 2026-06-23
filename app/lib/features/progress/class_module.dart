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

/// Phase 7 "Class" module on the Progress screen: join/create a class, then the
/// weekly leaderboard scoped to its members. ponytail: one widget, no new nav
/// tab — folded into the existing dashboard.
class ClassModule extends ConsumerStatefulWidget {
  const ClassModule({super.key});

  @override
  ConsumerState<ClassModule> createState() => _ClassModuleState();
}

class _ClassModuleState extends ConsumerState<ClassModule> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _act(Future<Cohort> Function(ApiClient) call) async {
    setState(() => _busy = true);
    try {
      await call(ref.read(apiClientProvider));
      ref.invalidate(cohortProvider);
      ref.invalidate(leaderboardProvider);
      ref.invalidate(cohortStudentsProvider);
      ref.invalidate(teachingClassesProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cohort = ref.watch(cohortProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Your class'),
        const SizedBox(height: 10),
        cohort.when(
          loading: () => const AppCard(
            child: Center(
                child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(color: AppColors.violet),
            )),
          ),
          error: (_, _) => const AppCard(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Could not load your class'),
            ),
          ),
          data: (c) => c == null ? _joinOrCreate() : _joined(c),
        ),
        _teachingSection(),
      ],
    );
  }

  /// Multi-class teacher area: every class the user created, each with its join
  /// code, a "send a deck" action, and a button to create another class.
  Widget _teachingSection() {
    final teaching = ref.watch(teachingClassesProvider);
    return teaching.maybeWhen(
      data: (classes) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          SectionLabel(classes.isEmpty ? 'Teaching' : 'Classes you teach'),
          const SizedBox(height: 10),
          for (final c in classes) ...[
            _teachingCard(c),
            const SizedBox(height: 10),
          ],
          AppButton(
            label: classes.isEmpty ? 'Create a class' : 'Create another class',
            icon: Icons.add_rounded,
            bg: AppColors.violet,
            shadow: AppColors.shadowViolet,
            onTap: _busy ? null : _createClass,
          ),
        ],
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }

  Widget _teachingCard(Cohort c) => AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name,
                          style: AppTheme.baloo(
                              size: 16, weight: FontWeight.w700)),
                      Text('${c.memberCount} member${c.memberCount == 1 ? '' : 's'}',
                          style: AppTheme.quick(
                              size: 12, color: AppColors.inkSoft)),
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
                    SelectableText(c.joinCode,
                        style: AppTheme.baloo(
                            size: 16,
                            weight: FontWeight.w800,
                            color: AppColors.violet,
                            letterSpacing: 1.5)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Send a deck',
                    icon: Icons.send_rounded,
                    bg: AppColors.mint,
                    shadow: AppColors.shadowMint,
                    onTap: _busy ? null : () => _sendDeck(c),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: 'Join QR',
                    icon: Icons.qr_code_rounded,
                    bg: AppColors.violet,
                    shadow: AppColors.shadowViolet,
                    onTap: () => showQrDialog(
                      context,
                      data: classQrData(c.joinCode),
                      title: 'Join “${c.name}”',
                      subtitle:
                          'Students scan this in Lexika to join — or enter '
                          'code ${c.joinCode}.',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Future<void> _createClass() async {
    final name = await _promptName('New class', 'Class name');
    if (name == null || name.isEmpty) return;
    await _act((api) => api.createCohort(name));
  }

  Future<void> _sendDeck(Cohort c) async {
    final api = ref.read(apiClientProvider);
    List<Deck> decks;
    try {
      decks = (await api.decks()).where((d) => !d.isSystemDeck).toList();
    } on ApiException catch (e) {
      _snack(e.message);
      return;
    }
    if (!mounted) return;
    if (decks.isEmpty) {
      _snack('Make a deck first, then send it to your class.');
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
                child: Text('Send which deck to “${c.name}”?',
                    style: AppTheme.baloo(size: 17, weight: FontWeight.w700)),
              ),
              for (final d in decks)
                BouncePress(
                  onTap: () => Navigator.of(ctx).pop(d),
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
                          child: Text(d.name,
                              style: AppTheme.baloo(
                                  size: 15, weight: FontWeight.w700)),
                        ),
                        Text('${d.cardCount}',
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
    try {
      final r = await api.sendDeckToClass(deck.id, c.id);
      ref.invalidate(teachingClassesProvider);
      _snack('Sent “${deck.name}” to ${r.sentTo} '
          'student${r.sentTo == 1 ? '' : 's'}.');
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<String?> _promptName(String title, String hint) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(title,
            style: AppTheme.baloo(size: 18, weight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.bgSoft,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          AppButton(
            label: 'Create',
            bg: AppColors.violet,
            onTap: () => Navigator.of(ctx).pop(ctrl.text.trim()),
          ),
        ],
      ),
    );
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Widget _joinOrCreate() => AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Join your class with a code',
                style: AppTheme.quick(
                    size: 13.5, weight: FontWeight.w600, color: AppColors.inkSoft)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _field(_code, 'CODE', caps: true)),
              const SizedBox(width: 8),
              AppButton(
                label: 'Join',
                expand: false,
                onTap: _busy
                    ? null
                    : () => _act((api) => api.joinCohort(_code.text.trim())),
              ),
              const SizedBox(width: 8),
              BouncePress(
                onTap: () => openScanner(context),
                pressedScale: 0.9,
                child: Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: AppColors.mintLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded,
                      size: 20, color: AppColors.mintDark),
                ),
              ),
            ]),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1),
            ),
            Text('…or create one (you’re the teacher)',
                style: AppTheme.quick(
                    size: 13.5, weight: FontWeight.w600, color: AppColors.inkSoft)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _field(_name, 'Class name')),
              const SizedBox(width: 10),
              AppButton(
                label: 'Create',
                expand: false,
                bg: AppColors.violet,
                shadow: AppColors.shadowViolet,
                onTap: _busy
                    ? null
                    : () => _act((api) => api.createCohort(_name.text.trim())),
              ),
            ]),
          ],
        ),
      );

  Widget _joined(Cohort c) {
    final lb = ref.watch(leaderboardProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        style: AppTheme.baloo(
                            size: 18, weight: FontWeight.w700)),
                    Text('${c.memberCount} member${c.memberCount == 1 ? '' : 's'}',
                        style: AppTheme.quick(
                            size: 12.5, color: AppColors.inkSoft)),
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
                  SelectableText(c.joinCode,
                      style: AppTheme.baloo(
                          size: 18,
                          weight: FontWeight.w800,
                          color: AppColors.violet,
                          letterSpacing: 1.5)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('This week',
            style: AppTheme.quick(
                size: 12.5, weight: FontWeight.w700, color: AppColors.inkSoft)),
        const SizedBox(height: 8),
        lb.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
                child: CircularProgressIndicator(color: AppColors.violet)),
          ),
          error: (_, _) => const Text('Could not load the leaderboard'),
          data: (rows) => rows.isEmpty
              ? Text('No XP earned this week yet — go review some words!',
                  style: AppTheme.quick(
                      size: 13, color: AppColors.inkFaint, height: 1.4))
              : Column(
                  children: [
                    for (final e in rows) ...[
                      _row(e),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
        ),
        if (c.isTeacher) _teacherDashboard(),
      ],
    );
  }

  /// Teacher-only: per-student progress across the class. ponytail: an
  /// ExpansionTile inside the same module, not a separate screen/route.
  Widget _teacherDashboard() {
    final students = ref.watch(cohortStudentsProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            title: Text('Teacher view — student progress',
                style: AppTheme.baloo(size: 15, weight: FontWeight.w700)),
            children: [
              students.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(
                      child: CircularProgressIndicator(color: AppColors.violet)),
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
                  size: 11.5, weight: FontWeight.w500, color: AppColors.inkFaint)),
        ]),
      );

  Widget _row(LeaderboardEntry e) {
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
                  size: 13.5,
                  weight: FontWeight.w700,
                  color: AppColors.violet)),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, {bool caps = false}) =>
      TextField(
        controller: c,
        textCapitalization:
            caps ? TextCapitalization.characters : TextCapitalization.sentences,
        autocorrect: false,
        style: AppTheme.quick(size: 15),
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: AppColors.bgSoft,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      );
}
