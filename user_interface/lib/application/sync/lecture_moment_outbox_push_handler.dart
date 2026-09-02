import 'package:drift/drift.dart';

import 'package:lefture/application/sync/lecture_outbox_push_handler.dart';
import 'package:lefture/application/sync/outbox_sync_service.dart';
import 'package:lefture/core/utils/network_constants.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

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

    // Outboxはユーザー単位に分かれていない一方、ローカルDBはサインアウトでも
    // 消えないため、アカウントを切り替えると「前のアカウントの行」を今の
    // セッションでpushしようとしてしまう(RLS違反や、前のアカウントごと削除
    // されている場合はFK違反になる)。現在のユーザーの行だけを送る。
    // ※uidがnull(トークン更新中など)のときは判定せず、通常の失敗→リトライに任せる。
    final uid = supabase.auth.currentUser?.id;
    if (uid != null && existing.userId != uid) return;

    // チュートリアル講義配下のモーメントはローカル完結のためpushしない
    if (await db.isTutorialLecture(existing.lectureId)) return;

    // 親講義がローカルから消えている/論理削除済みなら、pushしても
    // `lecture_moments_lecture_id_fkey`のFK違反(23503)になるだけなので送らない。
    //
    // 録音をDiscardした(=一度もSupabaseに登録されないまま削除された)講義では、
    // 講義側のpushは「Supabase側に無いなら送るものが無い」と判断して成功扱いで
    // Outboxから消える(lecture_outbox_push_handler.dart参照)。一方その録音中に
    // 押されたリアクション/メモのOutbox行はそのまま残るため、この判定が無いと
    // 存在しない親を参照し続け、givenUpになるまで(最大10回)毎回の同期で
    // FK違反を出し続けていた。
    final lecture = await (db.select(db.localLectures)
          ..where((t) => t.id.equals(existing.lectureId) & t.userId.equals(existing.userId)))
        .getSingleOrNull();
    if (lecture == null || lecture.deletedAt != null) return;

    // ★ 親講義がローカルには存在していても、サーバー側にまだ1行も無い
    // ケースがある(この講義自身のOutbox行がまだpushされていない/直前の
    // 失敗でバックオフ待ちになっている等)。その状態でこのMomentだけ先に
    // pushされると`lecture_moments_lecture_id_fkey`のFK違反(23503)になる
    // (録音中にリアクションを押した直後の即時push経路で実際に発生した)。
    // LectureOutboxPushHandler.pushはSupabase側の最新行から都度組み立てる
    // 冪等なupsertなので、念のため先に実行しておいても無害 — 既に同期済み
    // なら無駄なupsertが1回増えるだけで済む。
    await LectureOutboxPushHandler().push(db, existing.lectureId);

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
