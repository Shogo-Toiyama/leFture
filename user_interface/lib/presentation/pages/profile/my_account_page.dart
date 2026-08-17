import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/application/auth/auth_provider.dart';
import 'package:lefture/application/credit/credit_providers.dart';
import 'package:lefture/domain/entities/credit_summary.dart';
import 'package:lefture/application/debug/debug_providers.dart';
import 'package:lefture/domain/entities/user_profile.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/application/profile/user_profile_provider.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:lefture/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';
import 'package:lefture/presentation/pages/profile/widgets/change_email_sheet.dart';
import 'package:lefture/presentation/pages/profile/widgets/change_password_sheet.dart';
import 'package:lefture/presentation/pages/profile/widgets/change_auth_provider_sheet.dart';
import 'package:lefture/presentation/pages/profile/widgets/change_account_sheet.dart';
import 'package:lefture/presentation/pages/profile/widgets/change_avatar_sheet.dart';
import 'package:lefture/presentation/pages/profile/widgets/sign_out_flow.dart';
import 'package:lefture/application/profile/display_language_controller.dart';
import 'package:lefture/application/recording/recording_language_controller.dart';
import 'package:lefture/domain/entities/app_language.dart';
import 'package:lefture/presentation/pages/profile/widgets/language_selection_sheet.dart';
import 'package:lefture/infrastructure/repositories/backend_warmup.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/app_error_dialog.dart';
import 'package:lefture/presentation/widgets/user_avatar.dart';
import 'package:lefture/presentation/widgets/spaceship_announcement_modal.dart';
import 'package:lefture/application/transmission/transmission_provider.dart';

class MyAccountPage extends ConsumerWidget {
  const MyAccountPage({super.key});

  /// サインアウトは「未送信データの送信 → 破棄の同意 → ローカルデータのwipe →
  /// signOut」という手順を踏む(sign_out_flow.dart)。ローカルDBはサインアウトでも
  /// 消えないままだと複数アカウントの行が同居して壊れるため、ここで消し切る。
  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await runSignOutFlow(context, ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
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
            title: Text(
              l10n.myAccountTitle,
              style: const TextStyle(
                color: Color(0xFFF2F2F2),
                fontWeight: FontWeight.w600,
                fontSize: 20,
              ),
            ),
          ),

          // ── Body ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header (Avatar + Name & Credit Card)
                _HeaderSection(profile: profile),

                const SizedBox(height: 32),

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // SECTION 1 — PROFILE
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                _SectionHeader(
                  icon: Icons.person_rounded,
                  label: l10n.myAccountSectionProfile,
                  color: AppColors.starGold,
                ),
                const SizedBox(height: 8),
                _ProfileTilesSection(profile: profile),

                const SizedBox(height: 32),

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // SECTION 2 — ACTIVITY
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                _SectionHeader(
                  icon: Icons.auto_stories_rounded,
                  label: l10n.myAccountSectionActivity,
                  color: AppColors.starGold,
                ),
                const SizedBox(height: 8),
                _ActivitySection(),

                const SizedBox(height: 32),

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // SECTION 3 — APPLICATION
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                _SectionHeader(
                  icon: Icons.rocket_launch_rounded,
                  label: l10n.myAccountSectionApplication,
                  color: AppColors.starGold,
                ),
                const SizedBox(height: 8),
                _ApplicationSection(),

                const SizedBox(height: 32),

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // SECTION 4 — SETTINGS
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                _SectionHeader(
                  icon: Icons.settings_rounded,
                  label: l10n.myAccountSectionSettings,
                  color: const Color(0xFF8E99A6),
                ),
                const SizedBox(height: 8),
                _SettingsSection(onSignOut: () => _signOut(context, ref)),

