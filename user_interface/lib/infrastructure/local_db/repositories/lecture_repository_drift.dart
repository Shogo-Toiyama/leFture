import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

class LectureRepositoryDrift {
  final AppDatabase _db;

  LectureRepositoryDrift(this._db);

  Stream<List<Lecture>> watchLectures({required String? folderId}) {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return const Stream.empty();

    return _db.watchLectures(uid, folderId).map((rows) {
      return rows.map((row) => _toDomain(row)).toList();
    });
  }

  /// 論理削除を実行し、Outboxに登録する (Transaction)
  Future<void> softDeleteLecture({required String lectureId}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    await _db.transaction(() async {
      // 1. ローカルDBで論理削除
      // deletedAt を入れ、syncStatus を 'needs_sync' に変更
      await (_db.update(_db.localLectures)
            ..where((t) => t.id.equals(lectureId)))
          .write(LocalLecturesCompanion(
        deletedAt: Value(DateTime.now()),
        syncStatus: const Value('needs_sync'), // テキスト型に合わせて修正
        updatedAt: Value(DateTime.now()),
      ));

      // 2. Outboxに登録
      // AppDatabaseの enqueueOutbox を使ってもいいですが、
      // トランザクション内で確実に処理するため直接 insert します
      final payload = {
        'id': lectureId,
        'is_deleted': true,
      };

      await _db.into(_db.localOutbox).insert(
            LocalOutboxCompanion.insert(
              entityType: 'lecture',
              entityId: lectureId,
              op: 'update', // 論理削除なので update 扱い
              payloadJson: jsonEncode(payload),
              // enqueuedAt はデフォルト値が入るので省略OK
            ),
          );
    });
  }

  Lecture _toDomain(LocalLecture row) {
    return Lecture(
      id: row.id,
      ownerId: row.ownerId,
      folderId: row.folderId,
      title: row.title,
      isDeleted: row.deletedAt != null,
      sortOrder: row.sortOrder ?? 0,
      lectureDatetime: row.lectureDatetime ?? row.createdAt,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}