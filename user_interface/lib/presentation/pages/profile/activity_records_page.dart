import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:lefture/application/profile/activity_records_provider.dart';
import 'package:lefture/application/lecture_viewer/lecture_viewer_data_provider.dart';
import 'package:lefture/domain/entities/announcement.dart';
import 'package:lefture/domain/entities/lecture_topic.dart';
import 'package:lefture/domain/entities/review_card.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/repositories/review_card_repository_drift.dart';
import 'package:lefture/infrastructure/local_db/repositories/deep_note_repository_drift.dart';
import 'package:lefture/infrastructure/local_db/repositories/fun_fact_repository_drift.dart';
import 'package:lefture/infrastructure/local_db/repositories/announcement_repository_drift.dart';
import 'package:lefture/infrastructure/local_db/repositories/keyword_repository_drift.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/course/widgets/announcement_edit_sheet.dart';
import 'package:lefture/presentation/pages/deep_notes/deep_notes_list_page.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/announcement_tile.dart';
import 'package:lefture/presentation/widgets/announcement_type_icon.dart';
import 'package:lefture/presentation/widgets/app_error_dialog.dart';

class ActivityRecordsPage extends HookConsumerWidget {
  const ActivityRecordsPage({super.key, required this.type});

  final ActivityType type;

  String _pageTitle(AppLocalizations l10n) {
    switch (type) {
      case ActivityType.saved:
        return l10n.activityRecordsTitleSaved;
      case ActivityType.likes:
        return l10n.activityRecordsTitleLikes;
      case ActivityType.dislikes:
        return l10n.activityRecordsTitleDislikes;
      case ActivityType.announcements:
        return l10n.activityRecordsTitleAnnouncements;
      case ActivityType.trash:
        return l10n.activityRecordsTitleTrash;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final recordsAsync = ref.watch(activityRecordsProvider(type));
    final selectedFilter = useState('all');
    final selectedAnnouncementType = useState<AnnouncementType?>(null);

    // Records the user has toggled off the current filter (unliked/undisliked/unsaved) since
    // opening this page, keyed by record id. Kept visible with an "undo" affordance until the
    // user either undoes the action or the fresh data catches up (e.g. they re-liked it).
    final pendingOverrides = useState<Map<String, ActivityRecord>>(const {});
    final removedRecordIds = useState<Set<String>>(const {});

    // Converged means the live data now matches whatever the user would get by hitting "undo",
    // so the pending override is no longer needed.
    bool hasConverged(ActivityRecord anchor, ActivityRecord? live) {
      if (live == null) return false;
      if (type == ActivityType.announcements) {
        final anchorCompleted = (anchor.rawData as LocalAnnouncement).completedAt != null;
        final liveCompleted = (live.rawData as LocalAnnouncement).completedAt != null;
        return anchorCompleted == liveCompleted;
      }
      // Likes/Dislikes/Saved: presence in the fresh (type-filtered) list means it matches again.
      return true;
    }

    useEffect(() {
      final fresh = recordsAsync.asData?.value;
      if (fresh == null) return null;

      // Clear removedRecordIds if fresh list no longer contains them
      if (removedRecordIds.value.isNotEmpty) {
        final freshIds = fresh.map((r) => r.id).toSet();
        final remaining = removedRecordIds.value.intersection(freshIds);
        if (remaining.length != removedRecordIds.value.length) {
          removedRecordIds.value = remaining;
        }
      }

      if (pendingOverrides.value.isEmpty) return null;
      final freshById = {for (final r in fresh) r.id: r};
      final converged = pendingOverrides.value.entries
          .where((e) => hasConverged(e.value, freshById[e.key]))
          .map((e) => e.key)
          .toSet();
      if (converged.isNotEmpty) {
        pendingOverrides.value = Map.of(pendingOverrides.value)
          ..removeWhere((id, _) => converged.contains(id));
      }
      return null;
    }, [recordsAsync.asData?.value]);

    List<ActivityRecord> mergeWithPending(List<ActivityRecord> fresh) {
      final freshIds = fresh.map((r) => r.id).toSet();
      final overlay = pendingOverrides.value.values.where((r) => !freshIds.contains(r.id));
      final merged = [...fresh, ...overlay]
          .where((r) => !removedRecordIds.value.contains(r.id))
          .toList();
      merged.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      return merged;
    }

    // For the Active/Completed sub-filter: while a completion toggle is pending, keep evaluating
    // the filter against the pre-toggle snapshot so the item doesn't jump to the other tab.
    LocalAnnouncement announcementFilterSource(ActivityRecord r) {
      final anchor = pendingOverrides.value[r.id];
      return (anchor ?? r).rawData as LocalAnnouncement;
    }

    // Choose filters dynamically depending on the page type
    final List<Map<String, String>> filters;
    switch (type) {
      case ActivityType.saved:
        filters = [
          {'label': l10n.activityRecordsFilterAll, 'value': 'all'},
          {'label': l10n.activityRecordsFilterReviewCards, 'value': 'reviewCard'},
          {'label': l10n.activityRecordsFilterDeepNotes, 'value': 'deepNote'},
          {'label': l10n.activityRecordsFilterKeywords, 'value': 'keyword'},
        ];
        break;
      case ActivityType.likes:
      case ActivityType.dislikes:
        filters = [
          {'label': l10n.activityRecordsFilterAll, 'value': 'all'},
          {'label': l10n.activityRecordsFilterReviewCards, 'value': 'reviewCard'},
          {'label': l10n.activityRecordsFilterDeepNotes, 'value': 'deepNote'},
          {'label': l10n.activityRecordsFilterFunFacts, 'value': 'funFact'},
        ];
        break;
      case ActivityType.announcements:
        filters = [
          {'label': l10n.activityRecordsFilterAll, 'value': 'all'},
          {'label': l10n.activityRecordsFilterActive, 'value': 'active'},
          {'label': l10n.activityRecordsFilterCompleted, 'value': 'completed'},
        ];
        break;
      case ActivityType.trash:
        filters = [
          {'label': l10n.activityRecordsFilterAll, 'value': 'all'},
          {'label': l10n.activityRecordsFilterCourses, 'value': 'course'},
          {'label': l10n.activityRecordsFilterLectures, 'value': 'lecture'},
          {'label': l10n.activityRecordsTitleAnnouncements, 'value': 'announcement'},
        ];
        break;
    }

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ──────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.universe.voidBackground,
            title: Text(
              _pageTitle(l10n),
              style: const TextStyle(
                color: Color(0xFFF2F2F2),
                fontWeight: FontWeight.w600,
                fontSize: 20,
              ),
            ),
            actions: [
              if (type == ActivityType.trash)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.correctionRed),
                  onPressed: () => _confirmEmptyTrash(context, ref),
                  tooltip: l10n.activityRecordsEmptyTrashLabel,
                ),
            ],
          ),

          // ── Header/Banner & Filters ──────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (type == ActivityType.trash) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.correctionRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.correctionRed.withValues(alpha: 0.25), width: 1),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: AppColors.correctionRed, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              l10n.activityRecordsTrashRetentionBanner,
                              style: const TextStyle(
                                color: Color(0xFFF2F2F2),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Total Counter
                  recordsAsync.when(
                    data: (freshRecords) {
                      final records = mergeWithPending(freshRecords);
                      final count = records.where((r) {
                        if (type == ActivityType.announcements) {
                          final ann = announcementFilterSource(r);
                          if (selectedFilter.value == 'active' && ann.completedAt != null) return false;
                          if (selectedFilter.value == 'completed' && ann.completedAt == null) return false;
                          if (selectedAnnouncementType.value != null) {
                            final annType = announcementTypeFromString(ann.type);
                            if (annType != selectedAnnouncementType.value) return false;
                          }
                          return true;
                        }
                        if (selectedFilter.value == 'all') return true;
                        if (type == ActivityType.saved || type == ActivityType.likes || type == ActivityType.dislikes) {
                          if (selectedFilter.value == 'reviewCard') return r.type == ActivityRecordType.reviewCard;
                          if (selectedFilter.value == 'deepNote') return r.type == ActivityRecordType.deepNote;
                          if (selectedFilter.value == 'funFact') return r.type == ActivityRecordType.funFact;
                        }
                        if (type == ActivityType.trash) {
                          if (selectedFilter.value == 'course') return r.type == ActivityRecordType.course;
                          if (selectedFilter.value == 'lecture') return r.type == ActivityRecordType.lecture;
                          if (selectedFilter.value == 'announcement') return r.type == ActivityRecordType.announcement;
                        }
                        return true;
                      }).length;

                      return Text(
                        l10n.activityRecordsItemsFoundCount(count),
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 13,
                        ),
                      );
                    },
                    loading: () => const SizedBox(),
                    error: (error, stackTrace) => const SizedBox(),
                  ),

                  const SizedBox(height: 12),

                  // Horizontal Filter Chips (Status)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: filters.map((f) {
                        final isSelected = selectedFilter.value == f['value'];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            selected: isSelected,
                            label: Text(f['label']!),
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : AppColors.universe.textComet,
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                            selectedColor: AppColors.starGold,
                            backgroundColor: Colors.white.withValues(alpha: 0.05),
                            checkmarkColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: BorderSide(
                                color: isSelected ? Colors.transparent : Colors.white10,
                              ),
                            ),
                            onSelected: (_) {
                              selectedFilter.value = f['value']!;
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  if (type == ActivityType.announcements) ...[
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _ActivityTypeChip(
                            label: l10n.activityRecordsFilterAll,
                            icon: Icons.apps,
                            color: AppColors.starGold,
                            isSelected: selectedAnnouncementType.value == null,
                            onTap: () => selectedAnnouncementType.value = null,
                          ),
                          const SizedBox(width: 8),
                          ...[
                            AnnouncementType.todo,
                            AnnouncementType.event,
                            AnnouncementType.info,
                            AnnouncementType.hint,
                          ].map((annType) {
                            final color = colorForAnnouncementType(annType);
                            final icon = iconForAnnouncementType(annType);
                            final label = annType.name.toUpperCase();
                            final isSelected = selectedAnnouncementType.value == annType;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _ActivityTypeChip(
                                label: label,
                                icon: icon,
                                color: color,
                                isSelected: isSelected,
                                onTap: () => selectedAnnouncementType.value =
                                    isSelected ? null : annType,
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // ── Records List ─────────────────────────────────────────
          recordsAsync.when(
            data: (freshRecords) {
              final records = mergeWithPending(freshRecords);
              final filtered = records.where((r) {
                if (type == ActivityType.announcements) {
                  final ann = announcementFilterSource(r);
                  if (selectedFilter.value == 'active' && ann.completedAt != null) return false;
                  if (selectedFilter.value == 'completed' && ann.completedAt == null) return false;
                  if (selectedAnnouncementType.value != null) {
                    final annType = announcementTypeFromString(ann.type);
                    if (annType != selectedAnnouncementType.value) return false;
                  }
                  return true;
                }
                if (selectedFilter.value == 'all') return true;
                if (type == ActivityType.saved || type == ActivityType.likes || type == ActivityType.dislikes) {
                  if (selectedFilter.value == 'reviewCard') return r.type == ActivityRecordType.reviewCard;
                  if (selectedFilter.value == 'deepNote') return r.type == ActivityRecordType.deepNote;
                  if (selectedFilter.value == 'keyword') return r.type == ActivityRecordType.keyword;
                  if (selectedFilter.value == 'funFact') return r.type == ActivityRecordType.funFact;
                }
                if (type == ActivityType.trash) {
                  if (selectedFilter.value == 'course') return r.type == ActivityRecordType.course;
                  if (selectedFilter.value == 'lecture') return r.type == ActivityRecordType.lecture;
                  if (selectedFilter.value == 'announcement') return r.type == ActivityRecordType.announcement;
                }
                return true;
              }).toList();

              if (filtered.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Text(
                      l10n.activityRecordsNoFilterMatch,
                      style: const TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final record = filtered[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildRecordCard(context, ref, record, pendingOverrides, removedRecordIds),
                      );
                    },
                    childCount: filtered.length,
                  ),
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.starGold),
              ),
            ),
            error: (error, stackTrace) => SliverFillRemaining(
              child: Center(
                child: Text(
                  l10n.activityRecordsLoadFailed(error.toString()),
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildRecordCard(
    BuildContext context,
    WidgetRef ref,
    ActivityRecord record,
    ValueNotifier<Map<String, ActivityRecord>> pendingOverrides,
    ValueNotifier<Set<String>> removedRecordIds,
  ) {
    if (record.type == ActivityRecordType.announcement && type != ActivityType.trash) {
      final ann = record.rawData as LocalAnnouncement;
      final domainAnn = Announcement(
        id: ann.id,
        userId: ann.userId,
        lectureId: ann.lectureId,
        type: announcementTypeFromString(ann.type),
        title: ann.title,
        description: ann.description,
        location: ann.location,
        startSid: ann.startSid,
        endSid: ann.endSid,
        relatedTopicTitle: ann.relatedTopicTitle,
        datetimeParameters: ann.datetimeParametersJson != null
            ? Map<String, dynamic>.from(jsonDecode(ann.datetimeParametersJson!) as Map)
            : null,
        completedAt: ann.completedAt,
        deletedAt: ann.deletedAt,
        metadata: ann.metadataJson != null
            ? Map<String, dynamic>.from(jsonDecode(ann.metadataJson!) as Map)
            : null,
        createdAt: ann.createdAt,
        updatedAt: ann.updatedAt,
      );
      return AnnouncementTile(
        key: ValueKey('announcement_${domainAnn.id}_${domainAnn.isCompleted}'),
        announcement: domainAnn,
        onToggleComplete: (a) async {
          final isPending = pendingOverrides.value.containsKey(record.id);
          final next = Map<String, ActivityRecord>.of(pendingOverrides.value);
          if (isPending) {
            next.remove(record.id);
          } else {
            next[record.id] = record;
          }
          pendingOverrides.value = next;

          await ref.read(announcementRepositoryDriftProvider).toggleComplete(id: a.id, completed: !a.isCompleted);
          ref.read(lectureControllerProvider.notifier).pushOutboxNow();
        },
        onEdit: () async {
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => AnnouncementEditSheet(announcement: domainAnn),
          );
        },
        onDelete: (Announcement a) async {
          await ref
              .read(announcementRepositoryDriftProvider)
              .softDeleteAnnouncement(id: a.id);
          ref.read(lectureControllerProvider.notifier).pushOutboxNow();
        },
      );
    }

    if (type == ActivityType.trash) {
      return _buildTrashCard(context, ref, record, removedRecordIds);
    }

    final isPending = pendingOverrides.value.containsKey(record.id);

    return _ActivityContentCard(
      key: ValueKey(record.id),
      record: record,
      activityType: type,
      isPending: isPending,
      onToggleAction: () {
        final next = Map<String, ActivityRecord>.of(pendingOverrides.value);
        if (isPending) {
          next.remove(record.id);
        } else {
          next[record.id] = record;
        }
        pendingOverrides.value = next;

        switch (type) {
          case ActivityType.likes:
            _updateReaction(ref, record, isPending ? 'like' : null);
            break;
          case ActivityType.dislikes:
            _updateReaction(ref, record, isPending ? 'dislike' : null);
            break;
          case ActivityType.saved:
            _toggleSave(ref, record, isPending);
            break;
          default:
            break;
        }
      },
    );
  }

  Widget _buildTrashCard(
    BuildContext context,
    WidgetRef ref,
    ActivityRecord record,
    ValueNotifier<Set<String>> removedRecordIds,
  ) {
    final l10n = AppLocalizations.of(context);
    final IconData icon;
    final String typeLabel;

    switch (record.type) {
      case ActivityRecordType.course:
        icon = Icons.school_rounded;
        typeLabel = l10n.activityRecordsTypeLabelCourse;
        break;
      case ActivityRecordType.lecture:
        icon = Icons.mic_rounded;
        typeLabel = l10n.activityRecordsTypeLabelLecture;
        break;
      case ActivityRecordType.announcement:
        icon = Icons.campaign_rounded;
        typeLabel = l10n.activityRecordsTypeLabelAnnouncement;
        break;
      default:
        icon = Icons.delete_rounded;
        typeLabel = l10n.activityRecordsTypeLabelItem;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          // Left Icon Circle
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.universe.textComet, size: 20),
          ),
          const SizedBox(width: 14),

          // Texts
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.title,
                  style: const TextStyle(
                    color: Color(0xFFF2F2F2),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.activityRecordsDeletedOnLabel(DateFormat.yMMMd(l10n.localeName).format(record.dateTime), typeLabel),
                  style: TextStyle(
                    color: AppColors.universe.textComet,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Compact Action Buttons
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _restoreTrashItem(context, ref, record, removedRecordIds),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              child: Icon(
                Icons.settings_backup_restore_rounded,
                color: AppColors.starGold,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _confirmDeleteSingleTrashItem(context, ref, record, removedRecordIds),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              child: Icon(
                Icons.delete_forever_rounded,
                color: AppColors.correctionRed,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateReaction(WidgetRef ref, ActivityRecord record, String? newReaction) async {
    if (record.type == ActivityRecordType.reviewCard) {
      await ref.read(reviewCardRepositoryDriftProvider).updateReaction(id: record.id, reaction: newReaction);
    } else if (record.type == ActivityRecordType.deepNote) {
      await ref.read(deepNoteRepositoryDriftProvider).updateReaction(id: record.id, reaction: newReaction);
    } else if (record.type == ActivityRecordType.funFact) {
      await ref.read(funFactRepositoryDriftProvider).updateReaction(id: record.id, reaction: newReaction);
    }
    ref.read(lectureControllerProvider.notifier).pushOutboxNow();
  }

  Future<void> _toggleSave(WidgetRef ref, ActivityRecord record, bool save) async {
    final uid = supabase.auth.currentUser?.id;
    if (record.type == ActivityRecordType.reviewCard) {
      await ref.read(reviewCardRepositoryDriftProvider).updateSaved(id: record.id, saved: save);
    } else if (record.type == ActivityRecordType.deepNote) {
      await ref.read(deepNoteRepositoryDriftProvider).updateSaved(id: record.id, saved: save);
    } else if (record.type == ActivityRecordType.keyword && uid != null) {
      final raw = record.rawData as LocalKeyword;
      await ref.read(keywordRepositoryDriftProvider).toggleSaveKeyword(
            keywordId: record.id,
            userId: uid,
            isSaved: save,
            existingMetadataJson: raw.metadataJson,
          );
    }
    ref.read(lectureControllerProvider.notifier).pushOutboxNow();
  }

  Future<void> _restoreTrashItem(BuildContext context, WidgetRef ref, ActivityRecord record, ValueNotifier<Set<String>> removedRecordIds) async {
    final l10n = AppLocalizations.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      await TrashController.restoreItem(ref, record);
      removedRecordIds.value = {...removedRecordIds.value, record.id};
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(l10n.activityRecordsRestoredSnackbar),
          backgroundColor: AppColors.growthGreen,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        AppErrorDialog.showSmart(context, e, actionName: 'restoring trash item');
      }
    }
  }

  void _confirmDeleteSingleTrashItem(BuildContext context, WidgetRef ref, ActivityRecord record, ValueNotifier<Set<String>> removedRecordIds) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.universe.voidBackground,
          title: Text(
            l10n.activityRecordsDeleteItemDialogTitle(record.title),
            style: const TextStyle(color: Color(0xFFF2F2F2)),
          ),
          content: Text(
            l10n.activityRecordsDeleteItemDialogMessage,
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.activityRecordsCancelButton, style: const TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                // ダイアログを閉じた直後にunmountされる dialogContext ではなく、
                // await後もこのページが表示され続ける限り有効な外側の context を
                // 使う(そうしないと、非同期処理の完了時にcontext.mountedが常に
                // falseになり、エラーダイアログが一切表示されなくなるバグになる)。
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                try {
                  await TrashController.deleteSingleItem(ref, record);
                  removedRecordIds.value = {...removedRecordIds.value, record.id};
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text(l10n.activityRecordsItemDeletedSnackbar),
                      backgroundColor: AppColors.growthGreen,
                    ),
                  );
                } catch (e) {
                  if (context.mounted) {
                    AppErrorDialog.showSmart(context, e, actionName: 'deleting trash item');
                  }
                }
              },
              child: Text(l10n.activityRecordsDeleteButton, style: const TextStyle(color: AppColors.correctionRed)),
            ),
          ],
        );
      },
    );
  }

  void _confirmEmptyTrash(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.universe.voidBackground,
          title: Text(
            l10n.activityRecordsEmptyTrashDialogTitle,
            style: const TextStyle(color: Color(0xFFF2F2F2)),
          ),
          content: Text(
            l10n.activityRecordsEmptyTrashDialogMessage,
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.activityRecordsCancelButton, style: const TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                // dialogContextはダイアログを閉じた直後にunmountされるため、
                // await後も有効な外側のページcontextを使う(_confirmDeleteSingleTrashItem
                // と同じ理由)。
                final scaffold = ScaffoldMessenger.of(context);
                try {
                  final result = await TrashController.emptyTrash(ref);
                  final failedCount = result.coursesFailed.length + result.lecturesFailed.length;
                  scaffold.showSnackBar(
                    SnackBar(
                      content: Text(
                        result.hasFailures
                            ? l10n.activityRecordsEmptyTrashPartialFailureSnackbar(
                                result.coursesDeleted + result.lecturesDeleted, failedCount)
                            : l10n.activityRecordsEmptyTrashSuccessSnackbar,
                      ),
                      backgroundColor: result.hasFailures ? AppColors.correctionRed : AppColors.growthGreen,
                    ),
                  );
                } catch (e) {
                  if (context.mounted) {
                    AppErrorDialog.showSmart(context, e, actionName: 'emptying trash');
                  }
                }
              },
              child: Text(l10n.activityRecordsEmptyTrashLabel, style: const TextStyle(color: AppColors.correctionRed)),
            ),
          ],
        );
      },
    );
  }
}

