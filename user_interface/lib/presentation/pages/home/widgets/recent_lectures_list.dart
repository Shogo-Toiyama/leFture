import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/application/lecture/lecture_list_provider.dart';
import 'package:lefture/application/profile/user_profile_provider.dart';
import 'package:lefture/presentation/widgets/lecture_tile.dart';
import 'package:lefture/presentation/pages/course/widgets/lecture_edit_sheet.dart';
import 'package:lefture/presentation/pages/home/widgets/tutorial_lecture_callout.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';

import 'package:lefture/application/recording/recording_controller.dart';
import 'package:lefture/presentation/widgets/custom_dialog.dart';

class RecentLecturesList extends ConsumerWidget {
  const RecentLecturesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lectures =
        ref.watch(allLecturesStreamProvider).asData?.value ?? const [];
    final courses = ref.watch(courseListProvider).asData?.value ?? const [];
    final userProfile = ref.watch(currentUserProfileProvider).asData?.value;
    final isTutorialCompleted =
        userProfile?.metadata?['tutorial_completed_at'] != null;
    final courseCodeMap = {for (final c in courses) c.id: c.courseCode};
    final recent = lectures.take(10).toList();

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final lecture = recent[index];
        final courseCode = courseCodeMap[lecture.courseId];

        // チュートリアル未完了のチュートリアル講義だけ、軽い誘導装飾を付ける。
        final isUncompletedTutorial =
            lecture.metadata?['is_tutorial'] == true && !isTutorialCompleted;

        final tile = LectureTile(
          lecture: lecture,
          courseCode: courseCode,
          useRelativeTime: true,
          showChevron: true,
          onEdit: () async {
            await showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => LectureEditSheet(lecture: lecture),
            );
          },
          onDelete: () async {
            final recordingState = ref.read(recordingControllerProvider);
            if (recordingState.isRecording &&
                recordingState.currentLectureId == lecture.id) {
              await showDialog<void>(
                context: context,
                builder: (context) => const CustomDialog(
                  title: '録音中の講義は削除できません',
                  message:
                      'この講義は現在録音中です。削除する場合は、録音画面から録音を保存または破棄してください。',
                  confirmLabel: 'OK',
                  cancelLabel: null,
                  icon: Icons.mic_off_rounded,
                  iconColor: Colors.amber,
                ),
              );
              return;
            }

            await ref
                .read(lectureControllerProvider.notifier)
                .deleteLecture(lecture.id, courseId: lecture.courseId);
          },
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: isUncompletedTutorial ? TutorialLectureCallout(child: tile) : tile,
        );
      }, childCount: recent.length),
    );
  }
}
