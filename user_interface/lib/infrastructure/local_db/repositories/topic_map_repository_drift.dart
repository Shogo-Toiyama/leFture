import 'dart:convert';

import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:lefture/presentation/widgets/topic_map/topic_map_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'topic_map_repository_drift.g.dart';

@Riverpod(keepAlive: true)
TopicMapRepositoryDrift topicMapRepositoryDrift(Ref ref) {
  return TopicMapRepositoryDrift(ref.watch(appDatabaseProvider));
}

/// TopicMapの読み取りはローカルDB経由(オフライン優先)。書き込み
/// (markStale/reconstruct)は依然[TopicMapRepositorySupabase]がSupabase/
/// Cloud Runに直接行う — 変更が反映されるのは次のPull以降になるため、
/// 即時反映が必要な操作([TopicMapReconstructController.recreate])は
/// 呼び出し側で明示的に強制Pullしてから読み直す。
class TopicMapRepositoryDrift {
  final AppDatabase _db;

  TopicMapRepositoryDrift(this._db);

  /// コース of Topic Mapを監視する。
  Stream<TopicMapData?> watchTopicMapForCourse(String courseId) {
    final query = _db.select(_db.localTopicMaps)
      ..where((t) => t.courseId.equals(courseId));
    return query.watchSingleOrNull().map((row) {
      if (row == null) return null;
      final mapJson = jsonDecode(row.mapJson) as Map<String, dynamic>;
      return TopicMapData.fromJson(mapJson, isStale: row.isStale);
    });
  }
}
