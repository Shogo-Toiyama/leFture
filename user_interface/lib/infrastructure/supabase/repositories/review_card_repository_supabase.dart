import 'package:lecture_companion_ui/domain/entities/review_card.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'review_card_repository_supabase.g.dart';

@Riverpod(keepAlive: true)
ReviewCardRepositorySupabase reviewCardRepository(Ref ref) {
  return ReviewCardRepositorySupabase();
}

class ReviewCardRepositorySupabase {
  static const _table = 'review_cards';

  /// 指定レクチャーのレビューカード一覧（topic_number昇順）
  Future<List<ReviewCard>> listForLecture(String lectureId) async {
    final rows = await supabase
        .from(_table)
        .select()
        .eq('lecture_id', lectureId)
        .order('topic_number', ascending: true);

    return rows.map((e) => ReviewCard.fromMap(e)).toList();
  }
}
