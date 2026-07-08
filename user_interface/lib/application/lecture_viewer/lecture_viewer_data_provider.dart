import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/domain/entities/announcement.dart';
import 'package:lecture_companion_ui/domain/entities/deep_note.dart';
import 'package:lecture_companion_ui/domain/entities/fun_fact.dart';
import 'package:lecture_companion_ui/domain/entities/keyword.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_topic.dart';
import 'package:lecture_companion_ui/domain/entities/review_card.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/announcement_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/deep_note_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/fun_fact_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/keyword_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/lecture_topic_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/review_card_repository_supabase.dart';

part 'lecture_viewer_data_provider.g.dart';

/// 講義のトピック一覧（index昇順）
@riverpod
Future<List<LectureTopic>> lectureTopics(Ref ref, String lectureId) async {
  final repo = ref.watch(lectureTopicRepositoryProvider);
  return repo.listForLecture(lectureId);
}

/// 講義のDeep Note一覧（topic_number昇順）
@riverpod
Future<List<DeepNote>> deepNotes(Ref ref, String lectureId) async {
  final repo = ref.watch(deepNoteRepositoryProvider);
  return repo.listForLecture(lectureId);
}

/// 講義のキーワード一覧
@riverpod
Future<List<Keyword>> lectureKeywords(Ref ref, String lectureId) async {
  final repo = ref.watch(keywordRepositoryProvider);
  return repo.listForLecture(lectureId);
}

/// 講義のレビューカード一覧
@riverpod
Future<List<ReviewCard>> reviewCards(Ref ref, String lectureId) async {
  final repo = ref.watch(reviewCardRepositoryProvider);
  return repo.listForLecture(lectureId);
}

/// 講義のFunFact一覧
@riverpod
Future<List<FunFact>> funFactsForLecture(Ref ref, String lectureId) async {
  final repo = ref.watch(funFactRepositoryProvider);
  return repo.listForLecture(lectureId);
}

/// 講義のアナウンスメント一覧（全件・completed_atを問わず）。
/// AsyncNotifier として管理することで、Done/Undo 操作後も
/// プロバイダを invalidate せずローカル状態だけを更新（シート閉じるまで表示維持）。
@riverpod
class AnnouncementsForLecture extends _$AnnouncementsForLecture {
  @override
  Future<List<Announcement>> build(String lectureId) async {
    final repo = ref.watch(announcementRepositoryProvider);
    return repo.listForLecture(lectureId);
  }

  /// 指定アナウンスメントの完了/未完了をトグルして楽観的に状態を更新する。
  Future<void> toggleComplete(Announcement announcement) async {
    final repo = ref.read(announcementRepositoryProvider);
    final newCompletedAt = announcement.isCompleted ? null : DateTime.now();

    state = AsyncData(
      (state.value ?? []).map((a) {
        if (a.id == announcement.id) {
          return a.copyWith(completedAt: () => newCompletedAt);
        }
        return a;
      }).toList(),
    );

    await repo.markAsCompleted(announcement.id, newCompletedAt);
  }
}
