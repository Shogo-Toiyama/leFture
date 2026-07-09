import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/presentation/widgets/topic_map/topic_map_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'topic_map_repository_supabase.g.dart';

@Riverpod(keepAlive: true)
TopicMapRepositorySupabase topicMapRepository(Ref ref) {
  return TopicMapRepositorySupabase();
}

class TopicMapRepositorySupabase {
  static const _table = 'topic_maps';

  /// The course's topic map, or null if the pipeline hasn't generated one
  /// yet. One row per course is assumed; if that ever changes, the
  /// `updated_at` ordering here picks the most recently generated map.
  Future<TopicMapData?> getForCourse(String courseId) async {
    final row = await supabase
        .from(_table)
        .select('map')
        .eq('course_id', courseId)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();

    final mapJson = row?['map'] as Map<String, dynamic>?;
    if (mapJson == null) return null;

    return TopicMapData.fromJson(mapJson);
  }
}
