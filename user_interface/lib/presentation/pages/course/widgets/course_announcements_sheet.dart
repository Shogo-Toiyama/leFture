import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/course/course_announcement_provider.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/domain/entities/announcement.dart';
import 'package:lefture/infrastructure/local_db/repositories/announcement_repository_drift.dart';
import 'package:lefture/presentation/pages/course/widgets/announcement_edit_sheet.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/announcement_tile.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';

/// コース内の全レクチャーを横断した、未完了のアナウンスメント一覧ボトムシート。
class CourseAnnouncementsSheet extends ConsumerWidget {
  const CourseAnnouncementsSheet({super.key, required this.courseId});

  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
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
                    Expanded(
                      child: Text(
                        l10n.lectureViewerAnnouncementsSheetTitle,
                        style: TextStyle(
                          color: AppColors.universe.textStarlight,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
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
                    child: Text(l10n.courseAnnouncementsSheetLoadError(e.toString()), style: const TextStyle(color: AppColors.correctionRed)),
                  ),
                  data: (announcements) {
                    if (announcements.isEmpty) {
                      return Center(
                        child: Text(
                          l10n.courseNoAnnouncementsLabel,
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
                        return AnnouncementTile(
                          key: ValueKey(announcement.id),
                          announcement: announcement,
                          showTimestamp: true,
                          onToggleComplete: (a) async {
                            await ref
                                .read(announcementRepositoryDriftProvider)
                                .toggleComplete(id: a.id, completed: !a.isCompleted);
                            ref.read(lectureControllerProvider.notifier).pushOutboxNow();
                          },
                          onEdit: () async {
                            await showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => AnnouncementEditSheet(announcement: announcement),
                            );
                          },
                          onDelete: (Announcement a) async {
                            await ref
                                .read(announcementRepositoryDriftProvider)
                                .softDeleteAnnouncement(id: a.id);
                            ref.read(lectureControllerProvider.notifier).pushOutboxNow();
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
