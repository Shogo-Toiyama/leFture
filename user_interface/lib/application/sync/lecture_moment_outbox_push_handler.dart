import 'package:lecture_companion_ui/application/sync/outbox_sync_service.dart';
import 'package:lecture_companion_ui/core/utils/network_constants.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

/// pushの瞬間に[LocalLectureMoments]の最新行を読み直し、Supabaseの
/// `lecture_moments`テーブルへupsertする。クライアント発の新規行(録音中の
/// リアクション/メモ)なので、id自体をクライアントで発行しupsertする点は
/// [LectureOutboxPushHandler]と同じ形。ソフトデリート(deletedAtセット)も
/// 同じ行の更新として同じpushで運ばれる。
class LectureMomentOutboxPushHandler implements OutboxPushHandler {
  @override
  String get entityType => 'lecture_moment';

  @override
  Future<void> push(AppDatabase db, String entityId) async {
    final existing = await (db.select(db.localLectureMoments)
          ..where((t) => t.id.equals(entityId)))
        .getSingleOrNull();
    // ローカルにもう存在しない -> 送るものが無い
    if (existing == null) return;

    final payload = {
      'id': existing.id,
      'user_id': existing.userId,
      'lecture_id': existing.lectureId,
      'moment_type': existing.momentType,
      'note_text': existing.noteText,
      'timestamp_sec': existing.timestampSec,
      'created_at': existing.createdAt.toUtc().toIso8601String(),
      'updated_at': existing.updatedAt.toUtc().toIso8601String(),
      'deleted_at': existing.deletedAt?.toUtc().toIso8601String(),
    };

    await supabase.from('lecture_moments').upsert(payload).timeout(networkTimeout);
  }
}
