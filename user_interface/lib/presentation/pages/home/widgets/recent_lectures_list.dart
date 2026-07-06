import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_list_provider.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class RecentLecturesList extends ConsumerWidget {
  const RecentLecturesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lectures =
        ref.watch(allLecturesStreamProvider).asData?.value ?? const [];
    final courses = ref.watch(courseListProvider).asData?.value ?? const [];
    final courseCodeMap = {for (final c in courses) c.id: c.courseCode};
    final recent = lectures.take(10).toList();

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final lecture = recent[index];
        final courseCode = courseCodeMap[lecture.courseId];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: _LectureCard(lecture: lecture, courseCode: courseCode),
        );
      }, childCount: recent.length),
    );
  }
}

class _LectureCard extends StatelessWidget {
  final Lecture lecture;
  final String? courseCode;
  const _LectureCard({required this.lecture, this.courseCode});

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
      onTap: () => context.push('${AppRoutes.notesRoot}/v/${lecture.id}'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.universe.glassWhiteLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.universe.glassBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.universe.glassWhiteHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.description_outlined,
                color: AppColors.starGold,
                size: 24,
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
                        _relativeTime(lecture.lectureDatetime),
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
          ],
        ),
      ),
    );
  }
}

/// 「2 hours ago」のような相対時間表記。専用パッケージを入れるほどでもないので自前実装。
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
