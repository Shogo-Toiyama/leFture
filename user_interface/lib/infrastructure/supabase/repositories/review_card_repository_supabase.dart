import 'package:lefture/domain/entities/review_card.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'review_card_repository_supabase.g.dart';

@Riverpod(keepAlive: true)
ReviewCardRepositorySupabase reviewCardRepository(Ref ref) {
  return ReviewCardRepositorySupabase();
}

class ReviewCardRepositorySupabase {
  static const _table = 'review_cards';

  /// 指定レクチャーのレビューカード一覧（topic_number昇順、論理削除除外）
  Future<List<ReviewCard>> listForLecture(String lectureId) async {
    final rows = await supabase
        .from(_table)
        .select()
        .eq('lecture_id', lectureId)
        .isFilter('deleted_at', null)
        .order('topic_number', ascending: true);

    return rows.map((e) => ReviewCard.fromMap(e)).toList();
  }

  /// 指定レクチャーに紐づく全レビューカードを論理削除する（Lecture削除時のカスケード用）
  Future<void> softDeleteForLecture(String lectureId) async {
    await supabase
        .from(_table)
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('lecture_id', lectureId);
  }
}
