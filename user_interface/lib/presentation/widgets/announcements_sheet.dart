import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/application/announcement/announcement_provider.dart';
import 'package:lefture/application/course/course_announcement_provider.dart';
import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/application/lecture/lecture_list_provider.dart';
import 'package:lefture/application/lecture_viewer/lecture_viewer_data_provider.dart';
import 'package:lefture/domain/entities/announcement.dart';
import 'package:lefture/infrastructure/local_db/repositories/announcement_repository_drift.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/course/widgets/announcement_edit_sheet.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/announcement_tile.dart';
import 'package:lefture/presentation/widgets/announcement_type_icon.dart';

/// アナウンスメント一覧ボトムシート。
/// - [lectureId] 指定: 該当レクチャーのアナウンスを表示
/// - [courseId] 指定: 該当コース全レクチャーのアナウンスを表示
/// - 指定なし: 全コース横断のアナウンスを表示（ホーム画面用）
class AnnouncementsSheet extends HookConsumerWidget {
  const AnnouncementsSheet({
    super.key,
    this.courseId,
    this.lectureId,
    this.title,
    this.targetAnnouncementId,
  });

  final String? courseId;
  final String? lectureId;
  final String? title;
  final String? targetAnnouncementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    // フィルター状態
    final statusFilter = useState<String>('active'); // 'active', 'completed', 'all'
    final selectedType = useState<AnnouncementType?>(null); // null = すべて
    final recentlyCompletedIds = useState<Set<String>>({}); // 直近スワイプ完了したアナウンスID

    final targetItemKey = useMemoized(() => GlobalKey());
    final hasScrolledToTarget = useRef(false);

    // タブが切り替わったら一時保持リストをクリア
    useEffect(() {
      recentlyCompletedIds.value = {};
      return null;
    }, [statusFilter.value]);

    // データソースの分岐
    final AsyncValue<List<Announcement>> announcementsAsync;
    if (lectureId != null) {
      announcementsAsync = ref.watch(announcementsForLectureProvider(lectureId!));
    } else if (courseId != null) {
      announcementsAsync = ref.watch(allAnnouncementsForCourseProvider(courseId!));
    } else {
      announcementsAsync = ref.watch(allAnnouncementsProvider);
    }

    final sheetScrollControllerRef = useRef<ScrollController?>(null);

