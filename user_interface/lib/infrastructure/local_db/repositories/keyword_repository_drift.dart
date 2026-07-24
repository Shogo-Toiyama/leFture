import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:lefture/domain/entities/keyword.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'keyword_repository_drift.g.dart';

@Riverpod(keepAlive: true)
KeywordRepositoryDrift keywordRepositoryDrift(Ref ref) {
  return KeywordRepositoryDrift(ref.watch(appDatabaseProvider));
}

/// Keywordはサーバー生成コンテンツ。
/// ユーザーによるSave(ブックマーク)操作の書き込みと、Pull(Supabase→ローカルDB)をサポート。
class KeywordRepositoryDrift {
  final AppDatabase _db;

  KeywordRepositoryDrift(this._db);

  Stream<List<Keyword>> watchKeywordsForLecture(String lectureId) {
    final query = _db.select(_db.localKeywords)
      ..where((t) => t.lectureId.equals(lectureId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.topicNumber)]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  Future<void> toggleSaveKeyword({
    required String keywordId,
    required String userId,
    required bool isSaved,
    String? existingMetadataJson,
  }) async {
    Map<String, dynamic> metadataMap = {};
    if (existingMetadataJson != null && existingMetadataJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(existingMetadataJson);
        if (decoded is Map<String, dynamic>) {
          metadataMap = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    if (isSaved) {
      metadataMap['saved'] = true;
    } else {
      metadataMap.remove('saved');
    }

    final newMetadataJson = metadataMap.isEmpty ? null : jsonEncode(metadataMap);

    await _db.updateKeywordMetadata(
      id: keywordId,
      userId: userId,
      metadataJson: newMetadataJson,
    );

    // Queue outbox for background sync to Supabase
    await _db.enqueueOutbox(
      entityType: 'keyword',
      entityId: keywordId,
      op: 'update',
    );
  }

  Keyword _toDomain(LocalKeyword row) {
    return Keyword(
      id: row.id,
      userId: row.userId,
      lectureId: row.lectureId,
      topicNumber: row.topicNumber,
      keyword: row.keyword,
      definition: row.definition,
      metadataJson: row.metadataJson,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
    );
  }
}
