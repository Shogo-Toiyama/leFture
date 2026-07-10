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

  /// 指定レクチャーのDeep Note一覧（topic_number昇順、論理削除除外）
  Future<List<DeepNote>> listForLecture(String lectureId) async {
    final rows = await supabase
        .from(_table)
        .select()
        .eq('lecture_id', lectureId)
        .isFilter('deleted_at', null)
        .order('topic_number', ascending: true);

    return rows.map((e) => DeepNote.fromMap(e)).toList();
  }

  /// 指定レクチャーに紐づく全Deep Noteを論理削除する（Lecture削除時のカスケード用）
  Future<void> softDeleteForLecture(String lectureId) async {
    await supabase
        .from(_table)
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('lecture_id', lectureId);
  }
}
