import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lecture_companion_ui/domain/entities/fun_fact.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'fun_fact_repository_drift.g.dart';

@Riverpod(keepAlive: true)
FunFactRepositoryDrift funFactRepositoryDrift(Ref ref) {
  return FunFactRepositoryDrift(ref.watch(appDatabaseProvider));
}

class FunFactRepositoryDrift {
  final AppDatabase _db;

  FunFactRepositoryDrift(this._db);

  /// 講義に紐づくFunFact一覧(新しい順、論理削除除外)を監視する。
  Stream<List<FunFact>> watchFunFactsForLecture(String lectureId) {
    final query = _db.select(_db.localFunFacts)
      ..where((t) => t.lectureId.equals(lectureId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  /// 最新のFunFactを最大[limit]件監視する(ユーザー全体、論理削除除外)。
  Stream<List<FunFact>> watchRecentFunFacts(String userId, {int limit = 5}) {
    final query = _db.select(_db.localFunFacts)
      ..where((t) => t.userId.equals(userId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  /// reactionを即時ローカル更新(楽観的UI)し、Outboxに登録する。
  Future<void> updateReaction({required String id, required String? reaction}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    await _db.transaction(() async {
      await (_db.update(_db.localFunFacts)..where((t) => t.id.equals(id))).write(
        LocalFunFactsCompanion(reaction: Value(reaction)),
      );

      await _db.enqueueOutbox(
        entityType: 'fun_fact',
        entityId: id,
        op: 'update',
      );
    });
  }

  FunFact _toDomain(LocalFunFact row) {
    final metadata = row.metadataJson != null
        ? Map<String, dynamic>.from(jsonDecode(row.metadataJson!) as Map)
        : null;
    return FunFact(
      id: row.id,
      userId: row.userId,
      lectureId: row.lectureId,
      title: row.title,
      hook: row.hook,
      body: row.body,
      metadata: metadata,
      reaction: row.reaction,
      createdAt: row.createdAt,
    );
  }
}
