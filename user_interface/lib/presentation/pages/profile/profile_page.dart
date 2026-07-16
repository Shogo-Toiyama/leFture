import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/application/debug/debug_providers.dart';
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
                onPressed: () {},
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
                _ProfileSection(),

                const SizedBox(height: 32),

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // SECTION 2 — ACTIVITY
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                _SectionHeader(
                  icon: Icons.auto_stories_rounded,
                  label: 'Activity',
                  // 💡 代替候補: 'Library' / 'Archive' / 'History' / 'Collection'
                  color: const Color(0xFF7C83FD),
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
  @override
  Widget build(BuildContext context) {
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
                    child: const Center(
                      child: Text(
                        'ST',
                        style: TextStyle(
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
              // Name + email
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Shogo Toiyama',
                      style: TextStyle(
                        color: Color(0xFFF2F2F2),
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'shogo@example.com',
                      style: TextStyle(
                        color: AppColors.universe.textComet,
                        fontSize: 13,
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

          // ── Bio ───────────────────────────────────────────────
          Text(
            'Bio',
            style: TextStyle(
              color: AppColors.universe.textComet,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Computer Science student passionate about AI and machine learning. I love building things that make learning more intuitive and fun.',
            style: TextStyle(
              color: Color(0xFFF2F2F2),
              fontSize: 14,
              height: 1.6,
            ),
          ),

          const SizedBox(height: 20),

          // ── Interests ─────────────────────────────────────────
          Text(
            'Interests',
            style: TextStyle(
              color: AppColors.universe.textComet,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _InterestChip(label: '🤖 Machine Learning'),
              _InterestChip(label: '🌌 Astrophysics'),
              _InterestChip(label: '🎵 Music Theory'),
              _InterestChip(label: '📚 Linguistics'),
              _InterestChip(label: '🧩 Algorithm Design'),
            ],
          ),

          const SizedBox(height: 20),

          // ── Future Dream ──────────────────────────────────────
          Text(
            'Future Dream',
            style: TextStyle(
              color: AppColors.universe.textComet,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0x1AFFFFFF),
              border: Border.all(color: const Color(0x26FFB300), width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('✨', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Build an AI system that personalizes education for every learner on the planet.',
                    style: TextStyle(
                      color: Color(0xFFF2F2F2),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
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

// Interest Chip
class _InterestChip extends StatelessWidget {
  const _InterestChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0x1AFFFFFF),
        border: Border.all(color: const Color(0x33FFFFFF), width: 1),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFF2F2F2),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
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
            iconColor: const Color(0xFF7C83FD),
            title: 'Saved',
            subtitle: 'Review Cards · Deep Notes',
            onTap: () {},
          ),
          _Divider(),
          _ActivityTile(
            icon: Icons.favorite_rounded,
            iconColor: const Color(0xFFFF6B8A),
            title: 'Likes',
            subtitle: 'Review Cards · Deep Notes · Fun Facts',
            onTap: () {},
          ),
          _Divider(),
          _ActivityTile(
            icon: Icons.thumb_down_rounded,
            iconColor: AppColors.universe.textComet,
            title: 'Dislikes',
            subtitle: 'Review Cards · Deep Notes · Fun Facts',
            onTap: () {},
          ),
          _Divider(),
          _ActivityTile(
            icon: Icons.campaign_rounded,
            iconColor: AppColors.alertAmber,
            title: 'Announcements',
            subtitle: 'Including completed ones',
            onTap: () {},
          ),
          _Divider(),
          _ActivityTile(
            icon: Icons.delete_outline_rounded,
            iconColor: AppColors.correctionRed,
            title: 'Trash',
            subtitle: 'Deleted courses & lectures',
            onTap: () {},
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
    this.showChevron = true,
    this.isLast = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showChevron;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
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
                  color: iconColor.withValues(alpha: 0.15),
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