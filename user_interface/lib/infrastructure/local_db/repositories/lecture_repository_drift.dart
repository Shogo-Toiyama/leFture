import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

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
      await _db.enqueueOutbox(
        entityType: 'lecture',
        entityId: lectureId,
        op: 'update', // 論理削除なので update 扱い
      );
    });
  }

  /// タイトルと所属コースを更新し、Outboxに登録する (Transaction)
  Future<void> updateLectureTitleAndCourse({
    required String lectureId,
    required String? title,
    required String? courseId,
    DateTime? lectureDatetime,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

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
      ));

      // 2. Outboxに登録(softDeleteLectureと同様、entityIdのみでよい)
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
    );
  }
}