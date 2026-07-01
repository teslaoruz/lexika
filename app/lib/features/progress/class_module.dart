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
import 'class_detail_screen.dart';

/// "Classes" module on the Progress screen. A student can belong to several
/// classes; each is a card that opens the full class view (members, leaderboard,
/// shared decks, teacher tools). Below the list: join by code / scan, or create
/// a class. ponytail: the list + join/create only — everything else lives in
/// [ClassDetailScreen].
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
      ref.invalidate(myCohortsProvider);
      ref.invalidate(teachingClassesProvider);
      _code.clear();
      _name.clear();
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  void _open(int cohortId) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ClassDetailScreen(cohortId: cohortId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final classes = ref.watch(myCohortsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Your classes'),
        const SizedBox(height: 10),
        classes.when(
          loading: () => const AppCard(
            child: Padding(
              padding: EdgeInsets.all(16),
              child:
                  Center(child: CircularProgressIndicator(color: AppColors.violet)),
            ),
          ),
          error: (_, _) => const AppCard(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Could not load your classes'),
            ),
          ),
          data: (list) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final c in list) ...[
                _classCard(c),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 4),
              _joinOrCreate(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _classCard(Cohort c) => BouncePress(
        onTap: () => _open(c.id),
        pressedScale: 0.98,
        child: AppCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.isTeacher
                      ? AppColors.violetLight
                      : AppColors.mintLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                    c.isTeacher ? Icons.school_rounded : Icons.groups_rounded,
                    size: 20,
                    color: c.isTeacher
                        ? AppColors.violetDark
                        : AppColors.mintDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(c.name,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.baloo(
                                  size: 16, weight: FontWeight.w700)),
                        ),
                        if (c.isTeacher) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.violetLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('teacher',
                                style: AppTheme.quick(
                                    size: 10.5,
                                    weight: FontWeight.w700,
                                    color: AppColors.violetDark)),
                          ),
                        ],
                      ],
                    ),
                    Text(
                        '${c.memberCount} member${c.memberCount == 1 ? '' : 's'} • '
                        'code ${c.joinCode}',
                        style: AppTheme.quick(
                            size: 12, color: AppColors.inkSoft)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
            ],
          ),
        ),
      );

  Widget _joinOrCreate() => AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Join a class with a code',
                style: AppTheme.quick(
                    size: 13.5,
                    weight: FontWeight.w600,
                    color: AppColors.inkSoft)),
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
                    size: 13.5,
                    weight: FontWeight.w600,
                    color: AppColors.inkSoft)),
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
