import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lefture/domain/entities/announcement.dart';
import 'package:lefture/infrastructure/local_db/repositories/announcement_repository_drift.dart';

import '../lecture/lecture_list_provider.dart';

part 'course_announcement_provider.g.dart';

/// コースに属する全レクチャーを横断した、未完了のうち最新のアナウンスメント。
/// ローカルDB経由でオフライン優先。
@riverpod
Stream<Announcement?> latestAnnouncementForCourse(Ref ref, String courseId) async* {
  final lectures = await ref.watch(lectureListStreamProvider(courseId).future);
  final lectureIds = lectures.map((l) => l.id).toList();
  final cutoff = DateTime.now().subtract(const Duration(minutes: 5));

  yield* ref
      .watch(announcementRepositoryDriftProvider)
      .watchActiveAnnouncementsForLectureIds(lectureIds, completedAfter: cutoff)
      .map((list) {
        // 未完了のみにフィルタリング
        final activeList = list.where((a) => !a.isCompleted).toList();
        return activeList.isEmpty ? null : activeList.first;
      });
}

/// コースに属する全レクチャーを横断した、未完了、または直近5分以内に完了したアナウンスメント一覧。
/// ローカルDB経由でオフライン優先。30秒ごとに再評価し、5分経過した完了済みアナウンスメントを自動消去する。
@riverpod
Stream<List<Announcement>> activeAnnouncementsForCourse(Ref ref, String courseId) async* {
  final lectures = await ref.watch(lectureListStreamProvider(courseId).future);
  final lectureIds = lectures.map((l) => l.id).toList();
  final cutoff = DateTime.now().subtract(const Duration(minutes: 5));

  // 30秒ごとに再評価するためのタイマー
  final timer = Timer.periodic(const Duration(seconds: 30), (_) {
    ref.invalidateSelf();
  });
  ref.onDispose(() {
    timer.cancel();
  });

  yield* ref
      .watch(announcementRepositoryDriftProvider)
      .watchActiveAnnouncementsForLectureIds(lectureIds, completedAfter: cutoff);
}
