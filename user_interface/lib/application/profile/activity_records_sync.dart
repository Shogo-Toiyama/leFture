import 'package:lefture/application/profile/activity_records_provider.dart';
import 'package:lefture/application/sync/announcement_sync_service.dart';
import 'package:lefture/application/sync/deep_note_sync_service.dart';
import 'package:lefture/application/sync/fun_fact_sync_service.dart';
import 'package:lefture/application/sync/keyword_sync_service.dart';
import 'package:lefture/application/sync/lecture_content_sync.dart';
import 'package:lefture/application/sync/review_card_sync_service.dart';
import 'package:lefture/core/utils/connectivity_utils.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

/// 保存・いいね・よくないの記録を最後に取り直した時刻のカーソル。
const _flaggedEntityType = 'activity_flagged';
const _flaggedFreshness = Duration(hours: 24);

/// プロフィールの記録ページを開いた時用。記録はローカルDBを横断して
/// 集計しているが、起動時は直近講義の子データしか取っていないため、古い講義で
/// 保存・リアクションした行やお知らせはここで取る。前回から24時間以内なら
/// ローカルをそのまま使う。
///
/// 取れた行はローカルDBのStreamを通じて[activityRecordsProvider]に自動で
/// 反映される。失敗はログだけ残す(ローカルにある分は表示できているため)。
Future<void> refreshActivityRecordsIfStale(AppDatabase db, ActivityType type) async {
  try {
    if (!await isDeviceOnline()) return;
    switch (type) {
      case ActivityType.saved:
      case ActivityType.likes:
      case ActivityType.dislikes:
        await _refreshFlaggedIfStale(db);
      case ActivityType.announcements:
      case ActivityType.trash:
        await AnnouncementSyncService(db).pullAllIfStale();
    }
  } catch (e, st) {
    DevLog.add('⚠️ [ActivityRecordsSync] refresh for $type failed: $e\n$st');
  }
}

Future<void> _refreshFlaggedIfStale(AppDatabase db) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return;

  final cursor = await db.getSyncCursor(uid, _flaggedEntityType);
  final now = DateTime.now().toUtc();
  final last = cursor?.lastFullPulledAt;
  if (last != null && now.difference(last) < _flaggedFreshness) return;

  final lectureIdSets = await Future.wait([
    ReviewCardSyncService(db).pullFlagged(),
    DeepNoteSyncService(db).pullFlagged(),
    KeywordSyncService(db).pullFlagged(),
    FunFactSyncService(db).pullFlagged(),
  ]);

  // 記録のカードには講義のトピック名なども出るので、保存・リアクションした
  // 行がある講義は中身ごと(古ければ)取る。
  final lectureIds = {for (final s in lectureIdSets) ...s}.toList();
  await LectureContentSync(db).ensureFresh(lectureIds);

  await db.upsertSyncCursor(
    userId: uid,
    entityType: _flaggedEntityType,
    updateLastPulledAt: false,
    updateLastFullPulledAt: true,
    lastFullPulledAt: now,
  );
  DevLog.add('📥 [ActivityRecordsSync] Refreshed flagged rows across ${lectureIds.length} lecture(s).');
}