    // targetAnnouncementId が指定されている場合、完了済みならタブを切り替え、ターゲット位置へスクロール
    useEffect(() {
      if (targetAnnouncementId != null && !hasScrolledToTarget.value) {
        final list = announcementsAsync.asData?.value;
        if (list != null && list.any((a) => a.id == targetAnnouncementId)) {
          final target = list.firstWhere((a) => a.id == targetAnnouncementId);
          if (target.isCompleted && statusFilter.value == 'active') {
            statusFilter.value = 'all';
          }
          if (selectedType.value != null && selectedType.value != target.type) {
            selectedType.value = null;
          }

          hasScrolledToTarget.value = true;

          // BottomSheetの展開アニメーション完了(約350ms)を待ってからスクロールを実行
          Future.delayed(const Duration(milliseconds: 350), () async {
            if (!context.mounted) return;
            final sc = sheetScrollControllerRef.value;
            final targetIndex = list.indexWhere((a) => a.id == targetAnnouncementId);

            if (targetIndex >= 0 && sc != null && sc.hasClients) {
              const estimatedItemHeight = 110.0;
              final maxScroll = sc.position.maxScrollExtent;
              final targetOffset = (targetIndex * estimatedItemHeight).clamp(0.0, maxScroll);
              if (targetOffset > 0) {
                await sc.animateTo(
                  targetOffset,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                );
              }
            }

            if (!context.mounted) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final ctx = targetItemKey.currentContext;
              if (ctx != null) {
                Scrollable.ensureVisible(
                  ctx,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  alignment: 0.15,
                );
              }
            });
          });
        }
      }
      return null;
    }, [announcementsAsync, targetAnnouncementId]);

    // タイトルの決定
    final sheetTitle = title ??
        (lectureId != null || courseId != null
            ? l10n.lectureViewerAnnouncementsSheetTitle
            : l10n.homeAnnouncementsSheetTitle);

    // 全コース表示時のコース情報ルックアップテーブル
    final bool isGlobalScope = lectureId == null && courseId == null;
    final lectures = isGlobalScope
        ? (ref.watch(allLecturesStreamProvider).asData?.value ?? const [])
        : const [];
    final courseIdByLectureId = isGlobalScope
        ? {for (final l in lectures) l.id: l.courseId}
        : const <String, String>{};
    final courses = isGlobalScope
        ? (ref.watch(courseListProvider).asData?.value ?? const [])
        : const [];
    final courseTitleById = isGlobalScope
        ? {for (final c in courses) c.id: c.displayTitle}
        : const <String, String>{};

    return DraggableScrollableSheet(
      initialChildSize: lectureId != null ? 0.65 : 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        sheetScrollControllerRef.value = scrollController;
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
                        sheetTitle,
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

              // ── 1. 状態フィルター（セグメントバー） ──────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppColors.universe.glassWhiteLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.universe.glassBorder),
                  ),
                  child: Row(
                    children: [
                      _SegmentItem(
                        label: l10n.activityRecordsFilterActive,
                        isSelected: statusFilter.value == 'active',
                        onTap: () => statusFilter.value = 'active',
                      ),
                      _SegmentItem(
                        label: l10n.activityRecordsFilterCompleted,
                        isSelected: statusFilter.value == 'completed',
                        onTap: () => statusFilter.value = 'completed',
                      ),
                      _SegmentItem(
                        label: l10n.activityRecordsFilterAll,
                        isSelected: statusFilter.value == 'all',
                        onTap: () => statusFilter.value = 'all',
                      ),
                    ],
                  ),
                ),
              ),

              // ── 2. 種類フィルター（タイプ別カラーチップ） ────────────
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                child: Row(
                  children: [
                    _TypeChip(
                      label: l10n.activityRecordsFilterAll,
                      icon: Icons.apps,
                      color: AppColors.starGold,
                      isSelected: selectedType.value == null,
                      onTap: () => selectedType.value = null,
                    ),
                    const SizedBox(width: 8),
                    ...[
                      AnnouncementType.todo,
                      AnnouncementType.event,
                      AnnouncementType.info,
                      AnnouncementType.hint,
                    ].map((type) {
                      final color = colorForAnnouncementType(type);
                      final icon = iconForAnnouncementType(type);
                      final label = type.name.toUpperCase();
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _TypeChip(
                          label: label,
                          icon: icon,
                          color: color,
                          isSelected: selectedType.value == type,
                          onTap: () => selectedType.value =
                              selectedType.value == type ? null : type,
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 4),

              Expanded(
                child: announcementsAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.starGold),
                  ),
                  error: (e, _) => Center(
                    child: Text(
                      l10n.homeAnnouncementsSheetLoadError(e.toString()),
                      style: const TextStyle(color: AppColors.correctionRed),
                    ),
                  ),
                  data: (announcements) {
                    // フィルタリング処理
                    final filteredList = announcements.where((a) {
                      // 状態フィルター
                      if (statusFilter.value == 'active' && a.isCompleted) {
                        // 直近でスワイプ完了にしたアイテムは一時的に表示を維持
                        if (!recentlyCompletedIds.value.contains(a.id)) {
                          return false;
                        }
                      }
                      if (statusFilter.value == 'completed' && !a.isCompleted) return false;

                      // 種類フィルター
                      if (selectedType.value != null && a.type != selectedType.value) {
                        return false;
                      }

                      return true;
                    }).toList();

                    if (filteredList.isEmpty) {
                      final emptyMsg = courseId != null
                          ? l10n.courseNoAnnouncementsLabel
                          : l10n.homeAnnouncementsEmptyMessage;
                      return Center(
                        child: Text(
                          emptyMsg,
                          style: TextStyle(color: AppColors.universe.textComet),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      cacheExtent: 2000,
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      itemCount: filteredList.length,
                      separatorBuilder: (context, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final announcement = filteredList[index];
                        final isTarget = announcement.id == targetAnnouncementId;
                        final targetCourseId = isGlobalScope
                            ? (announcement.lectureId == null
                                ? null
                                : courseIdByLectureId[announcement.lectureId])
                            : courseId;

                        final tileWidget = AnnouncementTile(
                          key: ValueKey('announcement_${announcement.id}_${announcement.isCompleted}'),
                          announcement: announcement,
                          courseName: targetCourseId == null
                              ? null
                              : courseTitleById[targetCourseId],
                          onTap: (announcement.lectureId != null && targetCourseId != null)
                              ? () {
                                  Navigator.of(context).pop();
                                  context.push(
                                    '${AppRoutes.coursesRootPath}/c/$targetCourseId/v/${announcement.lectureId}?openAnnouncementId=${announcement.id}',
                                  );
                                }
                              : (targetCourseId != null
                                  ? () {
                                      Navigator.of(context).pop();
                                      context.push('${AppRoutes.coursesRootPath}/c/$targetCourseId');
                                    }
                                  : null),
                          onToggleComplete: (a) async {
                            final nextState = !a.isCompleted;
                            if (nextState) {
                              recentlyCompletedIds.value = {...recentlyCompletedIds.value, a.id};
                            } else {
                              recentlyCompletedIds.value =
                                  recentlyCompletedIds.value.where((id) => id != a.id).toSet();
                            }
                            await ref
                                .read(announcementRepositoryDriftProvider)
                                .toggleComplete(id: a.id, completed: nextState);
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

                        if (isTarget) {
                          return KeyedSubtree(
                            key: targetItemKey,
                            child: tileWidget,
                          );
                        }
                        return tileWidget;
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

class _SegmentItem extends StatelessWidget {
  const _SegmentItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.starGold.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: AppColors.starGold.withValues(alpha: 0.5), width: 1)
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? AppColors.universe.textStarlight
                  : AppColors.universe.textComet,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : AppColors.universe.glassWhiteLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : AppColors.universe.glassBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? color : AppColors.universe.textComet,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : AppColors.universe.textComet,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
