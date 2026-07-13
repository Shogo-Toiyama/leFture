import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lecture_companion_ui/core/utils/dev_log.dart';
import 'package:lecture_companion_ui/core/utils/network_constants.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

/// TopicMapのPull(Supabase→ローカルDB)専用サービス。書き込み(markStale/
/// reconstruct)は依然Supabase/Cloud Run直接なので、Outbox/Push側の対応は
/// 不要。[LectureSyncService]と同型の差分Pull(`updated_at`基準+24時間
/// 全件Pullセーフティネット)。
class TopicMapSyncService {
  final AppDatabase _db;

  TopicMapSyncService(this._db);

  static const _entityType = 'topic_map';
  static const _fullPullSafetyNet = Duration(hours: 24);

  Future<void> pull({bool forceFullPull = false}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final cursor = await _db.getSyncCursor(uid, _entityType);
    final now = DateTime.now().toUtc();

    final needsFullPull = forceFullPull ||
        cursor?.lastFullPulledAt == null ||
        now.difference(cursor!.lastFullPulledAt!) >= _fullPullSafetyNet;

    final localCount = await (_db.select(_db.localTopicMaps)
          ..where((t) => t.userId.equals(uid)))
        .get()
        .then((rows) => rows.length);
    final effectiveLastPullAt =
        (needsFullPull || localCount == 0) ? null : cursor.lastPulledAt;

    var query = supabase.from('topic_maps').select().eq('user_id', uid);
    if (effectiveLastPullAt != null) {
      final skewBuffer = effectiveLastPullAt.subtract(const Duration(minutes: 5));
      query = query.gt('updated_at', skewBuffer.toIso8601String());
    }

    final List<dynamic> data = await query.timeout(networkTimeout);

    DateTime? maxUpdatedAt = cursor?.lastPulledAt;
    if (data.isNotEmpty) {
      final companions = data.map((json) {
        final updatedAt = DateTime.parse(json['updated_at']);
        if (maxUpdatedAt == null || updatedAt.isAfter(maxUpdatedAt!)) {
          maxUpdatedAt = updatedAt;
        }
        final map = json['map'] as Map<String, dynamic>?;
        return LocalTopicMapsCompanion(
          courseId: Value(json['course_id'] as String),
          userId: Value(json['user_id'] as String),
          mapJson: Value(jsonEncode(map ?? const {})),
          isStale: Value(json['is_stale'] as bool? ?? false),
          updatedAt: Value(updatedAt),
          lastSyncedAt: Value(now),
        );
      }).toList();

      await _db.batch((batch) {
        batch.insertAllOnConflictUpdate(_db.localTopicMaps, companions);
      });

      DevLog.add('📥 [TopicMapSync] Pulled ${companions.length} topic map(s) from cloud.');
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
