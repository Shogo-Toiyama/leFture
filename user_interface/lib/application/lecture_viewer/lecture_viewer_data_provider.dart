import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lefture/domain/entities/announcement.dart';
import 'package:lefture/domain/entities/deep_note.dart';
import 'package:lefture/domain/entities/fun_fact.dart';
import 'package:lefture/domain/entities/keyword.dart';
import 'package:lefture/domain/entities/lecture_topic.dart';
import 'package:lefture/domain/entities/review_card.dart';
import 'package:lefture/infrastructure/local_db/repositories/announcement_repository_drift.dart';
import 'package:lefture/infrastructure/local_db/repositories/deep_note_repository_drift.dart';
import 'package:lefture/infrastructure/local_db/repositories/fun_fact_repository_drift.dart';
import 'package:lefture/infrastructure/local_db/repositories/keyword_repository_drift.dart';
import 'package:lefture/infrastructure/local_db/repositories/lecture_topic_repository_drift.dart';
import 'package:lefture/infrastructure/local_db/repositories/review_card_repository_drift.dart';

part 'lecture_viewer_data_provider.g.dart';

/// 講義のトピック一覧（index昇順、ローカルDB経由でオフライン優先）
@riverpod
Stream<List<LectureTopic>> lectureTopics(Ref ref, String lectureId) {
  return ref.watch(lectureTopicRepositoryDriftProvider).watchTopicsForLecture(lectureId);
}

/// 講義のDeep Note一覧（topic_number昇順、ローカルDB経由でオフライン優先）
@riverpod
Stream<List<DeepNote>> deepNotes(Ref ref, String lectureId) {
  return ref.watch(deepNoteRepositoryDriftProvider).watchDeepNotesForLecture(lectureId);
}

/// 講義のキーワード一覧（ローカルDB経由でオフライン優先）
@riverpod
Stream<List<Keyword>> lectureKeywords(Ref ref, String lectureId) {
  return ref.watch(keywordRepositoryDriftProvider).watchKeywordsForLecture(lectureId);
}

/// 講義のレビューカード一覧（ローカルDB経由でオフライン優先）
@riverpod
Stream<List<ReviewCard>> reviewCards(Ref ref, String lectureId) {
  return ref.watch(reviewCardRepositoryDriftProvider).watchReviewCardsForLecture(lectureId);
}

/// 講義のFunFact一覧(ローカルDB経由でオフライン優先)
@riverpod
Stream<List<FunFact>> funFactsForLecture(Ref ref, String lectureId) {
  return ref.watch(funFactRepositoryDriftProvider).watchFunFactsForLecture(lectureId);
}

/// 講義のアナウンスメント一覧（全件・completed_atを問わず）。
/// ローカルDB経由でオフライン優先。Streamなので、完了/未完了のトグルが
/// そのまま反映される。
@riverpod
Stream<List<Announcement>> announcementsForLecture(Ref ref, String lectureId) {
  return ref.watch(announcementRepositoryDriftProvider).watchAnnouncementsForLecture(lectureId);
}
