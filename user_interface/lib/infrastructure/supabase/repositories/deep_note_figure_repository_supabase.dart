import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/domain/entities/deep_note_figure.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

final deepNoteFigureRepositoryProvider = Provider<DeepNoteFigureRepositorySupabase>((ref) {
  return DeepNoteFigureRepositorySupabase();
});

final deepNoteFiguresProvider = FutureProvider.family<List<DeepNoteFigure>, String>((ref, lectureId) {
  return ref.watch(deepNoteFigureRepositoryProvider).listForLecture(lectureId);
});

class DeepNoteFigureRepositorySupabase {
  static const _table = 'deep_note_figures';

  /// 指定レクチャーのDeepNote図解一覧（topic_number, figure_index昇順、論理削除除外）
  Future<List<DeepNoteFigure>> listForLecture(String lectureId) async {
    try {
      final rows = await supabase
          .from(_table)
          .select()
          .eq('lecture_id', lectureId)
          .isFilter('deleted_at', null)
          .order('topic_number', ascending: true)
          .order('figure_index', ascending: true);

      return (rows as List).map((e) => DeepNoteFigure.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      // オフラインまたはテーブル未取得時は空リストでフォールバック
      return const [];
    }
  }
}
