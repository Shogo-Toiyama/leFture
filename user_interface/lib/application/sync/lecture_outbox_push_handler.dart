import 'package:lecture_companion_ui/application/sync/outbox_sync_service.dart';
import 'package:lecture_companion_ui/core/utils/network_constants.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

/// pushの瞬間に[LocalLectures]の最新行を読み直し、Supabaseの`lectures`
/// テーブルへ全カラムでupsertする。まだ一度もサーバーに存在しない講義
/// (アップロード完了前に削除された等)でもINSERTのNOT NULL制約に
/// 引っかからないよう、常に必要なカラムを揃えて送る。
/// `updated_at`はSupabase側の自動更新トリガーに一任するため送らない。
class LectureOutboxPushHandler implements OutboxPushHandler {
  @override
  String get entityType => 'lecture';

  @override
  Future<void> push(AppDatabase db, String entityId) async {
    final existing = await (db.select(db.localLectures)
          ..where((t) => t.id.equals(entityId)))
        .getSingleOrNull();
    // ローカルにもう存在しない(何らかの理由で消えた) -> 送るものが無い
    if (existing == null) return;

    final payload = {
      'id': existing.id,
      'user_id': existing.userId,
      'course_id': existing.courseId,
      'title': existing.title,
      'title_generated': existing.titleGenerated,
      'lecture_datetime':
          (existing.lectureDatetime ?? existing.createdAt).toUtc().toIso8601String(),
      'sort_order': existing.sortOrder ?? 0,
      'created_at': existing.createdAt.toUtc().toIso8601String(),
      'deleted_at': existing.deletedAt?.toUtc().toIso8601String(),
    };

    await supabase.from('lectures').upsert(payload).timeout(networkTimeout);
  }
}
