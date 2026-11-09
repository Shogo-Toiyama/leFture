import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lefture/application/sync/recent_lecture_scope.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/core/utils/network_constants.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

/// AnnouncementのPull(Supabase→ローカルDB)専用サービス。
/// [LectureSyncService]と同型の差分Pull(`updated_at`基準+24時間全件Pull
/// セーフティネット)。
///
/// 全件Pullの範囲は「未完了のお知らせは全講義から」+「直近講義のお知らせは
/// 完了済みも含めて全て」。Homeのお知らせバーは全講義の未完了分から最新を
/// 出すため、未完了分は講義で絞れない(第1回の講義で告知された期末試験など)。
/// 完了済みの古いお知らせは、お知らせシート/記録ページを開いた時に
/// [pullAllIfStale]で取る。
class AnnouncementSyncService {
  final AppDatabase _db;

  AnnouncementSyncService(this._db);

  static const entityType = 'announcement';
  static const _table = 'announcements';
  static const _fullPullSafetyNet = Duration(hours: 24);

  /// [pullAllIfStale]用の、ユーザー全体の全件Pullの時刻を記録するカーソル。
  static const _allEntityType = 'announcement_all';
  static const _allFreshness = Duration(hours: 24);

  Future<void> pull({bool forceFullPull = false, RecentLectureScope? scope}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final cursor = await _db.getSyncCursor(uid, entityType);
    final now = DateTime.now().toUtc();

    final needsFullPull = forceFullPull ||
        cursor?.lastFullPulledAt == null ||
        now.difference(cursor!.lastFullPulledAt!) >= _fullPullSafetyNet;

    final localCount = await (_db.select(_db.localAnnouncements)
          ..where((t) => t.userId.equals(uid) & t.deletedAt.isNull()))
        .get()
        .then((rows) => rows.length);
    final effectiveLastPullAt =
        (needsFullPull || localCount == 0) ? null : cursor.lastPulledAt;

    final List<String>? scopedIds = effectiveLastPullAt == null
        ? await (scope ?? RecentLectureScope()).recentLectureIds(uid)
        : null;

    var query = supabase.from(_table).select().eq('user_id', uid);
    if (scopedIds != null) {
      query = scopedIds.isEmpty
          ? query.isFilter('completed_at', null)
          : query.or('completed_at.is.null,lecture_id.in.(${scopedIds.join(',')})');
    } else {
      final skewBuffer = effectiveLastPullAt!.subtract(const Duration(minutes: 5));
      query = query.gt('updated_at', skewBuffer.toIso8601String());
    }

    final List<dynamic> data = await query.timeout(networkTimeout);

    DateTime? maxUpdatedAt = cursor?.lastPulledAt;
    for (final json in data) {
      final updatedAt = DateTime.parse(json['updated_at']);
      if (maxUpdatedAt == null || updatedAt.isAfter(maxUpdatedAt)) {
        maxUpdatedAt = updatedAt;
      }
    }

    // 直近講義のお知らせは完了済みも含めて全て取れているので、それらの講義に
    // ついてはサーバーに無いローカル行を消せる(他の講義の行には触らない)。
    await _write(uid, data, reconcileLectureIds: scopedIds);
    if (data.isNotEmpty) {
      DevLog.add('📥 [AnnouncementSync] Pulled ${data.length} announcement(s) from cloud'
          '${scopedIds != null ? ' (full, active + ${scopedIds.length} recent lecture(s))' : ''}.');
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

  /// 指定した講義のお知らせを全てPullし、サーバー側で消えた行はローカルからも
  /// 消す。syncカーソルは更新しない。
  Future<void> pullForLectures(List<String> lectureIds) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null || lectureIds.isEmpty) return;

    final data = await fetchRowsForLectures(_table, uid, lectureIds);
    await _write(uid, data, reconcileLectureIds: lectureIds);
    DevLog.add('📥 [AnnouncementSync] Refreshed ${data.length} announcement(s) for ${lectureIds.length} lecture(s).');
  }

