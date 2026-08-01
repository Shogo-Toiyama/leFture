import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/application/lecture/lecture_providers.dart';
import 'package:lefture/application/lecture/lecture_state_providers.dart';
import 'package:lefture/application/recording/recording_controller.dart';
import 'package:lefture/application/recording/recording_state.dart';
import 'package:lefture/domain/entities/course.dart';
import 'package:lefture/domain/entities/lecture.dart';
import 'package:lefture/presentation/pages/course/widgets/course_style_helper.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';

import 'package:lefture/presentation/widgets/custom_dialog.dart';
import 'package:lefture/presentation/widgets/tile_actions_sheet.dart';

class LectureTile extends ConsumerWidget {
  const LectureTile({
    super.key,
    required this.lecture,
    this.courseCode,
    this.useRelativeTime = false,
    this.showChevron = true,
    this.onEdit,
    this.onDelete,
  });

  final Lecture lecture;
  final String? courseCode;
  final bool useRelativeTime;
  final bool showChevron;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  String _relativeTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min${diff.inMinutes == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return '$weeks week${weeks == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 365) {
      final months = (diff.inDays / 30).floor();
      return '$months month${months == 1 ? '' : 's'} ago';
    }
    final years = (diff.inDays / 365).floor();
    return '$years year${years == 1 ? '' : 's'} ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
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

    final imagePath = ref.watch(firstTopicImagePathProvider(lecture.id)).asData?.value;
    final imageFile = imagePath == null ? null : ref.watch(artifactFileProvider(imagePath)).asData?.value;
    final uiState = ref.watch(lectureStateProvider(lecture.id)).asData?.value;

    final recordingState = ref.watch(recordingControllerProvider);
    final isActivelyRecording = recordingState.lectureId == lecture.id &&
        (recordingState.phase == RecordingPhase.recording ||
            recordingState.phase == RecordingPhase.paused ||
            recordingState.phase == RecordingPhase.requestingPermission ||
            recordingState.phase == RecordingPhase.uploading);

    final titleText = lecture.title?.trim().isNotEmpty == true
        ? lecture.title!
        : (lecture.titleGenerated?.trim().isNotEmpty == true
              ? lecture.titleGenerated!
              : l10n.lectureViewerUntitledLecture);

    final code = courseCode?.trim();
    final hasCourseCode = code != null && code.isNotEmpty;

    return GestureDetector(
      onTap: () => isActivelyRecording
          ? context.push(AppRoutes.recording)
          : context.go('${AppRoutes.coursesRootPath}/c/${lecture.courseId}/v/${lecture.id}'),
      onLongPress: (onEdit != null || onDelete != null)
          ? () => showTileActionsSheet(
                context: context,
                title: titleText,
                onEdit: () {
                  if (onEdit != null) onEdit!();
                },
                onDelete: () async {
                  final confirm = await showCustomDialog(
                    context: context,
                    title: 'Delete Lecture?',
                    message: 'Are you sure you want to delete "$titleText"? This action will remove the lecture and all its generated contents.',
                    confirmLabel: 'Delete',
                    icon: Icons.delete_outline,
                    isDestructive: true,
                  );
                  if (confirm == true && onDelete != null) {
                    onDelete!();
                  }
                },
              )
          : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.universe.glassWhiteLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: themeColor.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: themeColor.withValues(alpha: 0.3),
                ),
                image: imageFile != null
                    ? DecorationImage(image: FileImage(imageFile), fit: BoxFit.cover)
                    : null,
              ),
              child: imageFile == null
                  ? Icon(
                      Icons.description_outlined,
                      color: themeColor,
                      size: 22,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          titleText,
                          style: TextStyle(
                            color: AppColors.universe.textStarlight,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isActivelyRecording) ...[
                        const SizedBox(width: 6),
                        const _RecordingBadge(),
                      ] else if (uiState == LectureUIState.processing ||
                          uiState == LectureUIState.failed) ...[
                        const SizedBox(width: 6),
                        _StatusBadge(state: uiState!),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 12,
                        color: AppColors.universe.textComet,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        useRelativeTime
                            ? _relativeTime(lecture.lectureDatetime)
                            : DateFormat.yMMMd(l10n.localeName).format(lecture.lectureDatetime.toLocal()),
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 12,
                        ),
                      ),
                      if (hasCourseCode) ...[
                        const Spacer(),
                        Text(
                          code,
                          style: TextStyle(
                            color: themeColor.withValues(alpha: 0.6),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (showChevron) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: AppColors.universe.textComet,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecordingBadge extends StatelessWidget {
  const _RecordingBadge();

  @override
  Widget build(BuildContext context) {
    const color = AppColors.correctionRed;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          const Text(
            'Recording',
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state});

  final LectureUIState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isFailed = state == LectureUIState.failed;
    final color = isFailed ? AppColors.correctionRed : AppColors.starGold;
    final label = isFailed ? l10n.statusViewFailedLabel : l10n.statusViewProcessingLabel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isFailed) ...[
            SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            ),
            const SizedBox(width: 4),
          ] else ...[
            Icon(Icons.error_outline, size: 10, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
