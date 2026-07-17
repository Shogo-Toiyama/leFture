import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:drift/drift.dart' show Value;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lecture_companion_ui/application/profile/activity_records_provider.dart';
import 'package:lecture_companion_ui/domain/entities/announcement.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/repositories/review_card_repository_drift.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/repositories/deep_note_repository_drift.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/repositories/fun_fact_repository_drift.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/repositories/announcement_repository_drift.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/announcement_tile.dart';

class ActivityRecordsPage extends HookConsumerWidget {
  const ActivityRecordsPage({super.key, required this.type});

  final ActivityType type;

  String get _pageTitle {
    switch (type) {
      case ActivityType.saved:
        return 'Saved';
      case ActivityType.likes:
        return 'Likes';
      case ActivityType.dislikes:
        return 'Dislikes';
      case ActivityType.announcements:
        return 'Announcements';
      case ActivityType.trash:
        return 'Trash';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(activityRecordsProvider(type));
    final selectedFilter = useState('all');

    // Choose filters dynamically depending on the page type
    final List<Map<String, String>> filters;
    switch (type) {
      case ActivityType.saved:
        filters = const [
          {'label': 'All', 'value': 'all'},
          {'label': 'Review Cards', 'value': 'reviewCard'},
          {'label': 'Deep Notes', 'value': 'deepNote'},
        ];
        break;
      case ActivityType.likes:
      case ActivityType.dislikes:
        filters = const [
          {'label': 'All', 'value': 'all'},
          {'label': 'Review Cards', 'value': 'reviewCard'},
          {'label': 'Deep Notes', 'value': 'deepNote'},
          {'label': 'Fun Facts', 'value': 'funFact'},
        ];
        break;
      case ActivityType.announcements:
        filters = const [
          {'label': 'All', 'value': 'all'},
          {'label': 'Active', 'value': 'active'},
          {'label': 'Completed', 'value': 'completed'},
        ];
        break;
      case ActivityType.trash:
        filters = const [
          {'label': 'All', 'value': 'all'},
          {'label': 'Courses', 'value': 'course'},
          {'label': 'Lectures', 'value': 'lecture'},
          {'label': 'Announcements', 'value': 'announcement'},
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
              _pageTitle,
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
                  tooltip: 'Empty Trash',
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
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: AppColors.correctionRed, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Items in Trash will be permanently deleted after 30 days.',
                              style: TextStyle(
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
                    data: (records) {
                      final count = records.where((r) {
                        if (selectedFilter.value == 'all') return true;
                        if (type == ActivityType.saved || type == ActivityType.likes || type == ActivityType.dislikes) {
                          if (selectedFilter.value == 'reviewCard') return r.type == ActivityRecordType.reviewCard;
                          if (selectedFilter.value == 'deepNote') return r.type == ActivityRecordType.deepNote;
                          if (selectedFilter.value == 'funFact') return r.type == ActivityRecordType.funFact;
                        }
                        if (type == ActivityType.announcements) {
                          final ann = r.rawData as LocalAnnouncement;
                          if (selectedFilter.value == 'active') return ann.completedAt == null;
                          if (selectedFilter.value == 'completed') return ann.completedAt != null;
                        }
                        if (type == ActivityType.trash) {
                          if (selectedFilter.value == 'course') return r.type == ActivityRecordType.course;
                          if (selectedFilter.value == 'lecture') return r.type == ActivityRecordType.lecture;
                          if (selectedFilter.value == 'announcement') return r.type == ActivityRecordType.announcement;
                        }
                        return true;
                      }).length;

                      return Text(
                        '$count items found',
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

                  // Horizontal Filter Chips
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
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // ── Records List ─────────────────────────────────────────
          recordsAsync.when(
            data: (records) {
              final filtered = records.where((r) {
                if (selectedFilter.value == 'all') return true;
                if (type == ActivityType.saved || type == ActivityType.likes || type == ActivityType.dislikes) {
                  if (selectedFilter.value == 'reviewCard') return r.type == ActivityRecordType.reviewCard;
                  if (selectedFilter.value == 'deepNote') return r.type == ActivityRecordType.deepNote;
                  if (selectedFilter.value == 'funFact') return r.type == ActivityRecordType.funFact;
                }
                if (type == ActivityType.announcements) {
                  final ann = r.rawData as LocalAnnouncement;
                  if (selectedFilter.value == 'active') return ann.completedAt == null;
                  if (selectedFilter.value == 'completed') return ann.completedAt != null;
                }
                if (type == ActivityType.trash) {
                  if (selectedFilter.value == 'course') return r.type == ActivityRecordType.course;
                  if (selectedFilter.value == 'lecture') return r.type == ActivityRecordType.lecture;
                  if (selectedFilter.value == 'announcement') return r.type == ActivityRecordType.announcement;
                }
                return true;
              }).toList();

              if (filtered.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'No items match this filter.',
                      style: TextStyle(color: Colors.white38, fontSize: 14),
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
                        child: _buildRecordCard(context, ref, record),
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
                  'Failed to load records: $error',
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

  Widget _buildRecordCard(BuildContext context, WidgetRef ref, ActivityRecord record) {
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
        metadata: ann.metadataJson != null
            ? Map<String, dynamic>.from(jsonDecode(ann.metadataJson!) as Map)
            : null,
        createdAt: ann.createdAt,
        updatedAt: ann.updatedAt,
      );
      return AnnouncementTile(
        announcement: domainAnn,
        onToggleComplete: (a) async {
          await ref.read(announcementRepositoryDriftProvider).toggleComplete(id: a.id, completed: !a.isCompleted);
          ref.read(lectureControllerProvider.notifier).pushOutboxNow();
        },
      );
    }

    if (type == ActivityType.trash) {
      return _buildTrashCard(context, ref, record);
    }

    return _buildContentCard(context, ref, record);
  }

  Widget _buildContentCard(BuildContext context, WidgetRef ref, ActivityRecord record) {
    final IconData icon;
    final String typeLabel;

    switch (record.type) {
      case ActivityRecordType.reviewCard:
        icon = Icons.bookmark_rounded;
        typeLabel = 'Review Card';
        break;
      case ActivityRecordType.deepNote:
        icon = Icons.article_rounded;
        typeLabel = 'Deep Note';
        break;
      case ActivityRecordType.funFact:
        icon = Icons.lightbulb_rounded;
        typeLabel = 'Fun Fact';
        break;
      default:
        icon = Icons.star_rounded;
        typeLabel = 'Content';
    }

    // Toggle Saved Status Action
    final isSaved = _isSavedRecord(record);
    final String? reaction = _getReactionRecord(record);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Badge Row
          Row(
            children: [
              Icon(icon, color: AppColors.starGold, size: 16),
              const SizedBox(width: 6),
              Text(
                typeLabel.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.starGold,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              Text(
                DateFormat('MMM d, h:mm a').format(record.dateTime),
                style: TextStyle(
                  color: AppColors.universe.textComet,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Title
          Text(
            record.title,
            style: const TextStyle(
              color: Color(0xFFF2F2F2),
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
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 14),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 8),

          // Action Toolbar Row
          Row(
            children: [
              // Like Button
              IconButton(
                icon: Icon(
                  reaction == 'like' ? Icons.thumb_up_rounded : Icons.thumb_up_alt_outlined,
                  color: reaction == 'like' ? Colors.blueAccent : Colors.white38,
                  size: 20,
                ),
                onPressed: () => _updateReaction(ref, record, reaction == 'like' ? null : 'like'),
              ),
              // Dislike Button
              IconButton(
                icon: Icon(
                  reaction == 'dislike' ? Icons.thumb_down_rounded : Icons.thumb_down_alt_outlined,
                  color: reaction == 'dislike' ? Colors.redAccent : Colors.white38,
                  size: 20,
                ),
                onPressed: () => _updateReaction(ref, record, reaction == 'dislike' ? null : 'dislike'),
              ),
              const Spacer(),
              // Save Toggle Button (only for reviewCard & deepNote)
              if (record.type == ActivityRecordType.reviewCard || record.type == ActivityRecordType.deepNote)
                IconButton(
                  icon: Icon(
                    isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    color: isSaved ? AppColors.starGold : Colors.white38,
                    size: 20,
                  ),
                  onPressed: () => _toggleSave(ref, record, !isSaved),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrashCard(BuildContext context, WidgetRef ref, ActivityRecord record) {
    final IconData icon;
    final String typeLabel;

    switch (record.type) {
      case ActivityRecordType.course:
        icon = Icons.school_rounded;
        typeLabel = 'Course';
        break;
      case ActivityRecordType.lecture:
        icon = Icons.mic_rounded;
        typeLabel = 'Lecture';
        break;
      case ActivityRecordType.announcement:
        icon = Icons.campaign_rounded;
        typeLabel = 'Announcement';
        break;
      default:
        icon = Icons.delete_rounded;
        typeLabel = 'Item';
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
                  'Deleted on ${DateFormat('MMM d, yyyy').format(record.dateTime)} · $typeLabel',
                  style: TextStyle(
                    color: AppColors.universe.textComet,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Restore Button
          IconButton(
            icon: const Icon(Icons.settings_backup_restore_rounded, color: AppColors.starGold),
            tooltip: 'Restore $typeLabel',
            onPressed: () => _restoreTrashItem(context, ref, record),
          ),
        ],
      ),
    );
  }

  bool _isSavedRecord(ActivityRecord record) {
    if (record.type == ActivityRecordType.reviewCard) {
      final card = record.rawData as LocalReviewCard;
      final metadata = card.metadataJson != null
          ? Map<String, dynamic>.from(jsonDecode(card.metadataJson!) as Map)
          : null;
      return metadata?['saved'] == true;
    } else if (record.type == ActivityRecordType.deepNote) {
      final note = record.rawData as LocalDeepNote;
      final metadata = note.metadataJson != null
          ? Map<String, dynamic>.from(jsonDecode(note.metadataJson!) as Map)
          : null;
      return metadata?['saved'] == true;
    }
    return false;
  }

  String? _getReactionRecord(ActivityRecord record) {
    if (record.type == ActivityRecordType.reviewCard) {
      final card = record.rawData as LocalReviewCard;
      final metadata = card.metadataJson != null
          ? Map<String, dynamic>.from(jsonDecode(card.metadataJson!) as Map)
          : null;
      return metadata?['reaction'] as String?;
    } else if (record.type == ActivityRecordType.deepNote) {
      final note = record.rawData as LocalDeepNote;
      final metadata = note.metadataJson != null
          ? Map<String, dynamic>.from(jsonDecode(note.metadataJson!) as Map)
          : null;
      return metadata?['reaction'] as String?;
    } else if (record.type == ActivityRecordType.funFact) {
      final fact = record.rawData as LocalFunFact;
      return fact.reaction;
    }
    return null;
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
    if (record.type == ActivityRecordType.reviewCard) {
      await ref.read(reviewCardRepositoryDriftProvider).updateSaved(id: record.id, saved: save);
    } else if (record.type == ActivityRecordType.deepNote) {
      await ref.read(deepNoteRepositoryDriftProvider).updateSaved(id: record.id, saved: save);
    }
    ref.read(lectureControllerProvider.notifier).pushOutboxNow();
  }

  Future<void> _restoreTrashItem(BuildContext context, WidgetRef ref, ActivityRecord record) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final db = ref.read(appDatabaseProvider);

      if (record.type == ActivityRecordType.course) {
        // Restore course in Supabase
        await supabase.from('courses').update({'deleted_at': null}).eq('id', record.id);
        // Force refresh deleted courses list
        ref.invalidate(deletedCoursesFutureProvider);
      } else if (record.type == ActivityRecordType.lecture) {
        // Restore local lecture
        await (db.update(db.localLectures)..where((t) => t.id.equals(record.id))).write(
          LocalLecturesCompanion(
            deletedAt: const Value(null),
            syncStatus: const Value('needs_sync'),
            updatedAt: Value(DateTime.now()),
          ),
        );
        // Queue outbox sync
        await db.enqueueOutbox(entityType: 'lecture', entityId: record.id, op: 'update');
        ref.read(lectureControllerProvider.notifier).pushOutboxNow();
      } else if (record.type == ActivityRecordType.announcement) {
        // Restore local announcement
        await (db.update(db.localAnnouncements)..where((t) => t.id.equals(record.id))).write(
          LocalAnnouncementsCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(DateTime.now()),
          ),
        );
        // Queue outbox sync
        await db.enqueueOutbox(entityType: 'announcement', entityId: record.id, op: 'update');
        ref.read(lectureControllerProvider.notifier).pushOutboxNow();
      }

      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Item restored successfully.'),
          backgroundColor: AppColors.growthGreen,
        ),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to restore item: $e'),
          backgroundColor: AppColors.correctionRed,
        ),
      );
    }
  }

  void _confirmEmptyTrash(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.universe.voidBackground,
          title: const Text(
            'Empty Trash?',
            style: TextStyle(color: Color(0xFFF2F2F2)),
          ),
          content: const Text(
            'All soft-deleted lectures, courses, and announcements will be permanently deleted from both the local database and the cloud. This action cannot be undone.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                final scaffold = ScaffoldMessenger.of(context);
                try {
                  await TrashController.emptyTrash(ref);
                  scaffold.showSnackBar(
                    const SnackBar(
                      content: Text('Trash emptied successfully.'),
                      backgroundColor: AppColors.growthGreen,
                    ),
                  );
                } catch (e) {
                  scaffold.showSnackBar(
                    SnackBar(
                      content: Text('Failed to empty trash: $e'),
                      backgroundColor: AppColors.correctionRed,
                    ),
                  );
                }
              },
              child: const Text('Empty Trash', style: TextStyle(color: AppColors.correctionRed)),
            ),
          ],
        );
      },
    );
  }
}
