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

  /// 指定レクチャーのトピック一覧（index昇順、論理削除除外）
  Future<List<LectureTopic>> listForLecture(String lectureId) async {
    final rows = await supabase
        .from(_table)
        .select()
        .eq('lecture_id', lectureId)
        .isFilter('deleted_at', null)
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
        .isFilter('deleted_at', null)
        .maybeSingle();

    return row?['image_path'] as String?;
  }

  /// 指定レクチャーに紐づく全トピックを論理削除する（Lecture削除時のカスケード用）
  Future<void> softDeleteForLecture(String lectureId) async {
    await supabase
        .from(_table)
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('lecture_id', lectureId);
  }
}
