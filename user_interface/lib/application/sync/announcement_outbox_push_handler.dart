import 'package:lefture/application/sync/outbox_sync_service.dart';
import 'package:lefture/core/utils/network_constants.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

/// Announcementはサーバー生成コンテンツ。ユーザーが変更できるのは
/// `completed_at`・`deleted_at`・`title`・`description`・`type`のみ。
/// `updated_at`はSupabase側の自動更新トリガーに任せるため送らない。
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
        .update({
          'completed_at': existing.completedAt?.toUtc().toIso8601String(),
          'deleted_at': existing.deletedAt?.toUtc().toIso8601String(),
          'title': existing.title,
          'description': existing.description,
          'type': existing.type,
        })
        .eq('id', entityId)
        .timeout(networkTimeout);
  }
}
