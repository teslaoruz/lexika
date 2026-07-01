import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../api/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_chip.dart';

/// Admin-only overview of every user + an activity snapshot. Watches
/// [adminUsersProvider] (throws 403 for non-admins — handled below). ponytail:
/// a plain scrollable list of cards, no filtering/paging.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(adminUsersProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text('Admin — all users',
            style: AppTheme.baloo(size: 18, weight: FontWeight.w800)),
      ),
      body: users.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.violet)),
        error: (e, _) {
          final msg = (e is ApiException && e.status == 403)
              ? 'Admins only'
              : (e is ApiException ? e.message : 'Could not load users');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(msg,
                  textAlign: TextAlign.center,
                  style: AppTheme.quick(
                      size: 14,
                      weight: FontWeight.w600,
                      color: AppColors.inkFaint)),
            ),
          );
        },
        data: (list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _userCard(list[i]),
        ),
      ),
    );
  }

  Widget _userCard(AdminUser u) {
    final name = (u.displayName?.trim().isNotEmpty ?? false)
        ? u.displayName!.trim()
        : (u.email?.isNotEmpty ?? false)
            ? u.email!
            : 'User ${u.id}';
    final isGoogle = u.authProvider == 'google';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: AppTheme.baloo(size: 16, weight: FontWeight.w800)),
              ),
              if (u.isAdmin)
                AppChip(
                  label: 'admin',
                  useBaloo: true,
                  fontSize: 11,
                  bg: AppColors.violetLight,
                  fg: AppColors.violet,
                ),
              const SizedBox(width: 6),
              AppChip(
                label: isGoogle ? 'google' : 'password',
                useBaloo: true,
                fontSize: 11,
                bg: isGoogle ? AppColors.coralLight : AppColors.bgSoft,
                fg: isGoogle ? AppColors.coralDark : AppColors.inkSoft,
              ),
            ],
          ),
          if (u.email != null && u.email!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(u.email!,
                style: AppTheme.quick(
                    size: 12.5, weight: FontWeight.w500, color: AppColors.inkFaint)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _stat('⚡ ${u.totalXp} XP'),
              _stat('🔥 ${u.currentStreak}'),
              _stat('✅ ${u.wordsLearned} learned'),
              _stat('${u.reviewsRecent} reviews (7d)'),
            ],
          ),
          const SizedBox(height: 6),
          Text('Last active: ${_date(u.lastActive)}',
              style: AppTheme.quick(size: 12, color: AppColors.inkFaint)),
          if (u.classes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in u.classes)
                  AppChip(
                    label: c,
                    fontSize: 11,
                    bg: AppColors.mintLight,
                    fg: AppColors.mintDark,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String text) => Text(text,
      style: AppTheme.quick(
          size: 13, weight: FontWeight.w600, color: AppColors.inkSoft));

  // ISO string (e.g. "2026-07-01" or full timestamp) → just the date part.
  String _date(String? iso) {
    if (iso == null || iso.isEmpty) return 'never';
    return iso.length >= 10 ? iso.substring(0, 10) : iso;
  }
}
