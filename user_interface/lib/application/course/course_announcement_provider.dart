import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/domain/entities/announcement.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/repositories/announcement_repository_drift.dart';

import '../lecture/lecture_list_provider.dart';

part 'course_announcement_provider.g.dart';

/// コースに属する全レクチャーを横断した、未完了のうち最新のアナウンスメント。
/// ローカルDB経由でオフライン優先。
@riverpod
Stream<Announcement?> latestAnnouncementForCourse(Ref ref, String courseId) async* {
  final lectures = await ref.watch(lectureListStreamProvider(courseId).future);
  final lectureIds = lectures.map((l) => l.id).toList();

  yield* ref
      .watch(announcementRepositoryDriftProvider)
      .watchActiveAnnouncementsForLectureIds(lectureIds)
      .map((list) => list.isEmpty ? null : list.first);
}

/// コースに属する全レクチャーを横断した、未完了のアナウンスメント一覧。
/// ローカルDB経由でオフライン優先。Streamなので、完了/未完了のトグルが
/// そのまま反映される。
@riverpod
Stream<List<Announcement>> activeAnnouncementsForCourse(Ref ref, String courseId) async* {
  final lectures = await ref.watch(lectureListStreamProvider(courseId).future);
  final lectureIds = lectures.map((l) => l.id).toList();

  yield* ref
      .watch(announcementRepositoryDriftProvider)
      .watchActiveAnnouncementsForLectureIds(lectureIds);
}
