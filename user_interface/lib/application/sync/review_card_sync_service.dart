import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lefture/application/sync/recent_lecture_scope.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/core/utils/network_constants.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

/// ReviewCardのPull(Supabase→ローカルDB)専用サービス。カード本体はサーバー
/// 生成で、ユーザーが変えられるのは`metadata`(保存・リアクション)だけ
/// (Push側は[ReviewCardOutboxPushHandler])。
/// [LectureSyncService]と同型の差分Pull(`updated_at`基準+24時間全件Pull
/// セーフティネット)。ただし全件Pullは[RecentLectureScope]の直近講義に
/// 絞る(古い講義は開いた時に[pullForLectures]で取る)。
class ReviewCardSyncService {
  final AppDatabase _db;

  ReviewCardSyncService(this._db);

  static const entityType = 'review_card';
  static const _table = 'review_cards';
  static const _fullPullSafetyNet = Duration(hours: 24);

  Future<void> pull({bool forceFullPull = false, RecentLectureScope? scope}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final cursor = await _db.getSyncCursor(uid, entityType);
    final now = DateTime.now().toUtc();

    final needsFullPull = forceFullPull ||
        cursor?.lastFullPulledAt == null ||
        now.difference(cursor!.lastFullPulledAt!) >= _fullPullSafetyNet;

    final localCount = await (_db.select(_db.localReviewCards)
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
      DevLog.add('📥 [ReviewCardSync] Pulled ${data.length} review card(s) from cloud'
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
    DevLog.add('📥 [ReviewCardSync] Refreshed ${data.length} review card(s) for ${lectureIds.length} lecture(s).');
  }

  Future<void> pullForLecture(String lectureId) => pullForLectures([lectureId]);

  /// プロフィールの記録用に、保存・リアクション済みの行を講義に関係なく取る。
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
    // まだPushできていないローカルの保存・リアクション変更を、サーバーの
    // 古い値で上書き/削除しないためのガード。
    final pendingIds = await _db.getPendingOutboxEntityIds(entityType);

    final companions = data.map((json) {
      final id = json['id'] as String;
      final cardContent = json['card_content'];
      return LocalReviewCardsCompanion(
        id: Value(id),
        userId: Value(json['user_id'] as String),
        lectureId: Value(json['lecture_id'] as String),
        topicNumber: Value((json['topic_number'] as num?)?.toInt() ?? 0),
        cardContentJson: Value(jsonEncode(cardContent ?? const [])),
        cardType: Value(json['card_type'] as String? ?? ''),
        title: Value(json['title'] as String?),
        heroEmoji: Value(json['hero_emoji'] as String?),
        metadataJson: pendingIds.contains(id)
            ? const Value.absent()
            : Value(json['metadata'] != null ? jsonEncode(json['metadata']) : null),
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
        await (_db.delete(_db.localReviewCards)
              ..where((t) =>
                  t.userId.equals(uid) &
                  t.lectureId.isIn(reconcileLectureIds) &
                  (keepIds.isEmpty ? const Constant(true) : t.id.isNotIn(keepIds))))
            .go();
      }
      if (companions.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(_db.localReviewCards, companions);
        });
      }
    });
  }
}
