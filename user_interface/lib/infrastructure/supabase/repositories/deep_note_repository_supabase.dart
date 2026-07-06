import 'package:lecture_companion_ui/domain/entities/deep_note.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'deep_note_repository_supabase.g.dart';

@Riverpod(keepAlive: true)
DeepNoteRepositorySupabase deepNoteRepository(Ref ref) {
  return DeepNoteRepositorySupabase();
}

class DeepNoteRepositorySupabase {
  static const _table = 'deep_notes';

  /// 指定レクチャーのDeep Note一覧（topic_number昇順）
  Future<List<DeepNote>> listForLecture(String lectureId) async {
    final rows = await supabase
        .from(_table)
        .select()
        .eq('lecture_id', lectureId)
        .order('topic_number', ascending: true);

    return rows.map((e) => DeepNote.fromMap(e)).toList();
  }
}
