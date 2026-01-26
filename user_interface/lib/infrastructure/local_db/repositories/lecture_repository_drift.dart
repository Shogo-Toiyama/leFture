// lib/infrastructure/local_db/repositories/lecture_repository_drift.dart

import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart'; // supabaseインスタンス用

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

  // DriftのLocalLectureクラス -> DomainのLectureクラスへの変換
  Lecture _toDomain(LocalLecture row) {
    return Lecture(
      id: row.id,
      ownerId: row.ownerId,
      folderId: row.folderId,
      title: row.title,
      isDeleted: false, // クエリで除外済み
      sortOrder: row.sortOrder ?? 0,
      lectureDatetime: row.lectureDatetime ?? row.createdAt,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      // 必要なら syncStatus などをここに追加拡張できます
    );
  }
}