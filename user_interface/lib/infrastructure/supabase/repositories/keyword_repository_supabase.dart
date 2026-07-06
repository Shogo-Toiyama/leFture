import 'package:lecture_companion_ui/domain/entities/keyword.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'keyword_repository_supabase.g.dart';

@Riverpod(keepAlive: true)
KeywordRepositorySupabase keywordRepository(Ref ref) {
  return KeywordRepositorySupabase();
}

class KeywordRepositorySupabase {
  static const _table = 'keywords';

  /// 指定レクチャーのキーワード一覧（topic_number昇順、論理削除除外）
  Future<List<Keyword>> listForLecture(String lectureId) async {
    final rows = await supabase
        .from(_table)
        .select()
        .eq('lecture_id', lectureId)
        .isFilter('deleted_at', null)
        .order('topic_number', ascending: true);

    return rows.map((e) => Keyword.fromMap(e)).toList();
  }
}
