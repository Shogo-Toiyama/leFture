// lib/application/lecture_viewer/lecture_content_recovery.dart
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:lefture/application/sync/deep_note_sync_service.dart';
import 'package:lefture/application/sync/fun_fact_sync_service.dart';
import 'package:lefture/application/sync/keyword_sync_service.dart';
import 'package:lefture/application/sync/lecture_topic_sync_service.dart';
import 'package:lefture/application/sync/review_card_sync_service.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

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

/// NotStartedView(分析前の「分析を始める」画面)専用の復元処理。
///
/// マスター音声のローカルアセット行(localLectureAssets, type:
/// 'master_audio')は、アップロード完了時にUploadManagerが即座に書く
/// 楽観的なローカル記録でしかなく、サーバー側からpull同期で復元される
/// 対象ではない。そのため、アプリの再インストール等でローカルDBごと
/// 消えると、実際にはR2に音声が残っているにもかかわらず、この行が
/// 二度と復活せずプレイヤーが永久に表示されなくなる
/// (この行が無い=「アップロードされていない」としか判定できないため)。
///
/// 分析前の講義は、他の情報(トピックや書き起こし)がまだ何も無いため、
/// 「録れているのが本当に授業の音声か、雑音を誤って録ってしまっただけの
/// 講義(削除すべきもの)か」をユーザーが確認する唯一の手段が音声プレビュー
/// になる。そのためこの画面でだけは、ローカル行が無ければSupabaseの
/// `lectures.audio_path`(Cloud Run側がアップロード確認後にしか書かない
/// 列)を直接1回フェッチして復元する。LectureViewerPage全体(通常の
/// [ensureLectureContentAvailable])には入れない — 分析済みの講義を含む
/// 全ての講義表示のたびに音声を先読みしてしまい、重くなるため。
///
/// 一度アップロードされた音声は不変なデータなので、復元した値はローカルへ
/// 書き戻して以降は通常の[masterAudioAssetProvider]経路に乗せる
/// (この関数自体は自己修復の1回きりの処理で、行が既にあれば何もしない)。
Future<void> ensureMasterAudioAssetAvailable(
  AppDatabase db, {
  required String lectureId,
  required String userId,
}) async {
  final hasLocalAsset = await (db.select(db.localLectureAssets)
        ..where((t) => t.lectureId.equals(lectureId))
        ..where((t) => t.type.equals('master_audio'))
        ..limit(1))
      .get()
      .then((rows) => rows.isNotEmpty);
  if (hasLocalAsset) return;

  DevLog.add(
    '📥 [LectureContentRecovery] No local master audio asset for $lectureId — checking Supabase.',
  );
  try {
    final row = await supabase
        .from('lectures')
        .select('audio_path')
        .eq('id', lectureId)
        .maybeSingle();
    final audioPath = row?['audio_path'] as String?;
    if (audioPath == null || audioPath.isEmpty) return;

    final now = DateTime.now().toUtc();
    await db.into(db.localLectureAssets).insertOnConflictUpdate(
          LocalLectureAssetsCompanion(
            id: Value(const Uuid().v4()),
            userId: Value(userId),
            lectureId: Value(lectureId),
            type: const Value('master_audio'),
            sequenceIndex: const Value(-1),
            storagePath: Value(audioPath),
            uploadStatus: const Value('uploaded'),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    DevLog.add(
      '✅ [LectureContentRecovery] Restored master audio asset for $lectureId from Supabase.',
    );
  } catch (e, st) {
    DevLog.add(
      '🚨 [LectureContentRecovery] Failed to restore master audio asset for $lectureId: $e\n$st',
    );
  }
}
