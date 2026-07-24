import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/application/lecture/lecture_list_provider.dart';
import 'package:lefture/domain/entities/course.dart';
import 'package:lefture/infrastructure/local_db/repositories/topic_map_repository_drift.dart';
import 'package:lefture/presentation/widgets/topic_map/topic_map_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'topic_map_provider.g.dart';

/// The course's topic map, or null if the pipeline hasn't generated one yet.
///
/// course_title/total_lectures_covered never live in the map jsonb itself
/// (see TopicMapData.fromJson) -- they belong to the courses/lectures
/// tables, so this provider composes the raw map with courseListProvider
/// and lectureListStreamProvider instead of trusting the json for them.
///
/// マップ本体はローカルDB経由(オフライン優先)。書き込み(markStale/
/// reconstruct)は依然Supabase/Cloud Run直接なので、変更の反映は次のPull
/// 以降になる(即時反映が必要な箇所はTopicMapReconstructControllerが
/// 明示的に強制Pullしてから呼び直す)。
@riverpod
Stream<TopicMapData?> topicMapForCourse(Ref ref, String courseId) async* {
  final repo = ref.watch(topicMapRepositoryDriftProvider);
  final stream = repo.watchTopicMapForCourse(courseId);

  await for (final raw in stream) {
    if (!ref.mounted) return;
    if (raw == null) {
      yield null;
      continue;
    }

    // ref.watch(...).future だと courseList/lectureListStream が後から再emit
    // するたびにこのprovider自体が丸ごと再構築されてしまう(lectureListStreamは
    // lectures書き込みのたびに再emitするため、Outbox同期と競合してdispose後の
    // Ref使用でクラッシュする)。ここでは購読ではなくスナップショット取得で
    // 十分なので ref.read にする -- 最新化は raw(topic_map本体)の再emit時に
    // このブロックごと再実行されることで担保される。
    final courses = await ref.read(courseListProvider.future);
    if (!ref.mounted) return;
    final course = courses.cast<Course?>().firstWhere(
          (c) => c?.id == courseId,
          orElse: () => null,
        );
    final lectures = await ref.read(lectureListStreamProvider(courseId).future);
    if (!ref.mounted) return;

    // ノードの「Lecture N」表示は保存されていない(topic_maps.mapには焼き込まない
    // ---削除・移動があるたびに腐るため)。バックエンドがLLM呼び出し直前に
    // 毎回計算し直すのと全く同じロジック(非削除Lectureをcreated_at昇順で
    // 並べた位置)を、表示のたびにここで計算し直す。
    final liveLectures = lectures.where((l) => !l.isDeleted).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final lectureNumById = <String, int>{
      for (var i = 0; i < liveLectures.length; i++) liveLectures[i].id: i + 1,
    };
    final annotatedNodes = raw.nodes
        .map((n) => n.copyWith(lectureNum: lectureNumById[n.sourceLectureId]))
        .toList();

    yield raw.copyWith(
      courseTitle: course?.courseTitle?.trim().isNotEmpty == true ? course!.courseTitle : null,
      totalLecturesCovered: lectures.length,
      nodes: annotatedNodes,
    );
  }
}
