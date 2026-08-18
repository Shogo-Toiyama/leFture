import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/core/utils/network_constants.dart';
import 'package:lefture/domain/entities/lecture.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

class LectureRepositoryDrift {
  final AppDatabase _db;

  LectureRepositoryDrift(this._db);

  Stream<List<Lecture>> watchLectures({
    required String userId,
    required String? courseId,
  }) {
    return _db.watchLectures(userId, courseId).map((rows) {
      return rows.map((row) => _toDomain(row)).toList();
    });
  }

  /// コースの有無に関わらず、ユーザーの全レクチャーを横断して監視する。
  Stream<List<Lecture>> watchAllLectures({required String userId}) {
    return _db.watchAllLectures(userId).map((rows) {
      return rows.map((row) => _toDomain(row)).toList();
    });
  }

  /// 講義詳細ページ用。単一講義をIDで監視する。
  Stream<Lecture?> watchLectureById(String lectureId) {
    return _db.watchLectureById(lectureId).map((row) => row == null ? null : _toDomain(row));
  }

  /// 論理削除を実行し、Outboxに登録する (Transaction)
  ///
  /// Outboxへは「entityId」だけを登録する。実際にSupabaseへ送るpayloadは
  /// [LectureOutboxPushHandler]がpush実行時に[LocalLectures]の最新行から
  /// 都度組み立てる(自己修復設計 — payload構築ロジックのバグを直すコードを
  /// リリースするだけで、既存の保留中Outbox行も次回のpushで自動的に正しい
  /// 内容で再送されるようにするため)。
  Future<void> softDeleteLecture({required String lectureId}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final now = DateTime.now();

    await _db.transaction(() async {
      // 1. ローカルDBで論理削除
      await (_db.update(_db.localLectures)
            ..where((t) => t.id.equals(lectureId)))
          .write(LocalLecturesCompanion(
        deletedAt: Value(now),
        syncStatus: const Value('needs_sync'), // テキスト型に合わせて修正
        updatedAt: Value(now),
      ));

      // 2. Outboxに登録
      if (await _db.isTutorialLecture(lectureId)) {
        return; // チュートリアル講義のデータはOutboxに入れない
      }

      await _db.enqueueOutbox(
        entityType: 'lecture',
        entityId: lectureId,
        op: 'update', // 論理削除なので update 扱い
      );
    });
  }

  /// 講義をローカルDBおよびSupabaseから物理削除（Hard Delete）する
  Future<void> hardDeleteLecture({required String lectureId}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    // 1. ローカルDBから物理削除
    await _db.hardDeleteLectureCascade(lectureId);

    // 2. Supabaseから物理削除
    try {
      if (!await _db.isTutorialLecture(lectureId)) {
        await supabase
            .from('lectures')
            .delete()
            .eq('id', lectureId)
            .timeout(networkTimeout);
      }
    } catch (e) {
      DevLog.add('⚠️ [LectureRepo] SupabaseからのHardDelete処理(未登録または通信エラー): $e');
    }
  }

  /// タイトルと所属コースを更新し、Outboxに登録する (Transaction)
  ///
  /// [previousCourseId]と[courseId]が異なる場合(Course間の移動、または
  /// 未設定↔設定の切り替え)は、courseIdを上書きする前の値を
  /// [LocalLecturesCompanion.pendingTopicMapStaleCourseId]に退避しておく。
  /// これにより[LectureOutboxPushHandler]がpush時に「移動元のTopic Mapを
  /// stale化(remove)」「移動先のTopic Mapをstale化(add)」を、Outboxの
  /// リトライ機構込みで確実に送信できる(courseId自体は即座に上書きされるため、
  /// この退避が無いと移動元の情報がpush時には失われてしまう)。
  Future<void> updateLectureTitleAndCourse({
    required String lectureId,
    required String? title,
    required String? courseId,
    String? previousCourseId,
    DateTime? lectureDatetime,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final isMove = courseId != previousCourseId;

    await _db.transaction(() async {
      // 1. ローカルDBを更新
      await (_db.update(_db.localLectures)
            ..where((t) => t.id.equals(lectureId)))
          .write(LocalLecturesCompanion(
        title: Value(title),
        courseId: Value(courseId),
        lectureDatetime: Value(lectureDatetime),
        syncStatus: const Value('needs_sync'),
        updatedAt: Value(DateTime.now()),
        topicMapMovePending: isMove ? const Value(true) : const Value.absent(),
        pendingTopicMapStaleCourseId:
            isMove ? Value(previousCourseId) : const Value.absent(),
      ));

      // 2. Outboxに登録(softDeleteLectureと同様、entityIdのみでよい)
      if (await _db.isTutorialLecture(lectureId)) {
        return; // チュートリアル講義のデータはOutboxに入れない
      }

      await _db.enqueueOutbox(
        entityType: 'lecture',
        entityId: lectureId,
        op: 'update',
      );
    });
  }

  Lecture _toDomain(LocalLecture row) {
    return Lecture(
      id: row.id,
      userId: row.userId,
      courseId: row.courseId,
      title: row.title,
      titleGenerated: row.titleGenerated,
      summary: row.summary,
      audioPath: row.audioPath,
      metadata: row.metadataJson != null
          ? Map<String, dynamic>.from(jsonDecode(row.metadataJson!) as Map)
          : null,
      deletedAt: row.deletedAt,
      sortOrder: row.sortOrder ?? 0,
      lectureDatetime: row.lectureDatetime ?? row.createdAt,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      lastAccessedAt: row.lastAccessedAt,
    );
  }
}