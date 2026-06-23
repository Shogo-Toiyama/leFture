import 'dart:convert';
import 'dart:developer' as dev;
import 'package:drift/drift.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart'; // supabaseインスタンス

class LectureSyncService {
  final AppDatabase _db;

  LectureSyncService(this._db);

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
        // 論理削除なら update is_deleted = true
        // 物理削除なら delete
        // ここでは論理削除（is_deletedフラグ）を想定して payload に is_deleted: true が入っているなら upsert
        await supabase.from('lectures').upsert(payload);
        break;
        
      default:
        dev.log('Unknown op: ${row.op}');
    }
  }

  /// ---------------------------------------------------------
  /// 2. Pull: Supabaseから変更分を取得してローカルDBへ
  /// ---------------------------------------------------------
  Future<void> pull({DateTime? lastPullAt}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    // クエリ構築
    var query = supabase.from('lectures').select().eq('user_id', uid);

    // 差分更新: 前回同期時刻があれば、それ以降に更新されたものだけ取得
    if (lastPullAt != null) {
      query = query.gt('updated_at', lastPullAt.toIso8601String());
    }

    final List<dynamic> data = await query;
    if (data.isEmpty) return;

    // ローカルDBへUpsertするためのデータ変換
    final companions = data.map((json) {
      return LocalLecturesCompanion(
        id: Value(json['id'] as String),
        userId: Value(json['user_id'] as String),
        courseId: Value(json['course_id'] as String?),
        title: Value(json['title'] as String?),
        lectureDatetime: Value(DateTime.tryParse(json['lecture_datetime'] ?? '')),
        sortOrder: Value(json['sort_order'] as int?),
        createdAt: Value(DateTime.parse(json['created_at'])),
        updatedAt: Value(DateTime.parse(json['updated_at'])),
        deletedAt: json['is_deleted'] == true 
            ? Value(DateTime.now()) // deletedフラグがtrueならdeletedAtを入れる
            : const Value(null),
        syncStatus: const Value('synced'), // 同期直後なのでsynced
      );
    }).toList();

    // Batch Insert (Drift)
    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(_db.localLectures, companions);
    });
    
    dev.log('📥 Pulled ${companions.length} lectures from cloud.');
  }
}