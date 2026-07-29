import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/core/utils/network_constants.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

/// AnnouncementのPull(Supabase→ローカルDB)専用サービス。
/// [LectureSyncService]と同型の差分Pull(`updated_at`基準+24時間全件Pull
/// セーフティネット)。
class AnnouncementSyncService {
  final AppDatabase _db;

  AnnouncementSyncService(this._db);

  static const _entityType = 'announcement';
  static const _fullPullSafetyNet = Duration(hours: 24);

  Future<void> pull({bool forceFullPull = false}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final cursor = await _db.getSyncCursor(uid, _entityType);
    final now = DateTime.now().toUtc();

    final needsFullPull = forceFullPull ||
        cursor?.lastFullPulledAt == null ||
        now.difference(cursor!.lastFullPulledAt!) >= _fullPullSafetyNet;

    final localCount = await (_db.select(_db.localAnnouncements)
          ..where((t) => t.userId.equals(uid) & t.deletedAt.isNull()))
        .get()
        .then((rows) => rows.length);
    final effectiveLastPullAt =
        (needsFullPull || localCount == 0) ? null : cursor.lastPulledAt;

    var query = supabase.from('announcements').select().eq('user_id', uid);
    if (effectiveLastPullAt != null) {
      final skewBuffer = effectiveLastPullAt.subtract(const Duration(minutes: 5));
      query = query.gt('updated_at', skewBuffer.toIso8601String());
    }

    final List<dynamic> data = await query.timeout(networkTimeout);

    DateTime? maxUpdatedAt = cursor?.lastPulledAt;
    if (data.isNotEmpty) {
      // まだPushできていないローカルのcompleted_at変更を、サーバーの古い値で
      // 上書きしないためのガード。
      final pendingIds = await _db.getPendingOutboxEntityIds(_entityType);

      final companions = data.map((json) {
        final updatedAt = DateTime.parse(json['updated_at']);
        if (maxUpdatedAt == null || updatedAt.isAfter(maxUpdatedAt!)) {
          maxUpdatedAt = updatedAt;
        }

        final id = json['id'] as String;
        final isPending = pendingIds.contains(id);
        final metadata = json['metadata'] != null
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : null;
        final datetimeParameters = json['datetime_parameters'] != null
            ? Map<String, dynamic>.from(json['datetime_parameters'] as Map)
            : null;

        return LocalAnnouncementsCompanion(
          id: Value(id),
          userId: Value(json['user_id'] as String),
          lectureId: Value(json['lecture_id'] as String),
          type: Value(json['type'] as String? ?? 'INFO'),
          title: Value(json['title'] as String? ?? ''),
          description: Value(json['description'] as String?),
          location: Value(json['location'] as String?),
          startSid: Value(json['start_sid'] as String?),
          endSid: Value(json['end_sid'] as String?),
          relatedTopicTitle: Value(json['related_topic_title'] as String?),
          datetimeParametersJson:
              Value(datetimeParameters != null ? jsonEncode(datetimeParameters) : null),
          // ローカルに未Pushの変更が無い場合のみサーバー値で上書きする
          completedAt: isPending
              ? const Value.absent()
              : Value(json['completed_at'] == null
                  ? null
                  : DateTime.parse(json['completed_at'] as String)),
          metadataJson: Value(metadata != null ? jsonEncode(metadata) : null),
          createdAt: Value(DateTime.parse(json['created_at'])),
          updatedAt: Value(updatedAt),
          deletedAt: Value(
            json['deleted_at'] == null ? null : DateTime.parse(json['deleted_at'] as String),
          ),
          syncStatus: const Value('synced'),
        );
      }).toList();

      await _db.batch((batch) {
        batch.insertAllOnConflictUpdate(_db.localAnnouncements, companions);
      });

      DevLog.add('📥 [AnnouncementSync] Pulled ${companions.length} announcement(s) from cloud.');
    }

    await _db.upsertSyncCursor(
      userId: uid,
      entityType: _entityType,
      lastPulledAt: maxUpdatedAt,
      updateLastFullPulledAt: needsFullPull,
      lastFullPulledAt: needsFullPull ? now : null,
    );
  }
}