                const SizedBox(height: 32),

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // VERSION FOOTER
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                const _VersionFooter(),
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
// HEADER: User Avatar & Credit Card
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderSection extends HookConsumerWidget {
  const _HeaderSection({required this.profile});
  final UserProfile? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isEditing = useState(false);
    final displayName = profile?.username ?? l10n.myAccountDefaultDisplayName;
    final controller = useTextEditingController(text: displayName);
    final isSubmitting = useState(false);

    useEffect(() {
      if (!isEditing.value) {
        controller.text = displayName;
      }
      return null;
    }, [displayName, isEditing.value]);

    Future<void> saveUsername() async {
      final newName = controller.text.trim();
      if (newName.isEmpty ||
          !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(newName) ||
          newName == displayName) {
        isEditing.value = false;
        controller.text = displayName;
        return;
      }

      isSubmitting.value = true;
      try {
        final repo = ref.read(userProfileRepositoryProvider);
        await repo.updateProfile(username: newName);
        ref.read(lectureControllerProvider.notifier).pushOutboxNow();
        isEditing.value = false;
      } catch (e) {
        if (context.mounted) {
          AppErrorDialog.showSmart(
            context,
            e,
            actionName: 'updating display name',
          );
        }
      } finally {
        isSubmitting.value = false;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // ── Avatar + Name Row ──────────────────────────────────
              Row(
                children: [
                  // Avatar (Tapping opens ChangeAvatarSheet)
                  GestureDetector(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => ChangeAvatarSheet(profile: profile),
                      );
                    },
                    child: Stack(
                      children: [
                        UserAvatar(profile: profile, size: 72),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.starGold,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.universe.voidBackground,
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.edit_rounded,
                              size: 12,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Name (Inline Editing)
                  Expanded(
                    child: isEditing.value
                        ? Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: controller,
                                  autofocus: true,
                                  style: const TextStyle(
                                    color: Color(0xFFF2F2F2),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withValues(
                                      alpha: 0.08,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: AppColors.starGold,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: AppColors.starGold,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                  onSubmitted: (_) => saveUsername(),
                                ),
                              ),
                              const SizedBox(width: 4),
                              if (isSubmitting.value)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.starGold,
                                  ),
                                )
                              else ...[
                                IconButton(
                                  icon: const Icon(
                                    Icons.check_rounded,
                                    color: AppColors.growthGreen,
                                    size: 22,
                                  ),
                                  onPressed: saveUsername,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: l10n.myAccountSaveNameTooltip,
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white54,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    isEditing.value = false;
                                    controller.text = displayName;
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: l10n.myAccountCancelEditTooltip,
                                ),
                              ],
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: Text(
                                  displayName,
                                  style: const TextStyle(
                                    color: Color(0xFFF2F2F2),
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  color: Color(0xFFF2F2F2),
                                  size: 22,
                                ),
                                onPressed: () {
                                  isEditing.value = true;
                                },
                                tooltip: l10n.myAccountEditNameTooltip,
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Credit Card ────────────────────────────────────────
        const _CreditCard(),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 1: Profile (Preview Tiles)
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileTilesSection extends StatelessWidget {
  const _ProfileTilesSection({required this.profile});
  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _GlassCard(
      child: Column(
        children: [
          _ProfilePreviewTile(
            icon: Icons.person_outline_rounded,
            label: l10n.myAccountAboutYouLabel,
            content: profile?.bio,
            placeholder: l10n.myAccountAboutYouPlaceholder,
            onTap: () => context.push(AppRoutes.profile),
          ),
          _Divider(),
          _ProfilePreviewTile(
            icon: Icons.auto_awesome_outlined,
            label: l10n.myAccountInterestsLabel,
            content: profile?.interests,
            placeholder: l10n.myAccountInterestsPlaceholder,
            onTap: () => context.push(AppRoutes.profile),
          ),
          _Divider(),
          _ProfilePreviewTile(
            icon: Icons.flag_outlined,
            label: l10n.myAccountFutureDreamsLabel,
            content: profile?.futureGoals,
            placeholder: l10n.myAccountFutureDreamsPlaceholder,
            onTap: () => context.push(AppRoutes.profile),
          ),
        ],
      ),
    );
  }
}

class _ProfilePreviewTile extends StatelessWidget {
  const _ProfilePreviewTile({
    required this.icon,
    required this.label,
    this.content,
    required this.placeholder,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String? content;
  final String placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasContent = content != null && content!.trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.white10,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 15, color: AppColors.starGold),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: AppColors.starGold,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      hasContent ? content! : placeholder,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasContent
                            ? const Color(0xFFF2F2F2)
                            : AppColors.universe.textComet,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
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
// Credit Card Widget
// ─────────────────────────────────────────────────────────────────────────────

class _CreditCard extends ConsumerWidget {
  const _CreditCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(creditSummaryProvider);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        ref.invalidate(creditSummaryProvider);
        context.push(AppRoutes.creditDetail);
      },
      child: _GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: summaryAsync.when(
            loading: () => const _CreditCardSkeleton(),
            error: (_, _) => const _CreditCardSkeleton(isError: true),
            data: (summary) => _CreditCardContent(summary: summary),
          ),
        ),
      ),
    );
  }
}

class _CreditCardSkeleton extends StatelessWidget {
  const _CreditCardSkeleton({this.isError = false});
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.starGold.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.bolt_rounded,
            color: AppColors.starGold,
            size: 16,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            isError
                ? l10n.myAccountCreditsUnavailable
                : l10n.myAccountLoadingCredits,
            style: TextStyle(
              color: isError ? Colors.white38 : const Color(0xFFF2F2F2),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _CreditCardContent extends StatelessWidget {
  const _CreditCardContent({required this.summary});
  final CreditSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // プラン未加入(=一度もclaimしていない)場合は「0」と明示的に表示する。
    final balance = summary.hasActivePlan
        ? (summary.creditBalanceDisplay ?? 0)
        : 0;
    final allocation = summary.hasActivePlan
        ? (summary.monthlyAllocationDisplay ?? 0)
        : 0;
    final isDepleted = balance <= 0;

    // 0でもバー自体は完全にはゼロにせず、薄く赤色のスリバーを残しておく
    // (「何も無い」ではなく「使い切った」ことが視覚的に分かるようにするため)。
    final displayFraction = isDepleted ? 0.03 : summary.remainingFraction;
    final barColors = isDepleted
        ? const [Color(0xFFFF5252), Color(0xFFD32F2F)]
        : const [Color(0xFFFFB300), Color(0xFFFF8F00)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.starGold.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: AppColors.starGold,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      l10n.creditDetailTitle,
                      style: const TextStyle(
                        color: Color(0xFFF2F2F2),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '$balance',
                        style: const TextStyle(
                          color: AppColors.starGold,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: ' / $allocation',
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.universe.textComet,
                  size: 18,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
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
                widthFactor: displayFraction,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: barColors),
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(
                        color: barColors.first.withValues(alpha: 0.5),
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
// SECTION 2: Application (Guides, Updates, Transmissions)
// ─────────────────────────────────────────────────────────────────────────────

class _ApplicationSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final unreadAsync = ref.watch(unreadTransmissionsProvider);
    final unreadList = unreadAsync.asData?.value ?? [];
    final hasUnread = unreadList.isNotEmpty;

    return _GlassCard(
      child: Column(
        children: [
          _ActivityTile(
            icon: Icons.satellite_alt_rounded,
            iconColor: AppColors.starGold,
            iconBgColor: const Color(0xFF1E88E5),
            title: l10n.myAccountTransmissionsTitle,
            subtitle: l10n.myAccountTransmissionsSubtitle,
            trailing: hasUnread
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.correctionRed,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      l10n.myAccountNewBadge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : null,
            onTap: () async {
              final allList = await ref.read(appTransmissionsProvider.future);
              if (context.mounted && allList.isNotEmpty) {
                final items = allList
                    .map((t) => SpaceshipAnnouncementItem.fromTransmission(t))
                    .toList();
                await showSpaceshipAnnouncementModal(
                  context,
                  announcements: items,
                );
                if (context.mounted) {
                  await markTransmissionsAsRead(ref, allList);
                }
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.myAccountNoTransmissionsSnackbar),
                  ),
                );
              }
            },
          ),
          _Divider(),
          _ActivityTile(
            icon: Icons.auto_awesome_rounded,
            iconColor: AppColors.starGold,
            iconBgColor: const Color(0xFFFFA000),
            title: l10n.myAccountIntroductionTitle,
            subtitle: l10n.myAccountIntroductionSubtitle,
            onTap: () {
              context.push(AppRoutes.introduction);
            },
          ),
          _Divider(),
          _ActivityTile(
            icon: Icons.rocket_launch_rounded,
            iconColor: AppColors.starGold,
            iconBgColor: const Color(0xFF03A9F4),
            title: l10n.myAccountOnboardingTitle,
            subtitle: l10n.myAccountOnboardingSubtitle,
            onTap: () {
              context.push(AppRoutes.onboarding);
            },
          ),
          _Divider(),
          _ActivityTile(
            icon: Icons.school_rounded,
            iconColor: AppColors.starGold,
            iconBgColor: const Color(0xFF9C27B0),
            title: l10n.myAccountTutorialTitle,
            subtitle: l10n.myAccountTutorialSubtitle,
            onTap: () async {
              final uid = supabase.auth.currentUser?.id;
              if (uid == null) return;
              final db = ref.read(appDatabaseProvider);
              final tut = await db.findTutorialLecture(uid);
              if (tut != null && context.mounted) {
                context.push('${AppRoutes.coursesRootPath}/c/${tut.courseId}/v/${tut.id}');
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.myAccountTutorialComingSoonSnackbar),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 3: Activity (Records)
// ─────────────────────────────────────────────────────────────────────────────

class _ActivitySection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _GlassCard(
      child: Column(
        children: [
          _ActivityTile(
            icon: Icons.bookmark_rounded,
            iconColor: AppColors.starGold,
            iconBgColor: const Color(0xFF4CAF50),
            title: l10n.activityRecordsTitleSaved,
            subtitle: l10n.myAccountSavedSubtitle,
            onTap: () => context.push('/account/activity/saved'),
          ),

          _Divider(),
          _ActivityTile(
            icon: Icons.favorite_rounded,
            iconColor: AppColors.starGold,
            iconBgColor: const Color(0xFFE53935),
            title: l10n.activityRecordsTitleLikes,
            subtitle: l10n.myAccountLikesDislikesSubtitle,
            onTap: () => context.push('/account/activity/likes'),
          ),
          _Divider(),
          _ActivityTile(
            icon: Icons.thumb_down_rounded,
            iconColor: AppColors.starGold,
            iconBgColor: const Color(0xFF2196F3),
            title: l10n.activityRecordsTitleDislikes,
            subtitle: l10n.myAccountLikesDislikesSubtitle,
            onTap: () => context.push('/account/activity/dislikes'),
          ),
          _Divider(),
          _ActivityTile(
            icon: Icons.campaign_rounded,
            iconColor: AppColors.starGold,
            iconBgColor: const Color(0xFF9C27B0),
            title: l10n.activityRecordsTitleAnnouncements,
            subtitle: l10n.myAccountAnnouncementsSubtitle,
            onTap: () => context.push('/account/activity/announcements'),
          ),
          _Divider(),
          _ActivityTile(
            icon: Icons.delete_outline_rounded,
            iconColor: AppColors.correctionRed,
            iconBgColor: AppColors.correctionRed,
            title: l10n.activityRecordsTitleTrash,
            subtitle: l10n.myAccountTrashSubtitle,
            onTap: () => context.push('/account/activity/trash'),
            showChevron: true,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _VersionFooter extends StatelessWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final versionText = snapshot.hasData
            ? 'leFture v${snapshot.data!.version} (${snapshot.data!.buildNumber})'
            : 'leFture';
        return Center(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 48),
            child: Text(
              versionText,
              style: TextStyle(
                color: AppColors.universe.textComet.withValues(alpha: 0.6),
                fontSize: 12,
                letterSpacing: 0.8,
              ),
            ),
          ),
        );
      },
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
    this.trailing,
    this.showChevron = true,
    this.isLast = false,
  });

  final IconData icon;
  final Color iconColor;
  final Color? iconBgColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
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
              if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
              if (showChevron)
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

class _SettingsSection extends ConsumerWidget {
  const _SettingsSection({required this.onSignOut});
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentUserProvider);
    // appMetadata['provider'] はGoTrue側で識別情報(identity)が追加/変更される
    // たびに再計算される「先頭のprovider」でしかなく、複数のidentityを持つ
    // ユーザーでは email 以外の値に化けることがある(順序保証が無いため)。
    // 「emailでのログインが実際に使えるか」はidentity一覧に email が
    // 含まれているかで判定する方が安定する。
    final isEmailUser =
        user?.identities?.any((identity) => identity.provider == 'email') ??
        false;

    return Column(
      children: [
        // Preferences
        _GlassCard(
          child: Builder(
            builder: (context) {
              final recordingCode = ref.watch(
                recordingLanguageControllerProvider,
              );
              final displayCode = ref.watch(displayLanguageControllerProvider);
              final recordingLang = recordingLanguageFromCode(recordingCode);
              final displayLang = displayLanguageFromCode(displayCode);
              return Column(
                children: [
                  _SettingsTile(
                    icon: Icons.record_voice_over_outlined,
                    iconColor: AppColors.universe.textComet,
                    title: l10n.myAccountRecordingLanguageTitle,
                    subtitle: recordingLang.nativeName,
                    onTap: () {
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const LanguageSelectionSheet(
                          mode: LanguageSheetMode.recording,
                        ),
                      );
                    },
                  ),
                  _Divider(),
                  _SettingsTile(
                    icon: Icons.language_rounded,
                    iconColor: AppColors.universe.textComet,
                    title: l10n.myAccountDisplayLanguageTitle,
                    subtitle: displayLang.nativeName,
                    onTap: () {
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const LanguageSelectionSheet(
                          mode: LanguageSheetMode.display,
                        ),
                      );
                    },
                  ),
                  _Divider(),
                  _SettingsTile(
                    icon: Icons.shield_outlined,
                    iconColor: AppColors.universe.textComet,
                    title: l10n.myAccountPermissionsTitle,
                    subtitle: l10n.myAccountPermissionsSubtitle,
                    isLast: true,
                    onTap: () => context.push(AppRoutes.permissionsSettings),
                  ),
                ],
              );
            },
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
                title: l10n.myAccountPrivacyPolicyTitle,
                onTap: () => context.push(AppRoutes.privacyPolicy),
              ),
              _Divider(),
              _SettingsTile(
                icon: Icons.gavel_rounded,
                iconColor: AppColors.universe.textComet,
                title: l10n.myAccountTermsOfServiceTitle,
                onTap: () => context.push(AppRoutes.termsOfService),
              ),
              _Divider(),
              _SettingsTile(
                icon: Icons.mail_outline_rounded,
                iconColor: AppColors.universe.textComet,
                title: l10n.myAccountContactUsTitle,
                onTap: () => context.push(AppRoutes.contact),
                isLast: true,
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Account
        _GlassCard(
          child: Column(
            children: isEmailUser
                ? [
                    _SettingsTile(
                      icon: Icons.email_outlined,
                      iconColor: const Color(0xFF7C83FD),
                      title: l10n.myAccountChangeEmailTitle,
                      onTap: () {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) => const ChangeEmailSheet(),
                        );
                      },
                    ),
                    _Divider(),
                    _SettingsTile(
                      icon: Icons.lock_outline_rounded,
                      iconColor: const Color(0xFF7C83FD),
                      title: l10n.myAccountChangePasswordTitle,
                      onTap: () {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) => const ChangePasswordSheet(),
                        );
                      },
                    ),
                    _Divider(),
                    _SettingsTile(
                      icon: Icons.security_rounded,
                      iconColor: const Color(0xFF7C83FD),
                      title: l10n.myAccountChangeLoginMethodTitle,
                      onTap: () {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) => const ChangeAuthProviderSheet(),
                        );
                      },
                      isLast: true,
                    ),
                  ]
                : [
                    _SettingsTile(
                      icon: Icons.manage_accounts_outlined,
                      iconColor: const Color(0xFF7C83FD),
                      title: l10n.myAccountChangeAccountTitle,
                      onTap: () {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) => const ChangeAccountSheet(),
                        );
                      },
                    ),
                    _Divider(),
                    _SettingsTile(
                      icon: Icons.security_rounded,
                      iconColor: const Color(0xFF7C83FD),
                      title: l10n.myAccountChangeLoginMethodTitle,
                      onTap: () {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) => const ChangeAuthProviderSheet(),
                        );
                      },
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
                title: l10n.myAccountSignOutTitle,
                titleColor: AppColors.correctionRed,
                onTap: onSignOut,
              ),
              _Divider(),
              _SettingsTile(
                icon: Icons.person_remove_outlined,
                iconColor: AppColors.correctionRed,
                title: l10n.myAccountDeleteAccountTitle,
                titleColor: AppColors.correctionRed,
                tileColor: AppColors.correctionRed.withValues(alpha: 0.2),
                onTap: () {
                  showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => const _DeleteAccountDialog(),
                  );
                },
                isLast: true,
              ),
            ],
          ),
        ),

