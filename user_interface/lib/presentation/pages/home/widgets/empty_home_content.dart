import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/application/galaxy/galaxy_data_provider.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/application/lecture/lecture_list_provider.dart';
import 'package:lefture/application/profile/user_profile_provider.dart';
import 'package:lefture/core/utils/connectivity_utils.dart';
import 'package:lefture/domain/entities/course.dart';
import 'package:lefture/presentation/pages/course/widgets/course_create_sheet.dart';
import 'package:lefture/presentation/pages/home/widgets/make_profile_sheet.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/galaxy/galaxy_view.dart';
import 'package:lefture/presentation/widgets/custom_app_bar.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';

// 銀河ウィジェットの高さの、画面縦幅に対する割合。HomePageと同じ比率に揃える。
const double _kGalaxyHeightRatio = 0.25;

/// まだ何もない（コースが無い、もしくはコースはあってもレクチャーが無い）
/// ユーザー向けのホーム画面。
///
/// 「まだ何もない」ではなく「これから育っていく銀河」として最初の一歩を促す。
/// Make Profile → Create Course → Record Lecture の順で、前のステップが
/// 終わるまで次のステップには進めないチェックリスト形式のオンボーディングになっている。
class EmptyHomeContent extends ConsumerWidget {
  const EmptyHomeContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(currentUserProfileProvider).asData?.value;
    final displayName = profile?.username?.trim();
    final greetingName = (displayName != null && displayName.isNotEmpty) ? displayName : l10n.emptyHomeDefaultName;

    final profileComplete = (profile?.bio?.trim().isNotEmpty ?? false);
    final courses = ref.watch(courseListProvider).asData?.value ?? const [];
    final hasCourse = courses.isNotEmpty;
    final lectures = ref.watch(allLecturesStreamProvider).asData?.value ?? const [];
    final hasLecture = lectures.isNotEmpty;

    final screenHeight = MediaQuery.of(context).size.height;
    final galaxyHeight = screenHeight * _kGalaxyHeightRatio;

    Future<void> handleRefresh() async {
      if (!await isDeviceOnline()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.homeOfflineSnackBarMessage)),
          );
        }
        return;
      }

      await ref.read(lectureControllerProvider.notifier).bootstrapLectures();
      ref.invalidate(courseListProvider);
      ref.invalidate(currentUserProfileProvider);
    }

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: SafeArea(
        child: Column(
          children: [
            const CustomAppBar(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return RefreshIndicator(
                    color: AppColors.starGold,
                    onRefresh: handleRefresh,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                l10n.emptyHomeWelcomeGreeting(greetingName),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.universe.textStarlight,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  height: 1.3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.emptyHomeStartBuilding,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.starGold,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                              ),
                            ),
                            SizedBox(height: galaxyHeight * 0.15),
                            // 銀河: HomePageと同じく画面横幅いっぱい + 縦幅比 + 上下グラデーションフェード
                            SizedBox(
                              width: double.infinity,
                              height: galaxyHeight,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: GalaxyView(
                                      // 回転が視覚的にわかるように、わずかにディスクの星と星雲を配置する
                                      config: defaultGalaxyConfig.copyWith(
                                        diskStarCount: 0,
                                        nebulaCount: 0,
                                      ),
                                      glowScale: 0.45,
                                    ),
                                  ),
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    height: 15,
                                    child: IgnorePointer(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              AppColors.universe.voidBackground,
                                              AppColors.universe.voidBackground.withValues(alpha: 0.0),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    height: 15,
                                    child: IgnorePointer(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.bottomCenter,
                                            end: Alignment.topCenter,
                                            colors: [
                                              AppColors.universe.voidBackground,
                                              AppColors.universe.voidBackground.withValues(alpha: 0.0),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: galaxyHeight * 0.15),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                l10n.emptyHomeGalaxyDescription,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.universe.textComet,
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),

                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Column(
                                children: [
                                  _OnboardingStepTile(
                                    stepNumber: 1,
                                    title: l10n.emptyHomeStepMakeProfileTitle,
                                    subtitle: profileComplete
                                        ? l10n.emptyHomeStepMakeProfileDoneSubtitle
                                        : l10n.emptyHomeStepMakeProfilePendingSubtitle,
                                    icon: Icons.person_outline,
                                    isDone: profileComplete,
                                    isEnabled: true,
                                    onTap: () => _openMakeProfileSheet(context),
                                  ),
                                  const SizedBox(height: 12),
                                  _OnboardingStepTile(
                                    stepNumber: 2,
                                    title: l10n.emptyHomeStepCreateCourseTitle,
                                    subtitle: !profileComplete
                                        ? l10n.emptyHomeStepCreateCourseDisabledSubtitle
                                        : hasCourse
                                            ? l10n.emptyHomeStepCreateCourseDoneSubtitle
                                            : l10n.emptyHomeStepCreateCoursePendingSubtitle,
                                    icon: Icons.school_outlined,
                                    isDone: hasCourse,
                                    isEnabled: profileComplete,
                                    onTap: () => _openCreateCourseSheet(context, ref),
                                  ),
                                  const SizedBox(height: 12),
                                  _OnboardingStepTile(
                                    stepNumber: 3,
                                    title: l10n.emptyHomeStepRecordLectureTitle,
                                    subtitle: !hasCourse
                                        ? l10n.emptyHomeStepRecordLectureDisabledSubtitle
                                        : hasLecture
                                            ? l10n.emptyHomeStepRecordLectureDoneSubtitle
                                            : l10n.emptyHomeStepRecordLecturePendingSubtitle,
                                    icon: Icons.mic_none,
                                    isDone: hasLecture,
                                    isEnabled: hasCourse,
                                    onTap: () => context.push(AppRoutes.recording),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMakeProfileSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const MakeProfileSheet(),
    );
  }

  Future<void> _openCreateCourseSheet(BuildContext context, WidgetRef ref) async {
    final profileComplete = (ref.read(currentUserProfileProvider).asData?.value?.bio
            ?.trim()
            .isNotEmpty ??
        false);
    if (!profileComplete) return;

    await showModalBottomSheet<Course>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CourseCreateSheet(),
    );
  }
}

/// チェックリスト形式のオンボーディング1ステップ分の行。
/// 前のステップが未完了の場合は isEnabled=false でグレーアウトし、タップを無視する。
class _OnboardingStepTile extends StatelessWidget {
  const _OnboardingStepTile({
    required this.stepNumber,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isDone,
    required this.isEnabled,
    required this.onTap,
  });

  final int stepNumber;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isDone;
  final bool isEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dimmed = !isEnabled;

    return Opacity(
      opacity: dimmed ? 0.45 : 1.0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isEnabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.universe.glassWhiteLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDone ? AppColors.starGold.withValues(alpha: 0.6) : AppColors.universe.glassBorder,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone ? AppColors.starGold : AppColors.universe.glassWhiteHigh,
                ),
                child: Icon(
                  isDone ? Icons.check : icon,
                  color: isDone ? Colors.white : AppColors.universe.textStarlight,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppColors.universe.textStarlight,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: AppColors.universe.textComet, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (!isEnabled)
                Icon(Icons.lock_outline, color: AppColors.universe.textComet, size: 18)
              else
                Icon(Icons.chevron_right, color: AppColors.universe.textComet, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
