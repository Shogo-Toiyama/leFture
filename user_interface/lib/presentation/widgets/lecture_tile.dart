import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

import 'package:lecture_companion_ui/presentation/widgets/custom_dialog.dart';
import 'package:lecture_companion_ui/presentation/widgets/tile_actions_sheet.dart';

class LectureTile extends StatelessWidget {
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

  static final _dateFmt = DateFormat('MMM d, yyyy');

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
  Widget build(BuildContext context) {
    final titleText = lecture.title?.trim().isNotEmpty == true
        ? lecture.title!
        : (lecture.titleGenerated?.trim().isNotEmpty == true
              ? lecture.titleGenerated!
              : 'Untitled Lecture');

    final code = courseCode?.trim();
    final hasCourseCode = code != null && code.isNotEmpty;

    return GestureDetector(
      onTap: () => context.go('${AppRoutes.notesRootPath}/c/${lecture.courseId}/v/${lecture.id}'),
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
                    message: 'Are you sure you want to delete "$titleText"? This action will remove the lecture and all its generated notes/flashcards permanently.',
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
          border: Border.all(color: AppColors.universe.glassBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.universe.glassWhiteHigh,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.description_outlined,
                color: AppColors.starGold,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleText,
                    style: TextStyle(
                      color: AppColors.universe.textStarlight,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                            : _dateFmt.format(lecture.lectureDatetime.toLocal()),
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
                            color: AppColors.universe.textComet,
                            fontSize: 12,
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
