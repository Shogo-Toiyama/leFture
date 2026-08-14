import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lefture/domain/entities/annotation.dart';
import 'package:lefture/domain/entities/review_card.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

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

  /// 新しいannotation(highlight/notes)を追加し、Outboxに登録する。
  /// 生成したannotationのidを返す。
  Future<String> addAnnotation({
    required String cardId,
    int? blockIdx,
    required int startIdx,
    required int endIdx,
    required String annotationType,
    required String annotatedWords,
    required dynamic contents,
  }) async {
    final annotationId = const Uuid().v4();
    await _updateMetadata(cardId, (metadata) {
      final annotations = _annotationsListOf(metadata);
      annotations.add(Annotation(
        id: annotationId,
        blockIdx: blockIdx,
        startIdx: startIdx,
        endIdx: endIdx,
        annotationType: annotationType,
        annotatedWords: annotatedWords,
        contents: contents,
      ).toMap());
      metadata['annotations'] = annotations;
    });
    return annotationId;
  }

  /// annotationIdの指定するannotationを削除し、Outboxに登録する。
  Future<void> removeAnnotation({required String cardId, required String annotationId}) async {
    await _updateMetadata(cardId, (metadata) {
      final annotations = _annotationsListOf(metadata);
      annotations.removeWhere((a) => a['id'] == annotationId);
      metadata['annotations'] = annotations;
    });
  }

  /// annotationIdの指定するannotationの内容を更新し、Outboxに登録する。
  /// 渡さなかったフィールドは既存の値を維持する。
  Future<void> updateAnnotation({
    required String cardId,
    required String annotationId,
    int? blockIdx,
    int? startIdx,
    int? endIdx,
    String? annotatedWords,
    dynamic contents,
  }) async {
    await _updateMetadata(cardId, (metadata) {
      final annotations = _annotationsListOf(metadata);
      final idx = annotations.indexWhere((a) => a['id'] == annotationId);
      if (idx == -1) return;

      final existing = Annotation.fromMap(Map<String, dynamic>.from(annotations[idx] as Map));
      annotations[idx] = Annotation(
        id: existing.id,
        blockIdx: blockIdx ?? existing.blockIdx,
        startIdx: startIdx ?? existing.startIdx,
        endIdx: endIdx ?? existing.endIdx,
        annotationType: existing.annotationType,
        annotatedWords: annotatedWords ?? existing.annotatedWords,
        contents: contents ?? existing.contents,
      ).toMap();
      metadata['annotations'] = annotations;
    });
  }

  /// [startIdx, endIdx)の範囲と重なるhighlightタイプのannotationを、その部分だけ
  /// 型抜きして削除する(重ならない前後の残り部分は新しいannotationとして残す)。
  /// [blockText]は残り部分のannotatedWordsを再計算するための、その
  /// block(またはノート全体)の現在のプレーンテキスト。
  Future<void> eraseHighlightRange({
    required String cardId,
    int? blockIdx,
    required int startIdx,
    required int endIdx,
    required String blockText,
  }) async {
    await _updateMetadata(cardId, (metadata) {
      final annotations = _annotationsListOf(metadata);
      final result = <dynamic>[];
      for (final raw in annotations) {
        final a = Annotation.fromMap(Map<String, dynamic>.from(raw as Map));
        final overlaps = a.blockIdx == blockIdx &&
            a.annotationType == 'highlight' &&
            a.startIdx < endIdx &&
            a.endIdx > startIdx;
        if (!overlaps) {
          result.add(raw);
          continue;
        }
        if (a.startIdx < startIdx) {
          result.add(Annotation(
            id: const Uuid().v4(),
            blockIdx: a.blockIdx,
            startIdx: a.startIdx,
            endIdx: startIdx,
            annotationType: a.annotationType,
            annotatedWords: blockText.substring(a.startIdx, startIdx),
            contents: a.contents,
          ).toMap());
        }
        if (a.endIdx > endIdx) {
          result.add(Annotation(
            id: const Uuid().v4(),
            blockIdx: a.blockIdx,
            startIdx: endIdx,
            endIdx: a.endIdx,
            annotationType: a.annotationType,
            annotatedWords: blockText.substring(endIdx, a.endIdx),
            contents: a.contents,
          ).toMap());
        }
        // 完全に範囲内なら残り無し(丸ごと消去)。
      }
      metadata['annotations'] = result;
    });
  }

  List<dynamic> _annotationsListOf(Map<String, dynamic> metadata) {
    final raw = metadata['annotations'];
    return raw is List ? List<dynamic>.from(raw) : <dynamic>[];
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

      if (await _db.isTutorialLecture(existing.lectureId)) {
        return; // チュートリアル講義のデータはOutboxに入れない
      }

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
