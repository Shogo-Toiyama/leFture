import 'dart:convert';
import 'dart:developer' as dev;
import 'package:drift/drift.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart'; // supabaseインスタンス

class LectureSyncService {
  final AppDatabase _db;

  LectureSyncService(this._db);

  static const _entityType = 'lecture';

  /// 差分Pullが穴を持っていても、この間隔ごとに全件Pullで必ず回収する
  /// セーフティネット(コミット可視性ラグ・レプリケーション遅延・端末時計の
  /// 大幅なズレなどで差分Pullのカーソルが恒久的に取り残すリスクへの対策)。
  static const _fullPullSafetyNet = Duration(hours: 24);

  /// ---------------------------------------------------------
  /// 1. Push: ローカルの未送信変更 (Outbox) をSupabaseへ送る
  /// ---------------------------------------------------------
  Future<void> pushOutbox() async {
    // lectureに関連するOutboxのみ取得するクエリが必要ですが、
    // 汎用的にdequeueBatchで取ってきて、entityTypeでフィルタしてもOKです。
    // ここではシンプルに「未処理のOutboxを順次処理」するイメージで書きます。
    
    // ※ 実際には app_database.dart に getOutboxByEntityType などがあると効率的ですが
    // 一旦 dequeueBatch で全件取ってフィルタします。
    final rows = await _db.dequeueBatch(); 
    
    for (final row in rows) {
      if (row.entityType != 'lecture') continue;

      try {
        await _processOutboxItem(row);
        // 成功したら削除
        await _db.deleteOutboxIds([row.id]);
      } catch (e) {
        dev.log('Failed to process outbox item ${row.id}: $e');
        // エラー時は削除せず、次回のRetryに任せる（必要ならRetryCountを増やすなど）
      }
    }
  }

  Future<void> _processOutboxItem(LocalOutboxData row) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;

    switch (row.op) {
      case 'create':
      case 'update':
        // SupabaseへUpsert
        await supabase.from('lectures').upsert(payload);
        break;
      
      case 'delete':
        // 論理削除。payload に deleted_at (ISO8601) が入っている想定でupsert
        await supabase.from('lectures').upsert(payload);
        break;
        
      default:
        dev.log('Unknown op: ${row.op}');
    }
  }

  /// ---------------------------------------------------------
  /// 2. Pull: Supabaseから変更分を取得してローカルDBへ
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

    final List<dynamic> data = await query;

    DateTime? maxUpdatedAt = cursor?.lastPulledAt;
    if (data.isNotEmpty) {
      final companions = data.map((json) {
        final updatedAt = DateTime.parse(json['updated_at']);
        if (maxUpdatedAt == null || updatedAt.isAfter(maxUpdatedAt!)) {
          maxUpdatedAt = updatedAt;
        }
        return LocalLecturesCompanion(
          id: Value(json['id'] as String),
          userId: Value(json['user_id'] as String),
          courseId: Value(json['course_id'] as String?),
          title: Value(json['title'] as String?),
          titleGenerated: Value(json['title_generated'] as String?),
          lectureDatetime: Value(DateTime.tryParse(json['lecture_datetime'] ?? '')),
          sortOrder: Value(json['sort_order'] as int?),
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

      dev.log('📥 Pulled ${companions.length} lectures from cloud.');
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