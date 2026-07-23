import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_providers.dart';
import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/application/profile/user_profile_provider.dart';
import 'package:lecture_companion_ui/application/credit/credit_providers.dart';
import 'package:lecture_companion_ui/presentation/widgets/user_avatar.dart';
import 'recording_timer_chip.dart';

class CustomAppBar extends ConsumerWidget {
  const CustomAppBar({
    super.key,
    this.showHomeButton = false,
    this.title,
    this.isLightBg = false,
    this.actions,
  });

  final bool showHomeButton;
  final String? title;
  final bool isLightBg;
  final List<Widget>? actions;

  Future<void> _showNavigationStack(BuildContext context, WidgetRef ref) async {
    final state = GoRouterState.of(context);
    final courseId = state.pathParameters['courseId'];
    final lectureId = state.pathParameters['lectureId'];
    final path = state.uri.path;

    // Resolve course title
    String? courseTitle;
    if (courseId != null) {
      final courses = ref.read(courseListProvider).value;
      final course = courses?.cast<Course?>().firstWhere(
            (c) => c?.id == courseId,
            orElse: () => null,
          );
      courseTitle = course?.courseTitle ?? 'Course Detail';
    }

    // Resolve lecture title
    String? lectureTitle;
    if (lectureId != null) {
      final lectureVal = ref.read(lectureProvider(lectureId)).value;
      lectureTitle = lectureVal?.title?.trim().isNotEmpty == true
          ? lectureVal!.title!
          : (lectureVal?.titleGenerated?.trim().isNotEmpty == true
              ? lectureVal!.titleGenerated!
              : 'Lecture');
    }

    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    
    // Position popup menu near the home button
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final items = <PopupMenuEntry<String>>[
      // 1. Home (always present)
      PopupMenuItem<String>(
        value: 'home',
        child: Row(
          children: [
            Icon(Icons.dashboard, color: isLightBg ? AppColors.paper.textInk : AppColors.starGold, size: 18),
            const SizedBox(width: 10),
            const Text('Dashboard (Home)', style: TextStyle(fontSize: 13.5)),
            if (path == '/home') ...[
              const Spacer(),
              Icon(Icons.check, color: isLightBg ? AppColors.paper.textInk : AppColors.starGold, size: 16),
            ]
          ],
        ),
      ),

      // 2. Courses List
      PopupMenuItem<String>(
        value: 'courses',
        child: Row(
          children: [
            Icon(Icons.library_books, color: isLightBg ? AppColors.paper.textInk : AppColors.starGold, size: 18),
            const SizedBox(width: 10),
            const Text('Courses', style: TextStyle(fontSize: 13.5)),
            if (path == AppRoutes.coursesRootPath) ...[
              const Spacer(),
              Icon(Icons.check, color: isLightBg ? AppColors.paper.textInk : AppColors.starGold, size: 16),
            ]
          ],
        ),
      ),
      
      // 3. Course Detail
      if (courseId != null) ...[
        PopupMenuItem<String>(
          value: 'course',
          child: Row(
            children: [
              Icon(Icons.menu_book, color: isLightBg ? AppColors.paper.textInk : AppColors.starGold, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Course: $courseTitle',
                  style: const TextStyle(fontSize: 13.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (path == '${AppRoutes.coursesRootPath}/c/$courseId') ...[
                const SizedBox(width: 8),
                Icon(Icons.check, color: isLightBg ? AppColors.paper.textInk : AppColors.starGold, size: 16),
              ]
            ],
          ),
        ),
      ],

      // 4. Lecture Detail
      if (lectureId != null) ...[
        PopupMenuItem<String>(
          value: 'lecture',
          child: Row(
            children: [
              Icon(Icons.play_circle_outline, color: isLightBg ? AppColors.paper.textInk : AppColors.starGold, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Lecture: $lectureTitle',
                  style: const TextStyle(fontSize: 13.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (path == '${AppRoutes.coursesRootPath}/c/$courseId/v/$lectureId') ...[
                const SizedBox(width: 8),
                Icon(Icons.check, color: isLightBg ? AppColors.paper.textInk : AppColors.starGold, size: 16),
              ]
            ],
          ),
        ),
      ],

      // 5. Feature Subpage (Topic Map, Deep Notes, Review Cards, Transcript)
      if (path.contains('/rcv/')) ...[
        PopupMenuItem<String>(
          value: 'current',
          enabled: false,
          child: Row(
            children: [
              Icon(Icons.style, color: isLightBg ? AppColors.paper.textInk.withValues(alpha: 0.5) : AppColors.universe.textComet, size: 18),
              const SizedBox(width: 10),
              const Text('Review Cards (Current)', style: TextStyle(fontSize: 13.5, fontStyle: FontStyle.italic)),
              const Spacer(),
              Icon(Icons.check, color: isLightBg ? AppColors.paper.textInk : AppColors.starGold, size: 16),
            ],
          ),
        ),
      ] else if (path.contains('/dnd/')) ...[
        PopupMenuItem<String>(
          value: 'current',
          enabled: false,
          child: Row(
            children: [
              Icon(Icons.description, color: isLightBg ? AppColors.paper.textInk.withValues(alpha: 0.5) : AppColors.universe.textComet, size: 18),
              const SizedBox(width: 10),
              const Text('Deep Notes (Current)', style: TextStyle(fontSize: 13.5, fontStyle: FontStyle.italic)),
              const Spacer(),
              Icon(Icons.check, color: isLightBg ? AppColors.paper.textInk : AppColors.starGold, size: 16),
            ],
          ),
        ),
      ] else if (path.contains('/transcript/')) ...[
        PopupMenuItem<String>(
          value: 'current',
          enabled: false,
          child: Row(
            children: [
              Icon(Icons.subtitles, color: isLightBg ? AppColors.paper.textInk.withValues(alpha: 0.5) : AppColors.universe.textComet, size: 18),
              const SizedBox(width: 10),
              const Text('Transcript (Current)', style: TextStyle(fontSize: 13.5, fontStyle: FontStyle.italic)),
              const Spacer(),
              Icon(Icons.check, color: isLightBg ? AppColors.paper.textInk : AppColors.starGold, size: 16),
            ],
          ),
        ),
      ] else if (path.contains('/topic-map')) ...[
        PopupMenuItem<String>(
          value: 'current',
          enabled: false,
          child: Row(
            children: [
              Icon(Icons.map, color: isLightBg ? AppColors.paper.textInk.withValues(alpha: 0.5) : AppColors.universe.textComet, size: 18),
              const SizedBox(width: 10),
              const Text('Topic Map (Current)', style: TextStyle(fontSize: 13.5, fontStyle: FontStyle.italic)),
              const Spacer(),
              Icon(Icons.check, color: isLightBg ? AppColors.paper.textInk : AppColors.starGold, size: 16),
            ],
          ),
        ),
      ]
    ];

    if (items.length <= 1) {
      context.go(AppRoutes.home);
      return;
    }

    final String? result = await showMenu<String>(
      context: context,
      position: position,
      items: items,
      color: isLightBg ? const Color(0xFFF9F9FB) : const Color(0xFF1E213A),
      elevation: 8,
    );

    if (!context.mounted) return;

    if (result == 'home') {
      context.go(AppRoutes.home);
    } else if (result == 'courses') {
      context.go(AppRoutes.coursesRootPath);
    } else if (result == 'course' && courseId != null) {
      context.go('${AppRoutes.coursesRootPath}/c/$courseId');
    } else if (result == 'lecture' && courseId != null && lectureId != null) {
      context.go('${AppRoutes.coursesRootPath}/c/$courseId/v/$lectureId');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textColor = isLightBg ? AppColors.paper.textInk : AppColors.universe.textStarlight;
    final iconColor = isLightBg ? AppColors.paper.textInk : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 左側と右側の要素
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 左: ホームボタン + 録音チップ (リアルタイムで同期)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showHomeButton) ...[
                    GestureDetector(
                      onTap: () => context.go(AppRoutes.home),
                      onLongPress: () => _showNavigationStack(context, ref),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Icon(Icons.home, color: iconColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  const RecordingTimerChip(),
                ],
              ),

              // 右: プロフィール & クレジット残量 (および追加アクションボタン)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (actions != null) ...[
                    ...actions!,
                    const SizedBox(width: 8),
                  ],
                  Consumer(
                    builder: (context, ref, child) {
                      final profile = ref.watch(currentUserProfileProvider).asData?.value;
                      final summary = ref.watch(creditSummaryProvider).asData?.value;
                      // ロード中/未取得/プラン未加入(hasActivePlan=false)は薄い赤の
                      // ミニマムスリバーだけ見せる(0を「何も無い」ではなく
                      // 「使い切った/未加入」として視覚的に区別するため)。
                      final isDepleted = summary == null || !summary.hasActivePlan || (summary.creditBalanceDisplay ?? 0) <= 0;
                      final gaugeValue = isDepleted ? 0.03 : summary.remainingFraction;
                      final gaugeColor = isDepleted
                          ? const Color(0xFFD32F2F)
                          : (isLightBg ? AppColors.deepGold : AppColors.starGold);
                      return GestureDetector(
                        onTap: () => context.push(AppRoutes.account),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // クレジット残量ゲージ
                            SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                value: gaugeValue,
                                strokeWidth: 2.5,
                                backgroundColor: isLightBg
                                    ? AppColors.paper.textInk.withValues(alpha: 0.1)
                                    : AppColors.universe.glassWhiteLow,
                                valueColor: AlwaysStoppedAnimation<Color>(gaugeColor),
                              ),
                            ),
                            // User Avatar
                            UserAvatar(
                              profile: profile,
                              size: 25,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              )
            ],
          ),

          // 中央タイトル (もし指定されている場合)
          if (title != null)
            IgnorePointer(
              child: Center(
                child: Text(
                  title!,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
