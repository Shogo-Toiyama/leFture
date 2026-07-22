import 'package:drift/drift.dart' show Value;
import 'package:lecture_companion_ui/application/sync/outbox_sync_service.dart';
import 'package:lecture_companion_ui/core/utils/network_constants.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/topic_map_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

/// pushの瞬間に[LocalLectures]の最新行を読み直し、Supabaseの`lectures`
/// テーブルへ全カラムでupsertする。まだ一度もサーバーに存在しない講義
/// (アップロード完了前に削除された等)でもINSERTのNOT NULL制約に
/// 引っかからないよう、常に必要なカラムを揃えて送る。
/// `updated_at`はSupabase側の自動更新トリガーに一任するため送らない。
///
/// あわせて、削除/Course間移動によるTopic Mapのstale化(mark-stale)も
/// このpushの一部として送信する。これによりLectureの永続化(lecture行の
/// upsert)とstale化通知が同じOutboxリトライ(バックオフ・最大10回)に乗り、
/// 「Lectureは削除されたのにis_staleが立たない」という穴を無くす。
/// stale化の送信が失敗した場合はこのpush全体を失敗させ、次回リトライで
/// lecture行のupsert(冪等)ごとやり直す — mark-stale自体もバックエンド側で
/// 同一lecture_idの重複追加を弾くため、再送は安全。
class LectureOutboxPushHandler implements OutboxPushHandler {
  LectureOutboxPushHandler({TopicMapRepositorySupabase? topicMapRepository})
      : _topicMapRepository = topicMapRepository ?? TopicMapRepositorySupabase();

  final TopicMapRepositorySupabase _topicMapRepository;

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
      'recording_language': existing.recordingLanguage,
      'display_language': existing.displayLanguage,
    };

    await supabase.from('lectures').upsert(payload).timeout(networkTimeout);

    // 削除: courseIdが残っている(=所属コースがあった)場合のみ、そのTopic Mapを
    // stale化する。backend側はlecture_idの重複追加を弾くので、リトライで
    // 複数回呼ばれても安全。
    if (existing.deletedAt != null && existing.courseId != null) {
      await _topicMapRepository.markStale(
        courseId: existing.courseId!,
        lectureId: entityId,
        action: 'remove',
      );
    }

    // Course間移動: 移動元(pendingTopicMapStaleCourseId)と移動先(現在のcourseId)
    // それぞれのTopic Mapをstale化してから、フラグを下ろす。
    if (existing.topicMapMovePending) {
      final oldCourseId = existing.pendingTopicMapStaleCourseId;
      final newCourseId = existing.courseId;

      await Future.wait([
        if (oldCourseId != null)
          _topicMapRepository.markStale(
            courseId: oldCourseId,
            lectureId: entityId,
            action: 'remove',
          ),
        if (newCourseId != null)
          _topicMapRepository.markStale(
            courseId: newCourseId,
            lectureId: entityId,
            action: 'add',
          ),
      ]);

      await (db.update(db.localLectures)..where((t) => t.id.equals(entityId))).write(
        const LocalLecturesCompanion(
          topicMapMovePending: Value(false),
          pendingTopicMapStaleCourseId: Value(null),
        ),
      );
    }
  }
}
