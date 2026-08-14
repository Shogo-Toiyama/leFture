import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import 'package:lefture/domain/entities/lecture_moment.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

part 'lecture_moment_repository_drift.g.dart';

@Riverpod(keepAlive: true)
LectureMomentRepositoryDrift lectureMomentRepositoryDrift(Ref ref) {
  return LectureMomentRepositoryDrift(ref.watch(appDatabaseProvider));
}

class LectureMomentRepositoryDrift {
  final AppDatabase _db;

  LectureMomentRepositoryDrift(this._db);

  /// 講義に紐づくリアクション/メモ一覧(タイムスタンプ昇順、論理削除除外)を監視する。
  Stream<List<LectureMoment>> watchMomentsForLecture(String lectureId) {
    final query = _db.select(_db.localLectureMoments)
      ..where((t) => t.lectureId.equals(lectureId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.timestampSec)]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  /// 新しいリアクション/メモをローカルに即時作成し、Outboxに登録する。
  Future<void> addMoment({
    required String lectureId,
    required String momentType,
    String? noteText,
    required int timestampSec,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();

    await _db.transaction(() async {
      await _db.into(_db.localLectureMoments).insert(
            LocalLectureMomentsCompanion.insert(
              id: id,
              userId: uid,
              lectureId: lectureId,
              momentType: momentType,
              noteText: Value(noteText),
              timestampSec: timestampSec,
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      if (await _db.isTutorialLecture(lectureId)) {
        return; // チュートリアル講義のデータはOutboxに入れない
      }

      await _db.enqueueOutbox(
        entityType: 'lecture_moment',
        entityId: id,
        op: 'create',
      );
    });
  }

  /// ソフトデリート(deletedAtをセット)し、Outboxに登録する。
  Future<void> deleteMoment(String id) async {
    final now = DateTime.now().toUtc();

    await _db.transaction(() async {
      final current = await (_db.select(_db.localLectureMoments)..where((t) => t.id.equals(id))).getSingleOrNull();

      await (_db.update(_db.localLectureMoments)..where((t) => t.id.equals(id))).write(
        LocalLectureMomentsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      if (current != null && await _db.isTutorialLecture(current.lectureId)) {
        return; // チュートリアル講義のデータはOutboxに入れない
      }

      await _db.enqueueOutbox(
        entityType: 'lecture_moment',
        entityId: id,
        op: 'update',
      );
    });
  }

  LectureMoment _toDomain(LocalLectureMoment row) {
    return LectureMoment(
      id: row.id,
      lectureId: row.lectureId,
      momentType: row.momentType,
      noteText: row.noteText,
      timestampSec: row.timestampSec,
      createdAt: row.createdAt,
    );
  }
}