class _ActivityContentCard extends ConsumerWidget {
  const _ActivityContentCard({
    super.key,
    required this.record,
    required this.activityType,
    required this.isPending,
    required this.onToggleAction,
  });

  final ActivityRecord record;
  final ActivityType activityType;

  /// True once the user has toggled this record off the current filter
  /// (unliked/undisliked/unsaved) but it's still shown with an undo affordance.
  final bool isPending;
  final VoidCallback onToggleAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final IconData icon;
    final String typeLabel;
    final Color badgeColor;

    switch (record.type) {
      case ActivityRecordType.reviewCard:
        icon = Icons.bookmark_rounded;
        typeLabel = l10n.activityRecordsContentTypeReviewCard;
        badgeColor = AppColors.starGold;
        break;
      case ActivityRecordType.deepNote:
        icon = Icons.article_rounded;
        typeLabel = l10n.activityRecordsContentTypeDeepNote;
        badgeColor = AppColors.starGold;
        break;
      case ActivityRecordType.keyword:
        icon = Icons.style_rounded;
        typeLabel = l10n.activityRecordsContentTypeKeyword;
        badgeColor = AppColors.starGold;
        break;
      case ActivityRecordType.funFact:
        icon = Icons.lightbulb_rounded;
        typeLabel = l10n.activityRecordsContentTypeFunFact;
        badgeColor = AppColors.starGold;
        break;
      default:
        icon = Icons.star_rounded;
        typeLabel = l10n.activityRecordsContentTypeDefault;
        badgeColor = AppColors.starGold;
    }

