import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lefture/application/sync/recent_lecture_scope.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/core/utils/network_constants.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

/// KeywordのPull(Supabase→ローカルDB)専用サービス。キーワード本体はサーバー
/// 生成で、ユーザーが変えられるのは`metadata`(保存等)と語句の編集
/// (Push側は[KeywordOutboxPushHandler])。
/// [LectureSyncService]と同型の差分Pull(`updated_at`基準+24時間全件Pull
/// セーフティネット)。ただし全件Pullは[RecentLectureScope]の直近講義に
/// 絞る(古い講義は開いた時に[pullForLectures]で取る)。
class KeywordSyncService {
  final AppDatabase _db;

  KeywordSyncService(this._db);

  static const entityType = 'keyword';
  static const _table = 'keywords';
  static const _fullPullSafetyNet = Duration(hours: 24);

  Future<void> pull({bool forceFullPull = false, RecentLectureScope? scope}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final cursor = await _db.getSyncCursor(uid, entityType);
    final now = DateTime.now().toUtc();

    final needsFullPull = forceFullPull ||
        cursor?.lastFullPulledAt == null ||
        now.difference(cursor!.lastFullPulledAt!) >= _fullPullSafetyNet;

    final localCount = await (_db.select(_db.localKeywords)
          ..where((t) => t.userId.equals(uid) & t.deletedAt.isNull()))
        .get()
        .then((rows) => rows.length);
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
      DevLog.add('📥 [KeywordSync] Pulled ${data.length} keyword(s) from cloud'
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
    DevLog.add('📥 [KeywordSync] Refreshed ${data.length} keyword(s) for ${lectureIds.length} lecture(s).');
  }

  Future<void> pullForLecture(String lectureId) => pullForLectures([lectureId]);

  /// プロフィールの記録用に、保存済みの行を講義に関係なく取る。
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
    // まだPushできていないローカルの変更(保存・語句の編集)を、サーバーの
    // 古い値で上書き/削除しないためのガード。
    final pendingIds = await _db.getPendingOutboxEntityIds(entityType);

    final companions = data.where((json) => !pendingIds.contains(json['id'] as String)).map((json) {
      return LocalKeywordsCompanion(
        id: Value(json['id'] as String),
        userId: Value(json['user_id'] as String),
        lectureId: Value(json['lecture_id'] as String),
        topicNumber: Value((json['topic_number'] as num?)?.toInt() ?? 0),
        keyword: Value(json['keyword'] as String? ?? ''),
        definition: Value(json['definition'] as String? ?? ''),
        // 以前はmetadata(保存フラグ)をPullしていなかったため、別端末で
        // 保存したキーワードがこの端末の記録に出なかった。
        metadataJson: Value(json['metadata'] != null ? jsonEncode(json['metadata']) : null),
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
        await (_db.delete(_db.localKeywords)
              ..where((t) =>
                  t.userId.equals(uid) &
                  t.lectureId.isIn(reconcileLectureIds) &
                  (keepIds.isEmpty ? const Constant(true) : t.id.isNotIn(keepIds))))
            .go();
      }
      if (companions.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(_db.localKeywords, companions);
        });
      }
    });
  }
}