        // Debug section (kept but tucked at the bottom)
        // const SizedBox(height: 12),
        // _DebugSection(),
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
    this.tileColor,
    this.subtitle,
    this.isLast = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final Color? tileColor;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tileColor ?? Colors.transparent,
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
                child: subtitle != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: titleColor ?? const Color(0xFFF2F2F2),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              color: AppColors.universe.textComet,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      )
                    : Text(
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

// ignore: unused_element
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

class _DeleteAccountDialog extends HookConsumerWidget {
  const _DeleteAccountDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final passwordController = useTextEditingController();
    final usernameController = useTextEditingController();
    final obscurePassword = useState(true);
    final isSubmitting = useState(false);
    final errorMessage = useState<String?>(null);
    final statusMessage = useState<String?>(null);

    // ダイアログが開いた瞬間にバックグラウンドでウォームアップ開始。
    final warmupFuture = useMemoized(() => BackendWarmup.waitUntilReady());

    final currentUser = supabase.auth.currentUser;
    final profileAsync = ref.watch(currentUserProfileProvider);
    final currentUsername = profileAsync.asData?.value?.username ?? '';
    // appMetadata['provider'] は複数identityを持つユーザーでは不安定なため、
    // identity一覧に email が含まれるかで判定する(_SettingsSectionと同じ理由)。
    final isEmailUser =
        currentUser?.identities?.any(
          (identity) => identity.provider == 'email',
        ) ??
        false;

    // Verify if submission is allowed
    final isInputValid = isEmailUser
        ? passwordController.text.isNotEmpty
        : currentUsername.isNotEmpty &&
            usernameController.text.trim() == currentUsername;

    // Rebuild dialog when inputs change
    useListenable(passwordController);
    useListenable(usernameController);

    Future<void> handleDelete() async {
      isSubmitting.value = true;
      errorMessage.value = null;

      try {
        statusMessage.value = l10n.deleteAccountDialogWakingBackendStatus;
        final isServerReady = await warmupFuture;
        if (!isServerReady) {
          if (context.mounted) {
            isSubmitting.value = false;
            statusMessage.value = null;
            errorMessage.value = l10n.deleteAccountDialogSlowBackendError;
          }
          return;
        }
        statusMessage.value = l10n.deleteAccountDialogDeletingStatus;

        // deleteAccount は AsyncValue.guard で例外を握りつぶすため throw されない。
        // 戻り値の AsyncValue を見て成否を判定する。
        final result = isEmailUser
            ? await ref
                  .read(authControllerProvider.notifier)
                  .deleteAccount(password: passwordController.text)
            : await ref.read(authControllerProvider.notifier).deleteAccount();

        if (!context.mounted) return;
        isSubmitting.value = false;

        if (result.hasError) {
          errorMessage.value = result.error.toString().replaceAll(
            'Exception: ',
            '',
          );
          return;
        }

        // 削除完了時点でセッションは既に破棄されており、GoRouter が /sign_in へ
        // 自動リダイレクトしている可能性がある(その際ダイアログを含むスタックは
        // 既に破棄済み)。Navigator.pop() を呼ぶとスタックが空の状態でポップされ
        // 例外になるため、pop() はせず go() でスタックごと置き換える。
        context.go(AppRoutes.accountDeleted);
      } finally {
        statusMessage.value = null;
      }
    }

    return AlertDialog(
      backgroundColor: const Color(0xFF13131C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.universe.glassBorder),
      ),
      title: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.correctionRed,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.deleteAccountDialogTitle,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.deleteAccountDialogWarningMessage,
              style: TextStyle(
                color: AppColors.universe.textComet,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            if (errorMessage.value != null) ...[
              AppErrorBox(
                actionName: 'deleting your account',
                rawError: errorMessage.value,
              ),
              const SizedBox(height: 16),
            ],
            if (statusMessage.value != null) ...[
              Text(
                statusMessage.value!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.universe.textComet,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (isEmailUser) ...[
              Text(
                l10n.deleteAccountDialogPasswordPrompt,
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: passwordController,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                obscureText: obscurePassword.value,
                cursorColor: AppColors.starGold,
                decoration: InputDecoration(
                  labelText: l10n.deleteAccountDialogPasswordLabel,
                  labelStyle: TextStyle(color: AppColors.universe.textComet),
                  filled: true,
                  fillColor: AppColors.universe.glassWhiteLow,
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: AppColors.universe.glassBorder,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(
                      color: AppColors.starGold,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword.value
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppColors.universe.textComet,
                    ),
                    onPressed: () =>
                        obscurePassword.value = !obscurePassword.value,
                  ),
                ),
              ),
            ] else ...[
              Text(
                l10n.deleteAccountDialogUsernamePrompt(currentUsername),
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: usernameController,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                cursorColor: AppColors.starGold,
                decoration: InputDecoration(
                  labelText: l10n.deleteAccountDialogUsernameLabel,
                  labelStyle: TextStyle(color: AppColors.universe.textComet),
                  filled: true,
                  fillColor: AppColors.universe.glassWhiteLow,
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: AppColors.universe.glassBorder,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(
                      color: AppColors.starGold,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isSubmitting.value
              ? null
              : () => Navigator.of(context).pop(),
          child: Text(
            l10n.deleteAccountDialogCancelButton,
            style: TextStyle(
              color: AppColors.universe.textComet,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: (isInputValid && !isSubmitting.value)
              ? handleDelete
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.correctionRed,
            foregroundColor: Colors.white,
            elevation: 0,
            disabledBackgroundColor: AppColors.correctionRed.withValues(
              alpha: 0.3,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: isSubmitting.value
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(l10n.deleteAccountDialogConfirmButton),
        ),
      ],
    );
  }
}
