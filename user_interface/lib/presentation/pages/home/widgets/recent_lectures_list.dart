import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_list_provider.dart';

import 'package:lecture_companion_ui/presentation/widgets/lecture_tile.dart';

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
          child: LectureTile(
            lecture: lecture,
            courseCode: courseCode,
            useRelativeTime: true,
            showChevron: true,
            onEdit: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Mock Edit Lecture: ${lecture.title ?? lecture.titleGenerated}')),
              );
            },
            onDelete: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Mock Delete Lecture: ${lecture.title ?? lecture.titleGenerated}')),
              );
            },
          ),
        );
      }, childCount: recent.length),
    );
  }
}
