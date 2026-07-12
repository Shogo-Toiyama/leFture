import 'package:lecture_companion_ui/application/sync/outbox_sync_service.dart';
import 'package:lecture_companion_ui/core/utils/network_constants.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

/// Announcementはサーバー生成コンテンツで、クライアントから新規作成される
/// ことはない。ユーザーが変更できるのは`completed_at`だけなので、
/// upsertではなく`update`のみを行う(NOT NULL制約に引っかかるINSERT経路が
/// そもそも発生しない設計)。`updated_at`はSupabase側の自動更新トリガーに
/// 一任するため送らない。
class AnnouncementOutboxPushHandler implements OutboxPushHandler {
  @override
  String get entityType => 'announcement';

  @override
  Future<void> push(AppDatabase db, String entityId) async {
    final existing = await (db.select(db.localAnnouncements)
          ..where((t) => t.id.equals(entityId)))
        .getSingleOrNull();
    if (existing == null) return;

    await supabase
        .from('announcements')
        .update({'completed_at': existing.completedAt?.toUtc().toIso8601String()})
        .eq('id', entityId)
        .timeout(networkTimeout);
  }
}
