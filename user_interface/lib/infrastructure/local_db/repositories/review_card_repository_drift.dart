import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lecture_companion_ui/domain/entities/review_card.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'review_card_repository_drift.g.dart';

@Riverpod(keepAlive: true)
ReviewCardRepositoryDrift reviewCardRepositoryDrift(Ref ref) {
  return ReviewCardRepositoryDrift(ref.watch(appDatabaseProvider));
}

/// ReviewCardはサーバー生成コンテンツで、ユーザーによる書き込みは無い。
/// Pull(Supabase→ローカルDB)は[ReviewCardSyncService]が担う。
class ReviewCardRepositoryDrift {
  final AppDatabase _db;

  ReviewCardRepositoryDrift(this._db);

  Stream<List<ReviewCard>> watchReviewCardsForLecture(String lectureId) {
    final query = _db.select(_db.localReviewCards)
      ..where((t) => t.lectureId.equals(lectureId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.topicNumber)]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  ReviewCard _toDomain(LocalReviewCard row) {
    final rawContent = jsonDecode(row.cardContentJson);
    final blocks = <ReviewCardBlock>[];
    if (rawContent is List) {
      for (final block in rawContent) {
        if (block is Map) {
          blocks.add(ReviewCardBlock.fromMap(Map<String, dynamic>.from(block)));
        }
      }
    }

    return ReviewCard(
      id: row.id,
      userId: row.userId,
      lectureId: row.lectureId,
      topicNumber: row.topicNumber,
      cardContent: blocks,
      cardType: row.cardType,
      title: row.title,
      heroEmoji: row.heroEmoji,
      createdAt: row.createdAt,
    );
  }
}
