import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/core/utils/network_constants.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

/// FunFactのPull(Supabase→ローカルDB)専用サービス。
/// [LectureSyncService]と同型の差分Pull(`updated_at`基準+24時間全件Pull
/// セーフティネット)。Supabase側に`updated_at`自動更新トリガーが整備された
/// ため、他デバイスでのreaction変更もこの差分Pullで検出できる。
class FunFactSyncService {
  final AppDatabase _db;

  FunFactSyncService(this._db);

  static const _entityType = 'fun_fact';
  static const _fullPullSafetyNet = Duration(hours: 24);

  Future<void> pull({bool forceFullPull = false}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final cursor = await _db.getSyncCursor(uid, _entityType);
    final now = DateTime.now().toUtc();

    final needsFullPull = forceFullPull ||
        cursor?.lastFullPulledAt == null ||
        now.difference(cursor!.lastFullPulledAt!) >= _fullPullSafetyNet;

    final localCount = await _db.getLocalFunFactsCount(uid);
    final effectiveLastPullAt =
        (needsFullPull || localCount == 0) ? null : cursor.lastPulledAt;

    var query = supabase.from('fun_facts').select().eq('user_id', uid);
    if (effectiveLastPullAt != null) {
      final skewBuffer = effectiveLastPullAt.subtract(const Duration(minutes: 5));
      query = query.gt('updated_at', skewBuffer.toIso8601String());
    }

    final List<dynamic> data = await query.timeout(networkTimeout);

    DateTime? maxUpdatedAt = cursor?.lastPulledAt;
    if (data.isNotEmpty) {
      // まだPushできていないローカルのreaction変更を、サーバーの古い値で
      // 上書きしないためのガード。
      final pendingIds = await _db.getPendingOutboxEntityIds(_entityType);

      final companions = data.map((json) {
        final updatedAt = DateTime.parse(json['updated_at']);
        if (maxUpdatedAt == null || updatedAt.isAfter(maxUpdatedAt!)) {
          maxUpdatedAt = updatedAt;
        }

        final id = json['id'] as String;
        final metadata = json['metadata'] as Map<String, dynamic>?;
        final isPending = pendingIds.contains(id);

        return LocalFunFactsCompanion(
          id: Value(id),
          userId: Value(json['user_id'] as String),
          lectureId: Value(json['lecture_id'] as String),
          title: Value(json['title'] as String?),
          hook: Value(json['hook'] as String? ?? ''),
          body: Value(json['body'] as String? ?? ''),
          metadataJson: Value(metadata != null ? jsonEncode(metadata) : null),
          // ローカルに未Pushの変更が無い場合のみサーバー値で上書きする
          reaction: isPending
              ? const Value.absent()
              : Value(metadata?['reaction'] as String?),
          createdAt: Value(DateTime.parse(json['created_at'])),
          updatedAt: Value(updatedAt),
          deletedAt: Value(
            json['deleted_at'] == null ? null : DateTime.parse(json['deleted_at'] as String),
          ),
          lastSyncedAt: Value(now),
        );
      }).toList();

      await _db.batch((batch) {
        batch.insertAllOnConflictUpdate(_db.localFunFacts, companions);
      });

      DevLog.add('📥 [FunFactSync] Pulled ${companions.length} fun fact(s) from cloud.');
    }

    await _db.upsertSyncCursor(
      userId: uid,
      entityType: _entityType,
      lastPulledAt: maxUpdatedAt,
      updateLastFullPulledAt: needsFullPull,
      lastFullPulledAt: needsFullPull ? now : null,
    );
  }

  /// 特定の講義1件分だけをSupabaseから無条件Pullする。ローカルキャッシュの
  /// 容量上限([LocalRetentionService.enforceCacheBudget])によってその講義の
  /// 行が削除された後、講義ページを開いた際に復元するための経路。
  /// 通常の[pull]と違い、`updated_at`での差分判定やsyncカーソルの更新は
  /// 行わない(全体同期のカーソルを狂わせないため)。
  Future<void> pullForLecture(String lectureId) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final now = DateTime.now().toUtc();
    final List<dynamic> data = await supabase
        .from('fun_facts')
        .select()
        .eq('user_id', uid)
        .eq('lecture_id', lectureId)
        .timeout(networkTimeout);

    if (data.isEmpty) return;

    // まだPushできていないローカルのreaction変更を、サーバーの古い値で
    // 上書きしないためのガード(通常のpullと同じ配慮)。
    final pendingIds = await _db.getPendingOutboxEntityIds(_entityType);

    final companions = data.map((json) {
      final id = json['id'] as String;
      final metadata = json['metadata'] as Map<String, dynamic>?;
      final isPending = pendingIds.contains(id);

      return LocalFunFactsCompanion(
        id: Value(id),
        userId: Value(json['user_id'] as String),
        lectureId: Value(json['lecture_id'] as String),
        title: Value(json['title'] as String?),
        hook: Value(json['hook'] as String? ?? ''),
        body: Value(json['body'] as String? ?? ''),
        metadataJson: Value(metadata != null ? jsonEncode(metadata) : null),
        reaction: isPending
            ? const Value.absent()
            : Value(metadata?['reaction'] as String?),
        createdAt: Value(DateTime.parse(json['created_at'])),
        updatedAt: Value(DateTime.parse(json['updated_at'])),
        deletedAt: Value(
          json['deleted_at'] == null ? null : DateTime.parse(json['deleted_at'] as String),
        ),
        lastSyncedAt: Value(now),
      );
    }).toList();

    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(_db.localFunFacts, companions);
    });

    DevLog.add('📥 [FunFactSync] Restored ${companions.length} fun fact(s) for lecture $lectureId.');
  }
}
