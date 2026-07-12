import 'package:drift/drift.dart';
import 'package:lecture_companion_ui/domain/entities/deep_note.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'deep_note_repository_drift.g.dart';

@Riverpod(keepAlive: true)
DeepNoteRepositoryDrift deepNoteRepositoryDrift(Ref ref) {
  return DeepNoteRepositoryDrift(ref.watch(appDatabaseProvider));
}

/// DeepNoteはサーバー生成コンテンツで、ユーザーによる書き込みは無い。
/// Pull(Supabase→ローカルDB)は[DeepNoteSyncService]が担う。
class DeepNoteRepositoryDrift {
  final AppDatabase _db;

  DeepNoteRepositoryDrift(this._db);

  Stream<List<DeepNote>> watchDeepNotesForLecture(String lectureId) {
    final query = _db.select(_db.localDeepNotes)
      ..where((t) => t.lectureId.equals(lectureId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.topicNumber)]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  DeepNote _toDomain(LocalDeepNote row) {
    return DeepNote(
      id: row.id,
      userId: row.userId,
      lectureId: row.lectureId,
      topicNumber: row.topicNumber,
      noteContents: row.noteContents,
      createdAt: row.createdAt,
    );
  }
}
