import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/domain/entities/announcement.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/announcement_repository_supabase.dart';

import '../lecture/lecture_list_provider.dart';

part 'course_announcement_provider.g.dart';

/// コースに属する全レクチャーを横断した、未完了のうち最新のアナウンスメント
/// (announcementsはlecture_id経由の紐付けのみでcourse_idを持たないため、
/// まずこのコースのレクチャーID一覧をローカルDBから取得してから絞り込む)
@riverpod
Future<Announcement?> latestAnnouncementForCourse(Ref ref, String courseId) async {
  final lectures = await ref.watch(lectureListStreamProvider(courseId).future);
  final lectureIds = lectures.map((l) => l.id).toList();

  final repo = ref.watch(announcementRepositoryProvider);
  return repo.getLatestActiveForLectureIds(lectureIds);
}

/// コースに属する全レクチャーを横断した、未完了のアナウンスメント一覧
@riverpod
Future<List<Announcement>> activeAnnouncementsForCourse(Ref ref, String courseId) async {
  final lectures = await ref.watch(lectureListStreamProvider(courseId).future);
  final lectureIds = lectures.map((l) => l.id).toList();

  final repo = ref.watch(announcementRepositoryProvider);
  return repo.listActiveForLectureIds(lectureIds);
}
