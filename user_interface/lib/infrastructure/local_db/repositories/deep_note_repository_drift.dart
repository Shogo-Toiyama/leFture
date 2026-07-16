import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lecture_companion_ui/domain/entities/annotation.dart';
import 'package:lecture_companion_ui/domain/entities/deep_note.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'deep_note_repository_drift.g.dart';

@Riverpod(keepAlive: true)
DeepNoteRepositoryDrift deepNoteRepositoryDrift(Ref ref) {
  return DeepNoteRepositoryDrift(ref.watch(appDatabaseProvider));
}

/// DeepNoteはサーバー生成コンテンツで、ユーザーによる書き込みは無い。
/// Pull(Supabase→ローカルDB)は[DeepNoteSyncService]が担う。ユーザーが
/// ローカルで即時更新できるのは`metadata`内のreaction/savedのみ。
class DeepNoteRepositoryDrift {
  final AppDatabase _db;

  DeepNoteRepositoryDrift(this._db);

  Stream<List<DeepNote>> watchDeepNotesForLecture(String lectureId) {
    final query = _db.select(_db.localDeepNotes)
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
  /// 生成したannotationのidを返す。DeepNoteはMarkdown文字列1本なのでblockIdxは無い。
  Future<String> addAnnotation({
    required String noteId,
    required int startIdx,
    required int endIdx,
    required String annotationType,
    required String annotatedWords,
    required dynamic contents,
  }) async {
    final annotationId = const Uuid().v4();
    await _updateMetadata(noteId, (metadata) {
      final annotations = _annotationsListOf(metadata);
      annotations.add(Annotation(
        id: annotationId,
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
  Future<void> removeAnnotation({required String noteId, required String annotationId}) async {
    await _updateMetadata(noteId, (metadata) {
      final annotations = _annotationsListOf(metadata);
      annotations.removeWhere((a) => a['id'] == annotationId);
      metadata['annotations'] = annotations;
    });
  }

  /// annotationIdの指定するannotationの内容を更新し、Outboxに登録する。
  /// 渡さなかったフィールドは既存の値を維持する。
  Future<void> updateAnnotation({
    required String noteId,
    required String annotationId,
    int? startIdx,
    int? endIdx,
    String? annotatedWords,
    dynamic contents,
  }) async {
    await _updateMetadata(noteId, (metadata) {
      final annotations = _annotationsListOf(metadata);
      final idx = annotations.indexWhere((a) => a['id'] == annotationId);
      if (idx == -1) return;

      final existing = Annotation.fromMap(Map<String, dynamic>.from(annotations[idx] as Map));
      annotations[idx] = Annotation(
        id: existing.id,
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
  /// [noteText]は残り部分のannotatedWordsを再計算するための、ノート全体の
  /// 現在のプレーンテキスト。
  Future<void> eraseHighlightRange({
    required String noteId,
    required int startIdx,
    required int endIdx,
    required String noteText,
  }) async {
    await _updateMetadata(noteId, (metadata) {
      final annotations = _annotationsListOf(metadata);
      final result = <dynamic>[];
      for (final raw in annotations) {
        final a = Annotation.fromMap(Map<String, dynamic>.from(raw as Map));
        final overlaps = a.annotationType == 'highlight' &&
            a.startIdx < endIdx &&
            a.endIdx > startIdx;
        if (!overlaps) {
          result.add(raw);
          continue;
        }
        if (a.startIdx < startIdx) {
          result.add(Annotation(
            id: const Uuid().v4(),
            startIdx: a.startIdx,
            endIdx: startIdx,
            annotationType: a.annotationType,
            annotatedWords: noteText.substring(a.startIdx, startIdx),
            contents: a.contents,
          ).toMap());
        }
        if (a.endIdx > endIdx) {
          result.add(Annotation(
            id: const Uuid().v4(),
            startIdx: endIdx,
            endIdx: a.endIdx,
            annotationType: a.annotationType,
            annotatedWords: noteText.substring(endIdx, a.endIdx),
            contents: a.contents,
          ).toMap());
        }
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
      final existing = await (_db.select(_db.localDeepNotes)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (existing == null) return;

      final metadata = existing.metadataJson != null
          ? Map<String, dynamic>.from(jsonDecode(existing.metadataJson!) as Map)
          : <String, dynamic>{};
      mutate(metadata);

      await (_db.update(_db.localDeepNotes)..where((t) => t.id.equals(id))).write(
        LocalDeepNotesCompanion(metadataJson: Value(jsonEncode(metadata))),
      );

      await _db.enqueueOutbox(
        entityType: 'deep_note',
        entityId: id,
        op: 'update',
      );
    });
  }

  DeepNote _toDomain(LocalDeepNote row) {
    final metadata = row.metadataJson != null
        ? Map<String, dynamic>.from(jsonDecode(row.metadataJson!) as Map)
        : null;
    return DeepNote(
      id: row.id,
      userId: row.userId,
      lectureId: row.lectureId,
      topicNumber: row.topicNumber,
      noteContents: row.noteContents,
      metadata: metadata,
      createdAt: row.createdAt,
    );
  }
}
