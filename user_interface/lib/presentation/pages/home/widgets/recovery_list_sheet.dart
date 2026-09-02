// lib/presentation/pages/home/widgets/recovery_list_sheet.dart
//
// 孤児録音が複数件あるとき、RecoveryBannerから開くボトムシート。
// バナー自体は1件しか代表表示できないため、それ以外の孤児は「自分で
// 探しに行く」しかなかった。ここに全件を出し、タップで該当講義へ飛ぶ。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lefture/app/routes.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/application/lecture/lecture_providers.dart';
import 'package:lefture/application/recording/recovery/recovery_providers.dart';
import 'package:lefture/domain/entities/lecture.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/course/widgets/lecture_edit_sheet.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/lecture_tile.dart';
import 'package:lefture/presentation/widgets/orphan_delete_confirm.dart';

class RecoveryListSheet extends ConsumerWidget {
  const RecoveryListSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final orphans = ref.watch(orphanRecordingsProvider).value ?? const [];

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
                        l10n.recoveryListSheetTitle(orphans.length),
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
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: orphans.length,
                  separatorBuilder: (context, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final orphan = orphans[index];
                    final domainLecture =
                        ref.watch(lectureProvider(orphan.lectureId)).value;
                    final driftLecture =
                        ref.watch(recoveryLectureProvider(orphan.lectureId)).value;

                    final now = DateTime.now();
                    final lecture = domainLecture ??
                        Lecture(
                          id: orphan.lectureId,
                          userId: driftLecture?.userId ?? '',
                          courseId: driftLecture?.courseId,
                          title: driftLecture?.title,
                          sortOrder: 0,
                          lectureDatetime: driftLecture?.lectureDatetime ?? now,
                          createdAt: driftLecture?.createdAt ?? now,
                          updatedAt: driftLecture?.updatedAt ?? now,
                        );

                    return LectureTile(
                      lecture: lecture,
                      useRelativeTime: true,
                      showChevron: true,
                      onTap: () {
                        Navigator.of(context).pop();
                        context.push(
                          '${AppRoutes.coursesRootPath}/c/${lecture.courseId}/v/${orphan.lectureId}',
                        );
                      },
                      onEdit: () async {
                        await showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => LectureEditSheet(lecture: lecture),
                        );
                      },
                      onDelete: () async {
                        final confirmed = await confirmOrphanHardDelete(context);
                        if (!confirmed) return;
                        await ref
                            .read(lectureControllerProvider.notifier)
                            .deleteLecture(
                              orphan.lectureId,
                              courseId: lecture.courseId,
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
