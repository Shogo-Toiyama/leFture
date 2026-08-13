// lib/application/lecture_viewer/pipeline_reveal_sync.dart
//
// LectureViewerPageの「完成した要素から出していく」演出を、実際のデータ到着と
// 揃えるための同期フック。
//
// processing_tasksはCloud Tasksがサーバー側で更新するだけで、それだけでは
// Flutter側のローカルDB(=画面が実際に読んでいるデータ源)には何も届かない。
// タスクが3秒ポーリング(job_providers.dart)でCOMPLETEDになったのを検知した
// タイミングで、そのタスクが書いたテーブルだけを狙い撃ちしてPullする。
// 全件bootstrapLecturesではなく対象を絞ることで、1ジョブあたり最大12回程度
// 起き得る「要素の完成」のたびに無駄な全件同期が走るのを避ける。
//
// FINALIZE_JOBだけは対象外 —— ジョブ完了時の全件bootstrapは既に
// lecture_viewer_page.dart側のref.listen(lectureStateProvider)がuiState==
// completeの遷移で行っているため、ここで重複して行う必要が無い。

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/sync/announcement_sync_service.dart';
import 'package:lefture/application/sync/deep_note_sync_service.dart';
import 'package:lefture/application/sync/fun_fact_sync_service.dart';
import 'package:lefture/application/sync/keyword_sync_service.dart';
import 'package:lefture/application/sync/lecture_sync_service.dart';
import 'package:lefture/application/sync/lecture_topic_sync_service.dart';
import 'package:lefture/application/sync/review_card_sync_service.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/domain/entities/processing_task.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';

/// task_type完了 -> その完了で新しく読めるようになるテーブルをPullするための
/// サービス群。1つのtask_typeが複数テーブルに書く場合は複数返す
/// (例: CORE_EXTRACTIONはlectures.summaryとkeywordsの両方を書く)。
List<Future<void> Function()> _pullFnsForTaskType(String taskType, AppDatabase db) {
  switch (taskType) {
    case 'CORE_EXTRACTION':
      return [
        () => LectureSyncService(db).pull(),
        () => KeywordSyncService(db).pull(),
      ];
    case 'ANNOUNCEMENT_GENERATION':
      return [() => AnnouncementSyncService(db).pull()];
    case 'DETAIL_CONTENTS_GENERATION':
      return [
        () => LectureTopicSyncService(db).pull(),
        () => DeepNoteSyncService(db).pull(),
      ];
    case 'REVIEW_CARD_GENERATION':
      return [() => ReviewCardSyncService(db).pull()];
    case 'FUN_FACTS_GENERATION':
      return [() => FunFactSyncService(db).pull()];
    default:
      // TRANSCRIBE_MASTER/CHECK_AND_ASSEMBLE/ROLE_CLASSIFICATION/TOPIC_MAPPING/
      // IMAGE_PROMPT_GENERATION/IMAGE_RENDERING/FUN_FACT_BRAINSTORMING/
      // FUN_FACT_SEARCH/FINALIZE_JOBは、これ単独でPullすべきユーザー可視データを
      // 持たない(中間生成物のみ、またはFINALIZE_JOBは上記の通り既存経路がカバー)。
      return const [];
  }
}

/// [tasks]の中でCOMPLETEDに「新しく」なったtask_typeを検知するたびに、対応する
/// テーブルだけを差分Pullする。同じlectureIdの間は既にPull済みのtask_typeを
/// 覚えておき、3秒ごとのポーリングで同じCOMPLETEDタスクを何度も見ても
/// 再Pullしない。
void usePipelineRevealSync({
  required WidgetRef ref,
  required String lectureId,
  required List<ProcessingTask> tasks,
}) {
  // lectureIdが変わったら(=別の講義ページになったら)まっさらに戻す。
  final syncedTypes = useMemoized(() => <String>{}, [lectureId]);

  final completedTypes = tasks.where((t) => t.isCompleted).map((t) => t.taskType).toSet();
  // Setの中身が変わった時だけeffectを再実行させるため、ソート済み文字列に
  // 変換してdepsに渡す(String同士は値で==比較されるため、内容が同じなら
  // 別インスタンスでも再実行されない)。
  final completedKey = (completedTypes.toList()..sort()).join(',');

  useEffect(() {
    final newlyCompleted = completedTypes.difference(syncedTypes);
    if (newlyCompleted.isEmpty) return null;
    syncedTypes.addAll(newlyCompleted);

    final db = ref.read(appDatabaseProvider);
    for (final type in newlyCompleted) {
      for (final pullFn in _pullFnsForTaskType(type, db)) {
        // best-effort: 1テーブルのPullが失敗しても他のPull・画面表示は継続する。
        // 失敗しても次の3秒ポーリングでtask_typeがCOMPLETEDのまま検知され続け、
        // syncedTypesに既に入っているため再試行はされない点に注意 —— ただし
        // これは「タスク自体は成功しているのにPullだけ失敗する」極めて稀な
        // ケース(ネットワーク瞬断等)なので、次回のbootstrapLectures(ホーム
        // 画面表示時など)で最終的に回収される。
        pullFn().catchError((Object e) {
          DevLog.add('⚠️ [PipelineRevealSync] Pull failed for $type: $e');
        });
      }
    }
    return null;
  }, [completedKey]);
}
