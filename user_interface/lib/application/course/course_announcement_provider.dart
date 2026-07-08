import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/domain/entities/announcement.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/announcement_repository_supabase.dart';

import '../lecture/lecture_list_provider.dart';

part 'course_announcement_provider.g.dart';

/// コースに属する全レクチャーを横断した、未完了のうち最新のアナウンスメント
@riverpod
Future<Announcement?> latestAnnouncementForCourse(Ref ref, String courseId) async {
  final lectures = await ref.watch(lectureListStreamProvider(courseId).future);
  final lectureIds = lectures.map((l) => l.id).toList();

  final repo = ref.watch(announcementRepositoryProvider);
  return repo.getLatestActiveForLectureIds(lectureIds);
}

/// コースに属する全レクチャーを横断した、未完了のアナウンスメント一覧。
/// AsyncNotifier として管理することで、Done/Undo 操作後も
/// プロバイダを invalidate せずローカル状態だけを更新（シート閉じるまで表示維持）。
@riverpod
class ActiveAnnouncementsForCourse extends _$ActiveAnnouncementsForCourse {
  @override
  Future<List<Announcement>> build(String courseId) async {
    final lectures = await ref.watch(lectureListStreamProvider(courseId).future);
    final lectureIds = lectures.map((l) => l.id).toList();

    final repo = ref.watch(announcementRepositoryProvider);
    return repo.listActiveForLectureIds(lectureIds);
  }

  /// 指定アナウンスメントの完了/未完了をトグルして楽観的に状態を更新する。
  Future<void> toggleComplete(Announcement announcement) async {
    final repo = ref.read(announcementRepositoryProvider);
    final newCompletedAt = announcement.isCompleted ? null : DateTime.now();

    state = AsyncData(
      (state.value ?? []).map((a) {
        if (a.id == announcement.id) {
          return a.copyWith(completedAt: () => newCompletedAt);
        }
        return a;
      }).toList(),
    );

    await repo.markAsCompleted(announcement.id, newCompletedAt);
    ref.invalidate(latestAnnouncementForCourseProvider(courseId));
  }
}
