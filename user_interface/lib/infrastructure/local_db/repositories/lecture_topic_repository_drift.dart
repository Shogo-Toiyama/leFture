import 'package:drift/drift.dart';
import 'package:lefture/domain/entities/lecture_topic.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'lecture_topic_repository_drift.g.dart';

@Riverpod(keepAlive: true)
LectureTopicRepositoryDrift lectureTopicRepositoryDrift(Ref ref) {
  return LectureTopicRepositoryDrift(ref.watch(appDatabaseProvider));
}

/// LectureTopicはサーバー生成コンテンツで、ユーザーによる書き込みは無い。
/// Pull(Supabase→ローカルDB)は[LectureTopicSyncService]が担う。
class LectureTopicRepositoryDrift {
  final AppDatabase _db;

  LectureTopicRepositoryDrift(this._db);

  Stream<List<LectureTopic>> watchTopicsForLecture(String lectureId) {
    final query = _db.select(_db.localLectureTopics)
      ..where((t) => t.lectureId.equals(lectureId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.topicIndex)]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  /// 最初のトピック(index = 1)のimage_pathを監視
  Stream<String?> watchFirstTopicImagePath(String lectureId) {
    final query = _db.select(_db.localLectureTopics)
      ..where((t) =>
          t.lectureId.equals(lectureId) &
          t.topicIndex.equals(1) &
          t.deletedAt.isNull());
    return query.watchSingleOrNull().map((row) => row?.imagePath);
  }

  LectureTopic _toDomain(LocalLectureTopic row) {
    return LectureTopic(
      id: row.id,
      userId: row.userId,
      lectureId: row.lectureId,
      index: row.topicIndex,
      topicTitle: row.topicTitle,
      topicType: row.topicType,
      summary: row.summary,
      startSid: row.startSid,
      endSid: row.endSid,
      imagePath: row.imagePath,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}
