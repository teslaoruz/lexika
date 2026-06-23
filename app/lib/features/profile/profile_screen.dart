import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../api/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_chip.dart';
import '../../widgets/section_label.dart';

/// Signed-in user's profile: avatar + identity, live stat tiles (reusing the
/// Progress dashboard pattern), and a log-out action. Reads existing providers
/// only — no new state.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final stats = ref.watch(statsProvider);

    final email = (user?['email'] as String?) ?? '';
    final rawName = (user?['display_name'] as String?)?.trim();
    final name = (rawName != null && rawName.isNotEmpty)
        ? rawName
        : (email.isNotEmpty ? email.split('@').first : 'Learner');
    final nativeLanguage = (user?['native_language'] as String?);
    final level = (user?['current_level'] as String?);
    final avatar = (user?['avatar'] as String?);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _header(name, email, nativeLanguage, level, avatar),
        const SizedBox(height: 12),
        AppButton(
          label: 'Edit profile',
          icon: Icons.edit_rounded,
          bg: AppColors.violet,
          onTap: () => showDialog(
            context: context,
            builder: (_) => _EditProfileDialog(
              initialName: (user?['display_name'] as String?) ?? '',
              initialLang: nativeLanguage ?? 'ru',
              initialAvatar: avatar,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const SectionLabel('Your stats'),
        const SizedBox(height: 10),
        stats.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: CircularProgressIndicator(color: AppColors.violet)),
          ),
          error: (_, _) => _centered('Could not load stats'),
          data: _tiles,
        ),
        const SizedBox(height: 24),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          child: Row(
            children: [
              Text('🌙  Dark mode',
                  style: AppTheme.baloo(size: 15, weight: FontWeight.w700)),
              const Spacer(),
              Switch(
                value: ref.watch(themeModeProvider),
                activeThumbColor: AppColors.violet,
                onChanged: (_) =>
                    ref.read(themeModeProvider.notifier).toggle(),
              ),
            ],
          ),
        ),
        // Only meaningful in the browser — the native app is already installed.
        if (kIsWeb) ...[
          const SizedBox(height: 24),
          const SectionLabel('Get the app'),
          const SizedBox(height: 10),
          _getAppCard(),
        ],
        const SizedBox(height: 12),
        AppButton(
          label: 'Log out',
          icon: Icons.logout_rounded,
          bg: AppColors.coral,
          onTap: () => ref.read(authControllerProvider.notifier).logout(),
        ),
      ],
    );
  }

  /// APK download + iOS "add to home screen" hint (web only).
  static const _apkUrl =
      'https://github.com/teslaoruz/lexika/releases/latest/download/lexika.apk';

  Widget _getAppCard() => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📲  Install Lexika',
                style: AppTheme.baloo(size: 15, weight: FontWeight.w700)),
            const SizedBox(height: 12),
            AppButton(
              label: 'Download for Android (APK)',
              icon: Icons.android_rounded,
              bg: AppColors.mint,
              shadow: AppColors.shadowMint,
              onTap: () => launchUrl(Uri.parse(_apkUrl),
                  webOnlyWindowName: '_blank'),
            ),
            const SizedBox(height: 14),
            Text('On iPhone or iPad',
                style: AppTheme.baloo(
                    size: 13, weight: FontWeight.w700, color: AppColors.inkSoft)),
            const SizedBox(height: 4),
            Text(
              'Open this site in Safari, tap the Share button, then '
              '“Add to Home Screen” to install it like an app.',
              style: AppTheme.quick(
                  size: 13, height: 1.5, color: AppColors.inkFaint),
            ),
          ],
        ),
      );

  Widget _header(String name, String email, String? language, String? level,
      String? avatar) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '📖';
    final hasAvatar = avatar != null && avatar.isNotEmpty;
    return AppCard(
      padding: const EdgeInsets.all(20),
      radius: 28,
      shadow: AppColors.shadowMd,
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.violetLight,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Text(hasAvatar ? avatar : initial,
                style: hasAvatar
                    ? const TextStyle(fontSize: 40)
                    : AppTheme.baloo(
                        size: 34,
                        weight: FontWeight.w800,
                        color: AppColors.violet)),
          ),
          const SizedBox(height: 14),
          Text(name,
              textAlign: TextAlign.center,
              style: AppTheme.baloo(
                  size: 22, weight: FontWeight.w800, color: AppColors.ink)),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(email,
                textAlign: TextAlign.center,
                style: AppTheme.quick(
                    size: 13.5,
                    weight: FontWeight.w500,
                    color: AppColors.inkFaint)),
          ],
          if (language != null || level != null) ...[
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (language != null)
                  AppChip(
                    label: '🗣 ${_languageLabel(language)}',
                    useBaloo: true,
                    bg: AppColors.bgSoft,
                    fg: AppColors.inkSoft,
                  ),
                if (level != null)
                  AppChip(
                    label: '🎓 $level',
                    useBaloo: true,
                    bg: AppColors.violetLight,
                    fg: AppColors.violet,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _languageLabel(String code) {
    switch (code) {
      case 'ru':
        return 'Русский';
      case 'kk':
        return 'Қазақша';
      case 'fa':
        return 'فارسی';
      default:
        return code.toUpperCase();
    }
  }

  Widget _centered(String text) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(text,
              style: AppTheme.quick(
                  size: 14, weight: FontWeight.w500, color: AppColors.inkFaint)),
        ),
      );

  Widget _tiles(UserStats s) {
    return Column(
      children: [
        Row(children: [
          Expanded(
            child: _tile('🔥', '${s.currentStreak}', 'day streak',
                AppColors.amberLight, AppColors.amberDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _tile('⚡', '${s.totalXp}', 'total XP',
                AppColors.violetLight, AppColors.violet),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _tile('✅', '${s.totalWordsLearned}', 'words learned',
                AppColors.mintLight, AppColors.mintDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _tile('🏆', '${s.longestStreak}', 'longest streak',
                AppColors.coralLight, AppColors.coralDark),
          ),
        ]),
      ],
    );
  }

  Widget _tile(String emoji, String value, String label, Color fill,
      Color textOnFill) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(height: 12),
          Text(value,
              style: AppTheme.baloo(
                  size: 26, weight: FontWeight.w800, color: textOnFill)),
          Text(label,
              style: AppTheme.quick(
                  size: 12.5,
                  weight: FontWeight.w600,
                  color: AppColors.inkSoft)),
        ],
      ),
    );
  }
}

