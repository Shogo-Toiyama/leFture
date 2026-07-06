import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lecture_companion_ui/application/course/course_announcement_provider.dart';
import 'package:lecture_companion_ui/domain/entities/announcement.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/announcement_type_icon.dart';

/// コース内の全レクチャーを横断した、未完了のアナウンスメント一覧ボトムシート。
class CourseAnnouncementsSheet extends ConsumerWidget {
  const CourseAnnouncementsSheet({super.key, required this.courseId});

  final String courseId;

  static final _dateFmt = DateFormat('MMM d, yyyy · h:mm a');

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
                      itemBuilder: (context, index) => _AnnouncementTile(
                        announcement: announcements[index],
                        dateFmt: _dateFmt,
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

class _AnnouncementTile extends StatelessWidget {
  const _AnnouncementTile({required this.announcement, required this.dateFmt});

  final Announcement announcement;
  final DateFormat dateFmt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconForAnnouncementType(announcement.type), color: AppColors.starGold, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  announcement.title?.trim().isNotEmpty == true ? announcement.title! : 'Announcement',
                  style: TextStyle(
                    color: AppColors.universe.textStarlight,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (announcement.description?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    announcement.description!.trim(),
                    style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  dateFmt.format(announcement.createdAt.toLocal()),
                  style: TextStyle(color: AppColors.universe.textComet, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
