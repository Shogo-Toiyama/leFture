import 'package:drift/drift.dart';
import 'package:lecture_companion_ui/domain/entities/keyword.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'keyword_repository_drift.g.dart';

@Riverpod(keepAlive: true)
KeywordRepositoryDrift keywordRepositoryDrift(Ref ref) {
  return KeywordRepositoryDrift(ref.watch(appDatabaseProvider));
}

/// Keywordはサーバー生成コンテンツで、ユーザーによる書き込みは無い。
/// Pull(Supabase→ローカルDB)は[KeywordSyncService]が担う。
class KeywordRepositoryDrift {
  final AppDatabase _db;

  KeywordRepositoryDrift(this._db);

  Stream<List<Keyword>> watchKeywordsForLecture(String lectureId) {
    final query = _db.select(_db.localKeywords)
      ..where((t) => t.lectureId.equals(lectureId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.topicNumber)]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  Keyword _toDomain(LocalKeyword row) {
    return Keyword(
      id: row.id,
      userId: row.userId,
      lectureId: row.lectureId,
      topicNumber: row.topicNumber,
      keyword: row.keyword,
      definition: row.definition,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
    );
  }
}
