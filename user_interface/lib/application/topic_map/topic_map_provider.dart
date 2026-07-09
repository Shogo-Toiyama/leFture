import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_list_provider.dart';
import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/topic_map_repository_supabase.dart';
import 'package:lecture_companion_ui/presentation/widgets/topic_map/topic_map_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'topic_map_provider.g.dart';

/// The course's topic map, or null if the pipeline hasn't generated one yet.
///
/// course_title/total_lectures_covered never live in the map jsonb itself
/// (see TopicMapData.fromJson) -- they belong to the courses/lectures
/// tables, so this provider composes the raw map with courseListProvider
/// and lectureListStreamProvider instead of trusting the json for them.
@riverpod
Future<TopicMapData?> topicMapForCourse(Ref ref, String courseId) async {
  final repo = ref.watch(topicMapRepositoryProvider);
  final raw = await repo.getForCourse(courseId);
  if (raw == null) return null;

  final courses = await ref.watch(courseListProvider.future);
  final course = courses.cast<Course?>().firstWhere(
        (c) => c?.id == courseId,
        orElse: () => null,
      );
  final lectures = await ref.watch(lectureListStreamProvider(courseId).future);

  return raw.copyWith(
    courseTitle: course?.courseTitle?.trim().isNotEmpty == true ? course!.courseTitle : null,
    totalLecturesCovered: lectures.length,
  );
}
