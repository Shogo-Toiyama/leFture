import 'package:lecture_companion_ui/domain/entities/lecture_topic.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'lecture_topic_repository_supabase.g.dart';

@Riverpod(keepAlive: true)
LectureTopicRepositorySupabase lectureTopicRepository(Ref ref) {
  return LectureTopicRepositorySupabase();
}

class LectureTopicRepositorySupabase {
  static const _table = 'lecture_topics';

  /// 指定レクチャーのトピック一覧（index昇順）
  Future<List<LectureTopic>> listForLecture(String lectureId) async {
    final rows = await supabase
        .from(_table)
        .select()
        .eq('lecture_id', lectureId)
        .order('index', ascending: true);

    return rows.map((e) => LectureTopic.fromMap(e)).toList();
  }

  /// 最初のトピック（index = 1）の image_path を取得
  Future<String?> firstTopicImagePath(String lectureId) async {
    final row = await supabase
        .from(_table)
        .select('image_path')
        .eq('lecture_id', lectureId)
        .eq('index', 1)
        .maybeSingle();

    return row?['image_path'] as String?;
  }
}