  /// お知らせシート(全体・コース)や記録ページを開いた時用。ユーザーの
  /// お知らせを講義に関係なく全てPullする。ただし前回から24時間以内なら
  /// ローカルをそのまま使う。実際に取り直した時はtrueを返す。
  Future<bool> pullAllIfStale() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return false;

    final cursor = await _db.getSyncCursor(uid, _allEntityType);
    final now = DateTime.now().toUtc();
    final last = cursor?.lastFullPulledAt;
    if (last != null && now.difference(last) < _allFreshness) return false;

    final List<dynamic> data =
        await supabase.from(_table).select().eq('user_id', uid).timeout(networkTimeout);
    await _write(uid, data, reconcileAll: true);
    DevLog.add('📥 [AnnouncementSync] Pulled all ${data.length} announcement(s) for sheet/records.');

    await _db.upsertSyncCursor(
      userId: uid,
      entityType: _allEntityType,
      updateLastPulledAt: false,
      updateLastFullPulledAt: true,
      lastFullPulledAt: now,
    );
    return true;
  }

  /// [reconcileLectureIds]を渡すとそれらの講義について、[reconcileAll]なら
  /// ユーザー全体について、[data]に無いローカル行を削除する([data]がその範囲の
  /// 完全な集合である時だけ指定すること)。
  Future<void> _write(
    String uid,
    List<dynamic> data, {
    List<String>? reconcileLectureIds,
    bool reconcileAll = false,
  }) async {
    // まだPushできていないローカルのcompleted_at変更(や未送信の行)を、
    // サーバーの古い値で上書き/削除しないためのガード。
    final pendingIds = await _db.getPendingOutboxEntityIds(entityType);

    final companions = data.map((json) {
      final id = json['id'] as String;
      final isPending = pendingIds.contains(id);
      final metadata = json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null;
      final datetimeParameters = json['datetime_parameters'] != null
          ? Map<String, dynamic>.from(json['datetime_parameters'] as Map)
          : null;

      return LocalAnnouncementsCompanion(
        id: Value(id),
        userId: Value(json['user_id'] as String),
        lectureId: Value(json['lecture_id'] as String),
        type: Value(json['type'] as String? ?? 'INFO'),
        title: Value(json['title'] as String? ?? ''),
        description: Value(json['description'] as String?),
        location: Value(json['location'] as String?),
        startSid: Value(json['start_sid'] as String?),
        endSid: Value(json['end_sid'] as String?),
        relatedTopicTitle: Value(json['related_topic_title'] as String?),
        datetimeParametersJson:
            Value(datetimeParameters != null ? jsonEncode(datetimeParameters) : null),
        // ローカルに未Pushの変更が無い場合のみサーバー値で上書きする
        completedAt: isPending
            ? const Value.absent()
            : Value(json['completed_at'] == null
                ? null
                : DateTime.parse(json['completed_at'] as String)),
        metadataJson: Value(metadata != null ? jsonEncode(metadata) : null),
        createdAt: Value(DateTime.parse(json['created_at'])),
        updatedAt: Value(DateTime.parse(json['updated_at'])),
        deletedAt: Value(
          json['deleted_at'] == null ? null : DateTime.parse(json['deleted_at'] as String),
        ),
        syncStatus: const Value('synced'),
      );
    }).toList();

    await _db.transaction(() async {
      final reconcileScoped = reconcileLectureIds != null && reconcileLectureIds.isNotEmpty;
      if (reconcileAll || reconcileScoped) {
        final keepIds = {...data.map((j) => j['id'] as String), ...pendingIds}.toList();
        await (_db.delete(_db.localAnnouncements)
              ..where((t) {
                Expression<bool> cond = t.userId.equals(uid);
                if (!reconcileAll) cond = cond & t.lectureId.isIn(reconcileLectureIds!);
                if (keepIds.isNotEmpty) cond = cond & t.id.isNotIn(keepIds);
                return cond;
              }))
            .go();
      }
      if (companions.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(_db.localAnnouncements, companions);
        });
      }
    });
  }
}
