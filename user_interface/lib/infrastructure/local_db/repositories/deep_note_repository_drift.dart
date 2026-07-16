import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lecture_companion_ui/domain/entities/deep_note.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

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
