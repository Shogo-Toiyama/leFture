import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/profile/user_profile_provider.dart';
import 'package:lecture_companion_ui/presentation/pages/home/widgets/make_profile_sheet.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class UserProfileDetailPage extends ConsumerWidget {
  const UserProfileDetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final profile = profileAsync.asData?.value;
    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      appBar: AppBar(
        backgroundColor: AppColors.universe.voidBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFFF2F2F2), size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Profile',
          style: TextStyle(
            color: Color(0xFFF2F2F2),
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: AppColors.starGold, size: 20),
            tooltip: 'Edit Profile',
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => const MakeProfileSheet(),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            // ── Profile Detail Sections Card ───────────────────────────
            Container(
              decoration: BoxDecoration(
                color: AppColors.universe.glassWhiteLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.universe.glassBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProfileDetailItem(
                    icon: Icons.person_outline_rounded,
                    label: 'ABOUT YOU',
                    content: profile?.bio,
                    placeholder: 'No description set yet.',
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  _ProfileDetailItem(
                    icon: Icons.auto_awesome_outlined,
                    label: 'INTERESTS',
                    content: profile?.interests,
                    placeholder: 'No interests set yet.',
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  _ProfileDetailItem(
                    icon: Icons.flag_outlined,
                    label: 'FUTURE DREAMS',
                    content: profile?.futureGoals,
                    placeholder: 'No future dream set yet.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _ProfileDetailItem extends StatelessWidget {
  const _ProfileDetailItem({
    required this.icon,
    required this.label,
    this.content,
    required this.placeholder,
  });

  final IconData icon;
  final String label;
  final String? content;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final hasContent = content != null && content!.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 15,
                color: AppColors.starGold,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.starGold,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            hasContent ? content! : placeholder,
            style: TextStyle(
              color: hasContent
                  ? const Color(0xFFF2F2F2)
                  : AppColors.universe.textComet.withValues(alpha: 0.6),
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
