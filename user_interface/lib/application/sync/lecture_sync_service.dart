import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/core/utils/network_constants.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart'; // supabaseインスタンス

/// 講義のPull(Supabase→ローカルDB)専用のサービス。Push(Outboxの送信)は
/// [OutboxSyncService]/[LectureOutboxPushHandler]に統合されている
/// (書き込み時に固定されたpayloadではなく、push実行時に最新のローカル行
/// から再構築する自己修復設計のため)。
class LectureSyncService {
  final AppDatabase _db;

  LectureSyncService(this._db);

  static const _entityType = 'lecture';

  /// 差分Pullが穴を持っていても、この間隔ごとに全件Pullで必ず回収する
  /// セーフティネット(コミット可視性ラグ・レプリケーション遅延・端末時計の
  /// 大幅なズレなどで差分Pullのカーソルが恒久的に取り残すリスクへの対策)。
  static const _fullPullSafetyNet = Duration(hours: 24);

  /// ---------------------------------------------------------
  /// Pull: Supabaseから変更分を取得してローカルDBへ
  /// ---------------------------------------------------------
  ///
  /// カーソルは「クライアントのwall-clock」ではなく「実際に取得した行の
  /// 最大updated_at」を使う。コミット可視性ラグ等でこのカーソルが行を
  /// 取り残しても、[_fullPullSafetyNet]間隔で必ず全件Pullに切り替わるため
  /// 恒久的なロストにはならない。
  Future<void> pull({bool forceFullPull = false}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final cursor = await _db.getSyncCursor(uid, _entityType);
    final now = DateTime.now().toUtc();

    final needsFullPull = forceFullPull ||
        cursor?.lastFullPulledAt == null ||
        now.difference(cursor!.lastFullPulledAt!) >= _fullPullSafetyNet;

    final localCount = await _db.getLocalLecturesCount(uid);
    final effectiveLastPullAt =
        (needsFullPull || localCount == 0) ? null : cursor.lastPulledAt;

    // クエリ構築
    var query = supabase.from('lectures').select().eq('user_id', uid);

    if (effectiveLastPullAt != null) {
      // 5分間のバッファを差し引くことで、端末とサーバーの時計のズレや
      // 短時間のコミット可視性ラグによる同期漏れを緩和する
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
        final metadata = json['metadata'] as Map<String, dynamic>?;
        return LocalLecturesCompanion(
          id: Value(json['id'] as String),
          userId: Value(json['user_id'] as String),
          courseId: Value(json['course_id'] as String?),
          title: Value(json['title'] as String?),
          titleGenerated: Value(json['title_generated'] as String?),
          summary: Value(json['summary'] as String?),
          audioPath: Value(json['audio_path'] as String?),
          metadataJson: Value(metadata != null ? jsonEncode(metadata) : null),
          lectureDatetime: Value(DateTime.tryParse(json['lecture_datetime'] ?? '')),
          sortOrder: Value(json['sort_order'] as int?),
          recordingLanguage: Value(json['recording_language'] as String?),
          displayLanguage: Value(json['display_language'] as String?),
          createdAt: Value(DateTime.parse(json['created_at'])),
          updatedAt: Value(updatedAt),
          deletedAt: Value(
            json['deleted_at'] == null ? null : DateTime.parse(json['deleted_at'] as String),
          ),
          syncStatus: const Value('synced'), // 同期直後なのでsynced
        );
      }).toList();

      await _db.batch((batch) {
        batch.insertAllOnConflictUpdate(_db.localLectures, companions);
      });

      DevLog.add('📥 [LectureSync] Pulled ${companions.length} lecture(s) from cloud.');
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