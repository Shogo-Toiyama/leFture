import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_providers.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_state_providers.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart'; // Controller
import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/presentation/pages/course/widgets/course_style_helper.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_dialog.dart';

import 'views/processing_view.dart';
import 'views/not_started_view.dart';
import 'views/status_view.dart';

class LectureStatusScaffold extends ConsumerWidget {
  const LectureStatusScaffold({super.key, required this.lecture});

  final Lecture lecture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStateAsync = ref.watch(lectureStateProvider(lecture.id));
    final controllerState = ref.watch(lectureControllerProvider);
    final isActionLoading = controllerState.isLoading;

    final displayTitle = lecture.title?.trim().isNotEmpty == true
        ? lecture.title!
        : (lecture.titleGenerated?.trim().isNotEmpty == true
            ? lecture.titleGenerated!
            : 'Untitled Lecture');

    final coursesAsync = ref.watch(courseListProvider);
    final courses = coursesAsync.asData?.value;
    Course? parentCourse;
    if (courses != null && lecture.courseId != null) {
      for (final c in courses) {
        if (c.id == lecture.courseId) {
          parentCourse = c;
          break;
        }
      }
    }
    final themeColor = parentCourse != null
        ? CourseStyleHelper.hexToColor(parentCourse.color, fallback: AppColors.starGold)
        : AppColors.starGold;

    ref.listen<AsyncValue<LectureUIState>>(
      lectureStateProvider(lecture.id),
      (previous, next) {
        next.whenData((state){
          if (state == LectureUIState.complete) {
            final uid = supabase.auth.currentUser?.id;
            if (uid != null) {
              ref.invalidate(transcriptProvider(uid: uid, lectureId: lecture.id));
            }
            // Trigger sync immediately to fetch newly generated title and summary
            ref.read(lectureControllerProvider.notifier).bootstrapLectures();
          }
        });
      }
    );

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              themeColor.withValues(alpha: 0.3),
              themeColor.withValues(alpha: 0.08),
              Colors.transparent,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: uiStateAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.starGold)),
          error: (err, stack) => Center(child: Text('Error: $err')),
          data: (uiState) {
            switch (uiState) {
              case LectureUIState.loading:
              case LectureUIState.complete:
                return const SizedBox.shrink();

              case LectureUIState.processing:
              case LectureUIState.failed:
                // 分析中/失敗どちらもProcessingView側でjob.statusを見て
                // 見た目(ヘッダー色・Start Overの出し方)を切り替える。
                // ステップ単位の内訳・詳細エラー・粒度の細かいリトライも
                // ここで一貫して表示できるため、専用のStatusViewは使わない。
                return ProcessingView(lectureId: lecture.id);

              case LectureUIState.notStarted:
                return NotStartedView(lecture: lecture);

              case LectureUIState.syncing:
                return const StatusView(
                  icon: Icons.cloud_upload_outlined,
                  title: 'Syncing Audio...',
                  message: 'Please wait for the upload to complete.',
                );

              case LectureUIState.noAudio:
                return StatusView(
                  icon: Icons.no_photography_outlined,
                  title: 'No Audio Found',
                  isError: true,
                  isLoading: isActionLoading, // 削除中もクルクル
                  buttonIcon: Icons.delete,
                  buttonLabel: 'Delete Lecture',
                  onButtonPressed: () async {
                    final ok = await showCustomDialog(
                      context: context,
                      title: 'Delete folder',
                      message: 'Are you sure you want to delete "$displayTitle"?',
                      confirmLabel: 'Delete',
                      icon: Icons.delete_outline,
                      isDestructive: true,
                    );
                    if (ok == true) {
                      await ref
                          .read(lectureControllerProvider.notifier)
                          .deleteLecture(lecture.id, courseId: lecture.courseId);
                      if (context.mounted) context.pop();
                    }
                  },
                );
            }
          },
        ),
      ),
    );
  }
}