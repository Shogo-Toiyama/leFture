import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lefture/application/sync/recent_lecture_scope.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/core/utils/network_constants.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

/// FunFactのPull(Supabase→ローカルDB)専用サービス。
/// [LectureSyncService]と同型の差分Pull(`updated_at`基準+24時間全件Pull
/// セーフティネット)。Supabase側に`updated_at`自動更新トリガーが整備された
/// ため、他デバイスでのreaction変更もこの差分Pullで検出できる。
/// 全件Pullは[RecentLectureScope]の直近講義に絞る(HomeのFun Factカルーセルは
/// 新しい順に5件なので直近講義で足りる。古い講義は開いた時に
/// [pullForLectures]で取る)。
class FunFactSyncService {
  final AppDatabase _db;

  FunFactSyncService(this._db);

  static const entityType = 'fun_fact';
  static const _table = 'fun_facts';
  static const _fullPullSafetyNet = Duration(hours: 24);

  Future<void> pull({bool forceFullPull = false, RecentLectureScope? scope}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final cursor = await _db.getSyncCursor(uid, entityType);
    final now = DateTime.now().toUtc();

    final needsFullPull = forceFullPull ||
        cursor?.lastFullPulledAt == null ||
        now.difference(cursor!.lastFullPulledAt!) >= _fullPullSafetyNet;

    final localCount = await _db.getLocalFunFactsCount(uid);
    final effectiveLastPullAt =
        (needsFullPull || localCount == 0) ? null : cursor.lastPulledAt;

    // 全件Pullは直近講義の範囲だけ。差分Pullはユーザー全体(変わった行しか
    // 返らないので軽く、古い講義の更新もここで受け取れる)。
    final List<String>? scopedIds = effectiveLastPullAt == null
        ? await (scope ?? RecentLectureScope()).recentLectureIds(uid)
        : null;

    final List<dynamic> data;
    if (scopedIds != null) {
      data = await fetchRowsForLectures(_table, uid, scopedIds);
    } else {
      final skewBuffer = effectiveLastPullAt!.subtract(const Duration(minutes: 5));
      data = await supabase
          .from(_table)
          .select()
          .eq('user_id', uid)
          .gt('updated_at', skewBuffer.toIso8601String())
          .timeout(networkTimeout);
    }

    DateTime? maxUpdatedAt = cursor?.lastPulledAt;
    for (final json in data) {
      final updatedAt = DateTime.parse(json['updated_at']);
      if (maxUpdatedAt == null || updatedAt.isAfter(maxUpdatedAt)) {
        maxUpdatedAt = updatedAt;
      }
    }

    await _write(uid, data, now, reconcileLectureIds: scopedIds);
    if (data.isNotEmpty) {
      DevLog.add('📥 [FunFactSync] Pulled ${data.length} fun fact(s) from cloud'
          '${scopedIds != null ? ' (full, ${scopedIds.length} recent lecture(s))' : ''}.');
    }

    await _db.upsertSyncCursor(
      userId: uid,
      entityType: entityType,
      lastPulledAt: maxUpdatedAt,
      updateLastFullPulledAt: needsFullPull,
      lastFullPulledAt: needsFullPull ? now : null,
    );
    if (scopedIds != null) scope?.markFullPulled(entityType);
  }

  /// 指定した講義の行だけをSupabaseから無条件Pullし、サーバー側で消えた行
  /// (解析のやり直し等で物理削除されたもの)はローカルからも消す。
  /// 通常の[pull]と違い、`updated_at`での差分判定やsyncカーソルの更新は
  /// 行わない(全体同期のカーソルを狂わせないため)。
  Future<void> pullForLectures(List<String> lectureIds) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null || lectureIds.isEmpty) return;

    final data = await fetchRowsForLectures(_table, uid, lectureIds);
    await _write(uid, data, DateTime.now().toUtc(), reconcileLectureIds: lectureIds);
    DevLog.add('📥 [FunFactSync] Refreshed ${data.length} fun fact(s) for ${lectureIds.length} lecture(s).');
  }

  Future<void> pullForLecture(String lectureId) => pullForLectures([lectureId]);

  /// プロフィールの記録用に、リアクション済みの行を講義に関係なく取る。
  /// 取れた行の講義IDを返す。
  Future<Set<String>> pullFlagged() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return const {};
    final data = await fetchFlaggedRows(_table, uid);
    await _write(uid, data, DateTime.now().toUtc());
    return data.map((j) => j['lecture_id'] as String).toSet();
  }

  /// [reconcileLectureIds]を渡すと、それらの講義について[data]に無いローカル行を
  /// 削除する([data]がその講義群の完全な集合である時だけ渡すこと)。
  Future<void> _write(
    String uid,
    List<dynamic> data,
    DateTime now, {
    List<String>? reconcileLectureIds,
  }) async {
    // まだPushできていないローカルのreaction変更を、サーバーの古い値で
    // 上書き/削除しないためのガード。
    final pendingIds = await _db.getPendingOutboxEntityIds(entityType);

    final companions = data.map((json) {
      final id = json['id'] as String;
      final metadata = json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null;
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
        updatedAt: Value(DateTime.parse(json['updated_at'])),
        deletedAt: Value(
          json['deleted_at'] == null ? null : DateTime.parse(json['deleted_at'] as String),
        ),
        lastSyncedAt: Value(now),
      );
    }).toList();

    await _db.transaction(() async {
      if (reconcileLectureIds != null && reconcileLectureIds.isNotEmpty) {
        final keepIds = {...data.map((j) => j['id'] as String), ...pendingIds}.toList();
        await (_db.delete(_db.localFunFacts)
              ..where((t) =>
                  t.userId.equals(uid) &
                  t.lectureId.isIn(reconcileLectureIds) &
                  (keepIds.isEmpty ? const Constant(true) : t.id.isNotIn(keepIds))))
            .go();
      }
      if (companions.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(_db.localFunFacts, companions);
        });
      }
    });
  }
}