/// Pre-generated avatars to choose from (no uploads). ponytail: a flat emoji
/// set — add more entries here, no asset pipeline.
const _avatarChoices = [
  '🦊', '🐼', '🦉', '🐧', '🐸', '🐵', '🦄', '🐯',
  '🐱', '🐶', '🦁', '🐨', '🐰', '🐲', '🦋', '🌟',
];

class _EditProfileDialog extends ConsumerStatefulWidget {
  const _EditProfileDialog({
    required this.initialName,
    required this.initialLang,
    required this.initialAvatar,
  });

  final String initialName;
  final String initialLang;
  final String? initialAvatar;

  @override
  ConsumerState<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends ConsumerState<_EditProfileDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);
  late String _lang = widget.initialLang;
  late String? _avatar = widget.initialAvatar;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).updateProfile(
            displayName: _name.text.trim(),
            nativeLanguage: _lang,
            avatar: _avatar,
          );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('Edit profile',
          style: AppTheme.baloo(size: 20, weight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              style: AppTheme.quick(size: 15),
              decoration: InputDecoration(
                hintText: 'Display name',
                filled: true,
                fillColor: AppColors.bgSoft,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Native language',
                style: AppTheme.quick(size: 13.5, color: AppColors.inkSoft)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _langChip('ru', 'Русский'),
              _langChip('kk', 'Қазақша'),
              _langChip('fa', 'فارسی'),
            ]),
            const SizedBox(height: 16),
            Text('Avatar',
                style: AppTheme.quick(size: 13.5, color: AppColors.inkSoft)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _avatarChoices.map(_avatarTile).toList(),
            ),
          ],
        ),
      ),
      actions: [
        AppButton(
          label: _busy ? 'Saving…' : 'Save',
          onTap: _busy ? null : _save,
        ),
      ],
    );
  }

  Widget _langChip(String code, String label) {
    final selected = _lang == code;
    return AppChip(
      label: label,
      useBaloo: true,
      bg: selected ? AppColors.violet : AppColors.bgSoft,
      fg: selected ? AppColors.onAccent : AppColors.inkSoft,
      onTap: () => setState(() => _lang = code),
    );
  }

  Widget _avatarTile(String emoji) {
    final selected = _avatar == emoji;
    return GestureDetector(
      onTap: () => setState(() => _avatar = emoji),
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.violetLight : AppColors.bgSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.violet : Colors.transparent,
            width: 2,
          ),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}
