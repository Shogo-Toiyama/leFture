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
/// Pull(Supabase→ローカルDB)は[ReviewCardSyncService]が担う。ユーザーが
/// ローカルで即時更新できるのは`metadata`内のreaction/savedのみ。
class ReviewCardRepositoryDrift {
  final AppDatabase _db;

  ReviewCardRepositoryDrift(this._db);

  Stream<List<ReviewCard>> watchReviewCardsForLecture(String lectureId) {
    final query = _db.select(_db.localReviewCards)
      ..where((t) => t.lectureId.equals(lectureId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.topicNumber)]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  /// reactionを即時ローカル更新(楽観的UI)し、Outboxに登録する。
  /// 同じreactionを再度渡すとトグル解除(null)になる。
  Future<void> updateReaction({required String id, required String? reaction}) async {
    await _updateMetadata(id, (metadata) {
      if (reaction != null) {
        metadata['reaction'] = reaction;
      } else {
        metadata.remove('reaction');
      }
    });
  }

  /// savedを即時ローカル更新(楽観的UI)し、Outboxに登録する。
  Future<void> updateSaved({required String id, required bool saved}) async {
    await _updateMetadata(id, (metadata) {
      if (saved) {
        metadata['saved'] = true;
      } else {
        metadata.remove('saved');
      }
    });
  }

  Future<void> _updateMetadata(
    String id,
    void Function(Map<String, dynamic> metadata) mutate,
  ) async {
    await _db.transaction(() async {
      final existing = await (_db.select(_db.localReviewCards)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (existing == null) return;

      final metadata = existing.metadataJson != null
          ? Map<String, dynamic>.from(jsonDecode(existing.metadataJson!) as Map)
          : <String, dynamic>{};
      mutate(metadata);

      await (_db.update(_db.localReviewCards)..where((t) => t.id.equals(id))).write(
        LocalReviewCardsCompanion(metadataJson: Value(jsonEncode(metadata))),
      );

      await _db.enqueueOutbox(
        entityType: 'review_card',
        entityId: id,
        op: 'update',
      );
    });
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

    final metadata = row.metadataJson != null
        ? Map<String, dynamic>.from(jsonDecode(row.metadataJson!) as Map)
        : null;

    return ReviewCard(
      id: row.id,
      userId: row.userId,
      lectureId: row.lectureId,
      topicNumber: row.topicNumber,
      cardContent: blocks,
      cardType: row.cardType,
      title: row.title,
      heroEmoji: row.heroEmoji,
      metadata: metadata,
      createdAt: row.createdAt,
    );
  }
}
