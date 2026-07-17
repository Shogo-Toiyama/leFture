import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/application/debug/debug_providers.dart';
import 'package:lecture_companion_ui/domain/entities/user_profile.dart';
import 'package:lecture_companion_ui/application/profile/user_profile_provider.dart';
import 'package:lecture_companion_ui/presentation/pages/home/widgets/make_profile_sheet.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  Future<void> _signOut(BuildContext context) async {
    await supabase.auth.signOut();
    if (context.mounted) {
      context.go(AppRoutes.signIn);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final profile = profileAsync.asData?.value;

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ──────────────────────────────────────────────
          SliverAppBar(
            pinned: false,
            floating: true,
            backgroundColor: AppColors.universe.voidBackground,
            title: const Text(
              'Profile',
              style: TextStyle(
                color: Color(0xFFF2F2F2),
                fontWeight: FontWeight.w600,
                fontSize: 20,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Color(0xFFF2F2F2)),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => const MakeProfileSheet(),
                  );
                },
                tooltip: 'Edit Profile',
              ),
            ],
          ),

          // ── Body ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // SECTION 1 — PROFILE
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                _ProfileSection(profile: profile),

                const SizedBox(height: 32),

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // SECTION 2 — ACTIVITY
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                _SectionHeader(
                  icon: Icons.auto_stories_rounded,
                  label: 'Activity',
                  color: AppColors.starGold,
                ),
                const SizedBox(height: 8),
                _ActivitySection(),

                const SizedBox(height: 32),

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // SECTION 3 — SETTINGS
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                _SectionHeader(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  color: const Color(0xFF8E99A6),
                ),
                const SizedBox(height: 8),
                _SettingsSection(onSignOut: () => _signOut(context)),

                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 1: Profile
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.profile});
  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final displayName = profile?.username ?? 'Explorer';
    final initials = displayName.trim().isEmpty
        ? 'EX'
        : displayName
            .trim()
            .split(' ')
            .where((e) => e.isNotEmpty)
            .map((e) => e[0].toUpperCase())
            .take(2)
            .join('');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          // ── Avatar + Name Row ──────────────────────────────────
          Row(
            children: [
              // Avatar
              Stack(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7C83FD), Color(0xFFFFB300)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 24,
                        ),
                      ),
                    ),
                  ),
                  // Online badge
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppColors.growthGreen,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.universe.voidBackground,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // Name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Color(0xFFF2F2F2),
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Credit Bar ────────────────────────────────────────
          _CreditBar(percent: 0.70),

          const SizedBox(height: 20),

          // ── About You ─────────────────────────────────────────
          Row(
            children: [
              const Icon(
                Icons.person_outline_rounded,
                size: 15,
                color: AppColors.starGold,
              ),
              const SizedBox(width: 6),
              const Text(
                'ABOUT YOU',
                style: TextStyle(
                  color: AppColors.starGold,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0x1AFFFFFF),
              border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
            ),
            child: Text(
              profile?.bio ?? 'No description set yet.',
              style: const TextStyle(
                color: Color(0xFFF2F2F2),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Interests ─────────────────────────────────────────
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_outlined,
                size: 15,
                color: AppColors.starGold,
              ),
              const SizedBox(width: 6),
              const Text(
                'INTERESTS',
                style: TextStyle(
                  color: AppColors.starGold,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0x1AFFFFFF),
              border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
            ),
            child: Text(
              profile?.interests ?? 'No interests set yet.',
              style: const TextStyle(
                color: Color(0xFFF2F2F2),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Future Dreams ─────────────────────────────────────
          Row(
            children: [
              const Icon(
                Icons.flag_outlined,
                size: 15,
                color: AppColors.starGold,
              ),
              const SizedBox(width: 6),
              const Text(
                'FUTURE DREAMS',
                style: TextStyle(
                  color: AppColors.starGold,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0x1AFFFFFF),
              border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
            ),
            child: Text(
              profile?.futureGoals ?? 'No future dream set yet.',
              style: const TextStyle(
                color: Color(0xFFF2F2F2),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Credit Bar Widget
class _CreditBar extends StatelessWidget {
  const _CreditBar({required this.percent});
  final double percent;

  @override
  Widget build(BuildContext context) {
    final pct = (percent * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Credits',
              style: TextStyle(
                color: AppColors.universe.textComet,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$pct',
                    style: const TextStyle(
                      color: AppColors.starGold,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: ' / 100',
                    style: TextStyle(
                      color: AppColors.universe.textComet,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: Stack(
            children: [
              // Track
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0x1AFFFFFF),
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              // Fill
              FractionallySizedBox(
                widthFactor: percent,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
                    ),
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.starGold.withValues(alpha: 0.5),
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 2: Activity (Records)
// ─────────────────────────────────────────────────────────────────────────────

class _ActivitySection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        children: [
          _ActivityTile(
            icon: Icons.bookmark_rounded,
            iconColor: AppColors.starGold,
            iconBgColor: const Color(0xFF4CAF50),
            title: 'Saved',
            subtitle: 'Review Cards · Deep Notes',
            onTap: () => context.push('/profile/activity/saved'),
          ),
          _Divider(),
          _ActivityTile(
            icon: Icons.favorite_rounded,
            iconColor: AppColors.starGold,
            iconBgColor: const Color(0xFFE53935),
            title: 'Likes',
            subtitle: 'Review Cards · Deep Notes · Fun Facts',
            onTap: () => context.push('/profile/activity/likes'),
          ),
          _Divider(),
          _ActivityTile(
            icon: Icons.thumb_down_rounded,
            iconColor: AppColors.starGold,
            iconBgColor: const Color(0xFF2196F3),
            title: 'Dislikes',
            subtitle: 'Review Cards · Deep Notes · Fun Facts',
            onTap: () => context.push('/profile/activity/dislikes'),
          ),
          _Divider(),
          _ActivityTile(
            icon: Icons.campaign_rounded,
            iconColor: AppColors.starGold,
            iconBgColor: const Color(0xFF9C27B0),
            title: 'Announcements',
            subtitle: 'Including completed ones',
            onTap: () => context.push('/profile/activity/announcements'),
          ),
          _Divider(),
          _ActivityTile(
            icon: Icons.delete_outline_rounded,
            iconColor: AppColors.correctionRed,
            iconBgColor: AppColors.correctionRed,
            title: 'Trash',
            subtitle: 'Deleted courses & lectures',
            onTap: () => context.push('/profile/activity/trash'),
            showChevron: true,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconBgColor,
    this.showChevron = true,
    this.isLast = false,
  });

  final IconData icon;
  final Color iconColor;
  final Color? iconBgColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showChevron;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final bgColor = iconBgColor ?? iconColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.vertical(
          top: const Radius.circular(0),
          bottom: isLast ? const Radius.circular(16) : Radius.zero,
        ),
        splashColor: Colors.white10,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: bgColor.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFF2F2F2),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.universe.textComet,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.universe.textComet,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 3: Settings
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.onSignOut});
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Account
        _GlassCard(
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.email_outlined,
                iconColor: const Color(0xFF7C83FD),
                title: 'Change Email',
                onTap: () {},
              ),
              _Divider(),
              _SettingsTile(
                icon: Icons.lock_outline_rounded,
                iconColor: const Color(0xFF7C83FD),
                title: 'Change Password',
                onTap: () {},
                isLast: true,
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Legal & Support
        _GlassCard(
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                iconColor: AppColors.universe.textComet,
                title: 'Privacy Policy',
                onTap: () {},
              ),
              _Divider(),
              _SettingsTile(
                icon: Icons.gavel_rounded,
                iconColor: AppColors.universe.textComet,
                title: 'Terms of Service',
                onTap: () {},
              ),
              _Divider(),
              _SettingsTile(
                icon: Icons.mail_outline_rounded,
                iconColor: AppColors.universe.textComet,
                title: 'Contact Us',
                onTap: () {},
                isLast: true,
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Danger zone
        _GlassCard(
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.logout_rounded,
                iconColor: AppColors.correctionRed,
                title: 'Sign Out',
                titleColor: AppColors.correctionRed,
                onTap: onSignOut,
              ),
              _Divider(),
              _SettingsTile(
                icon: Icons.person_remove_outlined,
                iconColor: AppColors.correctionRed,
                title: 'Delete Account',
                titleColor: AppColors.correctionRed,
                onTap: () {},
                isLast: true,
              ),
            ],
          ),
        ),

        // Debug section (kept but tucked at the bottom)
        const SizedBox(height: 12),
        _DebugSection(),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
    this.titleColor,
    this.isLast = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Color? titleColor;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.vertical(
          bottom: isLast ? const Radius.circular(16) : Radius.zero,
        ),
        splashColor: Colors.white10,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: titleColor ?? const Color(0xFFF2F2F2),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.universe.textComet,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Debug Section (collapsed / hidden by default visually)
// ─────────────────────────────────────────────────────────────────────────────

class _DebugSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forceEmptyHome = ref.watch(debugForceEmptyHomeProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🛠 DEBUG',
            style: TextStyle(
              color: Colors.white24,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0x0AFFFFFF),
              border: Border.all(color: Colors.white12, width: 1),
            ),
            child: SwitchListTile(
              secondary: const Icon(
                Icons.bug_report,
                color: Colors.white30,
                size: 20,
              ),
              title: const Text(
                'Force Empty Home',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
              subtitle: const Text(
                'Shows onboarding state on Home.',
                style: TextStyle(color: Colors.white24, fontSize: 11),
              ),
              value: forceEmptyHome,
              activeThumbColor: AppColors.starGold,
              onChanged: (val) {
                ref.read(debugForceEmptyHomeProvider.notifier).toggle(val);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared UI Components
// ─────────────────────────────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: const Color(0x1AFFFFFF),
              border: Border.all(color: const Color(0x33FFFFFF), width: 0.8),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 0.5,
      color: Color(0x1AFFFFFF),
      indent: 66,
      endIndent: 0,
    );
  }
}