// lib/application/lecture_viewer/lecture_content_recovery.dart
import 'package:drift/drift.dart';

import 'package:lecture_companion_ui/application/sync/deep_note_sync_service.dart';
import 'package:lecture_companion_ui/application/sync/fun_fact_sync_service.dart';
import 'package:lecture_companion_ui/application/sync/keyword_sync_service.dart';
import 'package:lecture_companion_ui/application/sync/lecture_topic_sync_service.dart';
import 'package:lecture_companion_ui/application/sync/review_card_sync_service.dart';
import 'package:lecture_companion_ui/core/utils/dev_log.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';

/// [LocalRetentionService.enforceCacheBudget]の1GB LRU削除は、講義の
/// キャッシュファイルを削除する際に、Review Card/Deep Note/Fun Fact/Keyword/
/// Topicのローカル行も一緒に削除する。これらは元々「サーバー生成コンテンツの
/// 読み取り専用キャッシュ」でしかないため、ローカルから消えてもSupabase側には
/// 残っている — しかし、通常のPull(`*SyncService.pull()`)は`updated_at`の
/// 差分ベースなので、既に一度Pull済みとして扱われたこの講義の行は再取得
/// されない。放置すると、キャッシュが剥がれた講義を二度と開けなくなる。
///
/// この関数は講義ページを開いた瞬間に呼ばれ、ローカルにトピックが1件も
/// 無ければ「キャッシュ剥がれ」とみなし、その講義IDだけを対象にSupabaseから
/// 無条件で再取得する。画像本体は`imagePath`さえ戻れば
/// `artifactFileProvider`が表示時に自動でR2から取り直すため、ここでは
/// メタデータ(DB行)の復元だけを行う。
Future<void> ensureLectureContentAvailable(AppDatabase db, String lectureId) async {
  final hasLocalTopics = await (db.select(db.localLectureTopics)
        ..where((t) => t.lectureId.equals(lectureId) & t.deletedAt.isNull())
        ..limit(1))
      .get()
      .then((rows) => rows.isNotEmpty);
  if (hasLocalTopics) return;

  DevLog.add('📥 [LectureContentRecovery] No local content for lecture $lectureId — re-pulling from Supabase.');
  try {
    await Future.wait([
      LectureTopicSyncService(db).pullForLecture(lectureId),
      ReviewCardSyncService(db).pullForLecture(lectureId),
      DeepNoteSyncService(db).pullForLecture(lectureId),
      FunFactSyncService(db).pullForLecture(lectureId),
      KeywordSyncService(db).pullForLecture(lectureId),
    ]);
  } catch (e, st) {
    DevLog.add('🚨 [LectureContentRecovery] Failed to restore content for lecture $lectureId: $e\n$st');
  }
}
