import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/course/course_announcement_provider.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/announcement_tile.dart';

/// コース内の全レクチャーを横断した、未完了のアナウンスメント一覧ボトムシート。
class CourseAnnouncementsSheet extends ConsumerWidget {
  const CourseAnnouncementsSheet({super.key, required this.courseId});

  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcementsAsync = ref.watch(activeAnnouncementsForCourseProvider(courseId));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1C2E),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: AppColors.universe.glassBorder)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.universe.glassBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Row(
                  children: [
                    Text(
                      'Announcements',
                      style: TextStyle(
                        color: AppColors.universe.textStarlight,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: announcementsAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.starGold),
                  ),
                  error: (e, _) => Center(
                    child: Text('Error: $e', style: const TextStyle(color: AppColors.correctionRed)),
                  ),
                  data: (announcements) {
                    if (announcements.isEmpty) {
                      return Center(
                        child: Text(
                          'No announcements yet',
                          style: TextStyle(color: AppColors.universe.textComet),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      itemCount: announcements.length,
                      separatorBuilder: (context, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => AnnouncementTile(
                        announcement: announcements[index],
                        showTimestamp: true,
                        onToggleComplete: (a) => ref
                            .read(activeAnnouncementsForCourseProvider(courseId).notifier)
                            .toggleComplete(a),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