    final undoLabel = switch (activityType) {
      ActivityType.saved => l10n.activityRecordsUndoUnsaved,
      ActivityType.likes || ActivityType.dislikes => l10n.activityRecordsUndoUnreacted,
      _ => null,
    };

    VoidCallback? onTapCard;
    if (record.courseId != null && record.lectureId != null) {
      if (record.type == ActivityRecordType.reviewCard) {
        final card = record.rawData as LocalReviewCard;
        final allCards = ref.watch(reviewCardsProvider(record.lectureId!)).asData?.value ?? <ReviewCard>[];
        final allTopics = ref.watch(lectureTopicsProvider(record.lectureId!)).asData?.value ?? <LectureTopic>[];
        
        var targetIndex = 0;
        var currentFlatIdx = 0;
        for (final topic in allTopics) {
          final groupCards = sortReviewCards(allCards.where((c) => c.topicNumber == topic.index).toList());
          currentFlatIdx++; // Cover card
          for (final c in groupCards) {
            if (c.id == card.id) {
              targetIndex = currentFlatIdx;
              break;
            }
            currentFlatIdx++;
          }
          if (targetIndex > 0) break;
        }

        onTapCard = () {
          context.push('/home/courses/c/${record.courseId}/rcv/${record.lectureId}?index=$targetIndex');
        };
      } else if (record.type == ActivityRecordType.deepNote) {
        final note = record.rawData as LocalDeepNote;
        final allTopics = ref.watch(lectureTopicsProvider(record.lectureId!)).asData?.value ?? <LectureTopic>[];
        var targetArrayIndex = allTopics.indexWhere((t) => t.index == note.topicNumber);
        if (targetArrayIndex < 0) {
          targetArrayIndex = note.topicNumber > 0 ? note.topicNumber - 1 : 0;
        }

        onTapCard = () {
          context.push('/home/courses/c/${record.courseId}/dnd/${record.lectureId}/$targetArrayIndex', extra: <DeepNoteTopic>[]);
        };
      }
    }

