import 'package:lecture_companion_ui/core/utils/dev_log.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';

/// entityType(例: "lecture", "fun_fact", "announcement")ごとの、Outbox 1行を
/// 実際にSupabaseへ反映する処理。[push]は必ず[entityId]で対応するLocal*
/// テーブルの最新行を読み直してpayloadを組み立てること — Outbox行自体は
/// 書き込み時点のスナップショットを持たないため、payload構築ロジックの
/// バグを直すコードをリリースするだけで、既存の保留中Outbox行も次回の
/// pushで自動的に正しい内容で再送されるようになる(再インストール不要)。
abstract class OutboxPushHandler {
  String get entityType;

  Future<void> push(AppDatabase db, String entityId);
}

/// entityTypeごとに登録された[OutboxPushHandler]へディスパッチする、
/// 汎用的なOutbox送信処理。
class OutboxSyncService {
  OutboxSyncService(this._db, this._handlers);

  final AppDatabase _db;
  final Map<String, OutboxPushHandler> _handlers;

  Future<void> pushAll() async {
    final rows = await _db.dequeuePendingOutbox();
    if (rows.isEmpty) return;

    DevLog.add('📤 [Outbox] Pushing ${rows.length} pending item(s)...');

    for (final row in rows) {
      final handler = _handlers[row.entityType];
      if (handler == null) {
        DevLog.add('⚠️ [Outbox] No handler registered for entityType=${row.entityType} (outbox #${row.id})');
        await _db.recordOutboxFailure(row.id, 'No handler registered for entityType ${row.entityType}');
        continue;
      }

      try {
        await handler.push(_db, row.entityId);
        await _db.deleteOutboxIds([row.id]);
        DevLog.add('✅ [Outbox] Pushed #${row.id} (entityType=${row.entityType}, entity=${row.entityId})');
      } catch (e) {
        await _db.recordOutboxFailure(row.id, e.toString());
        DevLog.add('❌ [Outbox] Failed to push #${row.id} (entityType=${row.entityType}, entity=${row.entityId}): $e');
      }
    }
  }
}
