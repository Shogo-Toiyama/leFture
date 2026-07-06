import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/application/announcement/announcement_provider.dart';
import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_list_provider.dart';
import 'package:lecture_companion_ui/domain/entities/announcement.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/announcement_type_icon.dart';

/// 全コース横断の未完了アナウンスメント一覧シート (HomeのAnnouncementBarから開く)。
/// 各アナウンスをタップすると、そのアナウンスが属するコースのページへ遷移する。
class AllAnnouncementsSheet extends ConsumerWidget {
  const AllAnnouncementsSheet({super.key});

  static final _dateFmt = DateFormat('MMM d, yyyy · h:mm a');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcementsAsync = ref.watch(activeAnnouncementsProvider);

    // アナウンス→コースへ辿るための対応表 (announcementsはlecture_id経由の紐付けのみ)
    final lectures = ref.watch(allLecturesStreamProvider).asData?.value ?? const [];
    final courseIdByLectureId = {for (final l in lectures) l.id: l.courseId};
    final courses = ref.watch(courseListProvider).asData?.value ?? const [];
    final courseTitleById = {for (final c in courses) c.id: c.displayTitle};

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
                          'No announcements — you\'re all caught up!',
                          style: TextStyle(color: AppColors.universe.textComet),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      itemCount: announcements.length,
                      separatorBuilder: (context, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final announcement = announcements[index];
                        final courseId = announcement.lectureId == null
                            ? null
                            : courseIdByLectureId[announcement.lectureId];
                        return _AnnouncementTile(
                          announcement: announcement,
                          courseName: courseId == null ? null : courseTitleById[courseId],
                          onTap: courseId == null
                              ? null
                              : () {
                                  Navigator.of(context).pop(); // シートを閉じてから遷移
                                  context.push('${AppRoutes.notesRoot}/c/$courseId');
                                },
                        );
                      },
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
  const _AnnouncementTile({
    required this.announcement,
    required this.courseName,
    required this.onTap,
  });

  final Announcement announcement;
  final String? courseName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
                    announcement.title?.trim().isNotEmpty == true
                        ? announcement.title!.trim()
                        : 'Announcement',
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
                    [
                      if (courseName != null) courseName!,
                      AllAnnouncementsSheet._dateFmt.format(announcement.createdAt.toLocal()),
                    ].join(' · '),
                    style: TextStyle(color: AppColors.universe.textComet, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, color: AppColors.universe.textComet, size: 18),
          ],
        ),
      ),
    );
  }
}
