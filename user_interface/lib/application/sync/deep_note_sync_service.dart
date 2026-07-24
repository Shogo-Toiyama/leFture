import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/core/utils/network_constants.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

/// DeepNoteのPull(Supabase→ローカルDB)専用サービス。ユーザーによる書き込みが
/// 無い読み取り専用キャッシュなので、Outbox/Push側の対応は不要。
/// [LectureSyncService]と同型の差分Pull(`updated_at`基準+24時間全件Pull
/// セーフティネット)。
class DeepNoteSyncService {
  final AppDatabase _db;

  DeepNoteSyncService(this._db);

  static const _entityType = 'deep_note';
  static const _fullPullSafetyNet = Duration(hours: 24);

  Future<void> pull({bool forceFullPull = false}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final cursor = await _db.getSyncCursor(uid, _entityType);
    final now = DateTime.now().toUtc();

    final needsFullPull = forceFullPull ||
        cursor?.lastFullPulledAt == null ||
        now.difference(cursor!.lastFullPulledAt!) >= _fullPullSafetyNet;

    final localCount = await (_db.select(_db.localDeepNotes)
          ..where((t) => t.userId.equals(uid) & t.deletedAt.isNull()))
        .get()
        .then((rows) => rows.length);
    final effectiveLastPullAt =
        (needsFullPull || localCount == 0) ? null : cursor.lastPulledAt;

    var query = supabase.from('deep_notes').select().eq('user_id', uid);
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
        return LocalDeepNotesCompanion(
          id: Value(json['id'] as String),
          userId: Value(json['user_id'] as String),
          lectureId: Value(json['lecture_id'] as String),
          topicNumber: Value((json['topic_number'] as num?)?.toInt() ?? 0),
          noteContents: Value(json['note_contents'] as String? ?? ''),
          metadataJson: Value(
            json['metadata'] != null ? jsonEncode(json['metadata']) : null,
          ),
          createdAt: Value(DateTime.parse(json['created_at'])),
          updatedAt: Value(updatedAt),
          deletedAt: Value(
            json['deleted_at'] == null ? null : DateTime.parse(json['deleted_at'] as String),
          ),
          lastSyncedAt: Value(now),
        );
      }).toList();

      await _db.batch((batch) {
        batch.insertAllOnConflictUpdate(_db.localDeepNotes, companions);
      });

      DevLog.add('📥 [DeepNoteSync] Pulled ${companions.length} deep note(s) from cloud.');
    }

    await _db.upsertSyncCursor(
      userId: uid,
      entityType: _entityType,
      lastPulledAt: maxUpdatedAt,
      updateLastFullPulledAt: needsFullPull,
      lastFullPulledAt: needsFullPull ? now : null,
    );
  }

  /// 特定の講義1件分だけをSupabaseから無条件Pullする。ローカルキャッシュの
  /// 容量上限([LocalRetentionService.enforceCacheBudget])によってその講義の
  /// 行が削除された後、講義ページを開いた際に復元するための経路。
  /// 通常の[pull]と違い、`updated_at`での差分判定やsyncカーソルの更新は
  /// 行わない(全体同期のカーソルを狂わせないため)。
  Future<void> pullForLecture(String lectureId) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final now = DateTime.now().toUtc();
    final List<dynamic> data = await supabase
        .from('deep_notes')
        .select()
        .eq('user_id', uid)
        .eq('lecture_id', lectureId)
        .timeout(networkTimeout);

    if (data.isEmpty) return;

    final companions = data.map((json) {
      return LocalDeepNotesCompanion(
        id: Value(json['id'] as String),
        userId: Value(json['user_id'] as String),
        lectureId: Value(json['lecture_id'] as String),
        topicNumber: Value((json['topic_number'] as num?)?.toInt() ?? 0),
        noteContents: Value(json['note_contents'] as String? ?? ''),
        metadataJson: Value(
          json['metadata'] != null ? jsonEncode(json['metadata']) : null,
        ),
        createdAt: Value(DateTime.parse(json['created_at'])),
        updatedAt: Value(DateTime.parse(json['updated_at'])),
        deletedAt: Value(
          json['deleted_at'] == null ? null : DateTime.parse(json['deleted_at'] as String),
        ),
        lastSyncedAt: Value(now),
      );
    }).toList();

    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(_db.localDeepNotes, companions);
    });

    DevLog.add('📥 [DeepNoteSync] Restored ${companions.length} deep note(s) for lecture $lectureId.');
  }
}