    Widget actionIcon(IconData iconData, Color color) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggleAction,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Icon(iconData, color: color, size: 20),
        ),
      );
    }

    Widget? actionButton;
    switch (activityType) {
      case ActivityType.likes:
        actionButton = actionIcon(
          isPending ? Icons.favorite_border_rounded : Icons.favorite_rounded,
          isPending ? Colors.white38 : const Color(0xFFE53935),
        );
        break;
      case ActivityType.dislikes:
        actionButton = actionIcon(
          isPending ? Icons.thumb_down_alt_outlined : Icons.thumb_down_rounded,
          isPending ? Colors.white38 : const Color(0xFF2196F3),
        );
        break;
      case ActivityType.saved:
        if (record.type == ActivityRecordType.reviewCard || record.type == ActivityRecordType.deepNote) {
          actionButton = actionIcon(
            isPending ? Icons.bookmark_border_rounded : Icons.bookmark_rounded,
            isPending ? Colors.white38 : const Color(0xFF4CAF50),
          );
        }
        break;
      default:
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: isPending
            ? Colors.white.withValues(alpha: 0.02)
            : AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPending
              ? Colors.white12
              : AppColors.universe.glassBorder,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTapCard,
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.white10,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Badge Row
                Row(
                  children: [
                    Icon(icon, color: badgeColor, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      typeLabel.toUpperCase(),
                      style: TextStyle(
                        color: badgeColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      DateFormat.MMMd(l10n.localeName).add_jm().format(record.dateTime),
                      style: TextStyle(
                        color: AppColors.universe.textComet,
                        fontSize: 11,
                      ),
                    ),
                    if (onTapCard != null) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.universe.textComet,
                        size: 18,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),

                // Title
                Text(
                  record.title,
                  style: TextStyle(
                    color: isPending
                        ? Colors.white54
                        : const Color(0xFFF2F2F2),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),

                // Content body snippet
                Text(
                  record.content,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isPending
                        ? Colors.white38
                        : Colors.white70,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                
                const SizedBox(height: 12),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 8),

                // Action Toolbar Row
                Row(
                  children: [
                    if (isPending && undoLabel != null)
                      Text(
                        undoLabel,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    const Spacer(),
                    if (actionButton != null) actionButton,
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityTypeChip extends StatelessWidget {
  const _ActivityTypeChip({
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
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.white10,
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

