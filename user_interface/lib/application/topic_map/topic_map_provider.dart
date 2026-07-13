import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_list_provider.dart';
import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/repositories/topic_map_repository_drift.dart';
import 'package:lecture_companion_ui/presentation/widgets/topic_map/topic_map_models.dart';
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
    if (raw == null) {
      yield null;
      continue;
    }

    final courses = await ref.watch(courseListProvider.future);
    final course = courses.cast<Course?>().firstWhere(
          (c) => c?.id == courseId,
          orElse: () => null,
        );
    final lectures = await ref.watch(lectureListStreamProvider(courseId).future);

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
