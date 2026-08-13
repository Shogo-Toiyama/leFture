// lib/application/lecture/lecture_controller.dart

import 'dart:io';

import 'package:lefture/application/lecture/lecture_list_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:lefture/infrastructure/local_db/repositories/recording_repository_drift.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:lefture/application/sync/lecture_sync_service.dart';
import 'package:lefture/application/sync/fun_fact_sync_service.dart';
import 'package:lefture/application/sync/announcement_sync_service.dart';
import 'package:lefture/application/sync/keyword_sync_service.dart';
import 'package:lefture/application/sync/lecture_topic_sync_service.dart';
import 'package:lefture/application/sync/review_card_sync_service.dart';
import 'package:lefture/application/sync/deep_note_sync_service.dart';
import 'package:lefture/application/sync/topic_map_sync_service.dart';
import 'package:lefture/application/sync/outbox_sync_service.dart';
import 'package:lefture/application/sync/lecture_outbox_push_handler.dart';
import 'package:lefture/application/sync/lecture_moment_outbox_push_handler.dart';
import 'package:lefture/application/sync/fun_fact_outbox_push_handler.dart';
import 'package:lefture/application/sync/announcement_outbox_push_handler.dart';
import 'package:lefture/application/sync/review_card_outbox_push_handler.dart';
import 'package:lefture/application/sync/deep_note_outbox_push_handler.dart';
import 'package:lefture/application/sync/user_profile_outbox_push_handler.dart';
import 'package:lefture/application/sync/keyword_outbox_push_handler.dart';
import 'package:lefture/application/sync/user_profile_sync_service.dart';
import 'package:lefture/application/maintenance/local_retention_service.dart';
import 'package:lefture/core/utils/connectivity_utils.dart';
import 'package:lefture/application/job/job_providers.dart'; // jobRepository
import 'package:lefture/application/recording/upload_manager.dart';
import 'package:lefture/infrastructure/supabase/repositories/announcement_repository_supabase.dart';
import 'package:lefture/infrastructure/supabase/repositories/review_card_repository_supabase.dart';
import 'package:lefture/infrastructure/supabase/repositories/fun_fact_repository_supabase.dart';
import 'package:lefture/infrastructure/supabase/repositories/lecture_topic_repository_supabase.dart';
import 'package:lefture/infrastructure/supabase/repositories/deep_note_repository_supabase.dart';
import 'package:lefture/infrastructure/supabase/repositories/keyword_repository_supabase.dart';
import 'package:lefture/core/utils/dev_log.dart';

part 'lecture_controller.g.dart';

// keepAlive: true — autoDisposeのままだと、Welcome画面での先読み
// (bootstrapIfNeeded)が終わった直後にWelcomeが破棄されて、このController
// ごと(_lastBootstrapAttemptAtの記憶も)消えてしまう。すると直後のHome表示時に
// もう一度bootstrapIfNeededを呼んだ時、15分スロットルが効かず全データを
// 再度Pullし直してしまっていた。セッション中は保持し続けることでこれを防ぐ。
@Riverpod(keepAlive: true)
class LectureController extends _$LectureController {
  @override
  FutureOr<void> build() {
    return null;
  }

  LectureSyncService _sync() {
    final db = ref.read(appDatabaseProvider);
    return LectureSyncService(db);
  }

  /// entityTypeごとのPushハンドラを登録した汎用Outbox送信サービス。
  /// フェーズ2/3でFunFact/Announcement用のハンドラもここに追加していく。
  OutboxSyncService _outbox() {
    final db = ref.read(appDatabaseProvider);
    return OutboxSyncService(db, {
      'lecture': LectureOutboxPushHandler(),
      'lecture_moment': LectureMomentOutboxPushHandler(),
      'fun_fact': FunFactOutboxPushHandler(),
      'announcement': AnnouncementOutboxPushHandler(),
      'review_card': ReviewCardOutboxPushHandler(),
      'deep_note': DeepNoteOutboxPushHandler(),
      'keyword': KeywordOutboxPushHandler(),
      'user_profile': UserProfileOutboxPushHandler(),
    });
  }

  // --- Sync / Bootstrap Logic ---

  /// UIイベント(Home画面表示・Pull-to-Refreshなど)による連続呼び出しを
  /// 間引くための、プロセス内だけのタイムスタンプ。永続化はしない —
  /// アプリがコールドスタートした直後は常にnullになるため、
  /// 起動ごとに1回は必ずbootstrapが走ることも意図している。
  DateTime? _lastBootstrapAttemptAt;

  /// 進行中のbootstrapLectures()があれば、新規に開始せずその完了を共有して
  /// 待つ。呼び出し元(bootstrapIfNeeded/LectureViewerPageのref.listen等)が
  /// ほぼ同時に何度も呼んでも、実際のPullは1回しか走らない。
  Future<void>? _inFlightBootstrap;

  Future<void> bootstrapLectures({bool forceFullPull = false, String reason = 'unspecified'}) async {
    // 診断用: どの呼び出し元が何回bootstrapLecturesを起動しているか追跡する
    // (LectureViewerPageで無限にPullし続けるバグの調査用に追加)。
    DevLog.add('🔁 [LectureController] bootstrapLectures() called: reason=$reason forceFullPull=$forceFullPull');

    final inFlight = _inFlightBootstrap;
    if (inFlight != null) {
      DevLog.add('⏳ [LectureController] bootstrapLectures() already in-flight (reason=$reason) — awaiting existing call');
      await inFlight;
      return;
    }

    final future = _runBootstrapLectures(forceFullPull: forceFullPull);
    _inFlightBootstrap = future;
    try {
      await future;
    } finally {
      _inFlightBootstrap = null;
    }
  }

  Future<void> _runBootstrapLectures({bool forceFullPull = false}) async {
    // このメソッドはHome画面のuseEffect・バックグラウンド復帰・オンライン復帰など、
    // 誰も画面を見ていない/watchしていないタイミングでも呼ばれる。LectureControllerは
    // autoDisposeなので、keepAliveしないと非同期処理の途中でProviderが破棄され、
    // 以降のref.read(...)が「Cannot use the Ref...after it has been disposed」で
    // 失敗する(実際に発生していたバグ)。
    final link = ref.keepAlive();
    try {
      _lastBootstrapAttemptAt = DateTime.now().toUtc();
      final db = ref.read(appDatabaseProvider);

      // オフライン時はネットワーク処理を試みない。ここでチェックせずに
      // 各Push/Pullをawaitすると、タイムアウトが発火するまで
      // Pull-to-Refresh等の呼び出し元が長時間(プラットフォーム依存で
      // 数十秒〜数分)ブロックされてしまう不具合が実際に起きていた。
      if (await isDeviceOnline()) {
        try {
          await _outbox().pushAll();
        } catch (e, st) {
          DevLog.add('⚠️ [LectureController] Outbox push skipped: $e\n$st');
        }

        // Pull対象のエンティティ一覧。1つの失敗が他を止めないよう、
        // それぞれ独立してtry/catchする。
        final pulls = <String, Future<void> Function()>{
          'lecture': () => _sync().pull(forceFullPull: forceFullPull),
          'fun_fact': () => FunFactSyncService(db).pull(forceFullPull: forceFullPull),
          'announcement': () => AnnouncementSyncService(db).pull(forceFullPull: forceFullPull),
          'keyword': () => KeywordSyncService(db).pull(forceFullPull: forceFullPull),
          'lecture_topic': () => LectureTopicSyncService(db).pull(forceFullPull: forceFullPull),
          'review_card': () => ReviewCardSyncService(db).pull(forceFullPull: forceFullPull),
          'deep_note': () => DeepNoteSyncService(db).pull(forceFullPull: forceFullPull),
          'topic_map': () => TopicMapSyncService(db).pull(forceFullPull: forceFullPull),
          'user_profile': () => UserProfileSyncService(db).pull(),
        };

        for (final entry in pulls.entries) {
          try {
            await entry.value();
          } catch (e, st) {
            DevLog.add('⚠️ [LectureController] ${entry.key} pull skipped: $e\n$st');
          }
        }
      } else {
        DevLog.add('📴 [LectureController] Offline — skipping outbox push/pull.');
      }

      // ローカル保守処理(30日超の論理削除の物理削除・キャッシュ容量のLRU剥がし)。
      // Push/Pullとは独立した処理なので、失敗してもSync自体は成功として扱う。
      try {
        final uid = supabase.auth.currentUser?.id;
        if (uid != null) {
          final db = ref.read(appDatabaseProvider);
          await LocalRetentionService(db).runMaintenance(uid);
        }
      } catch (e, st) {
        DevLog.add('⚠️ [LectureController] Local retention maintenance skipped: $e\n$st');
      }
    } finally {
      link.close();
    }
  }

  /// 講義を明示的ダウンロード対象としてPin/Unpinする。Pin中はキャッシュ容量の
  /// LRU剥がし対象から除外される(将来の「ダウンロード」UIから呼ぶ想定)。
  Future<void> setLecturePinned(String lectureId, bool pinned) async {
    final db = ref.read(appDatabaseProvider);
    await db.setLecturePinned(lectureId, pinned);
  }

  void resetThrottle() {
    _lastBootstrapAttemptAt = null;
  }

  Future<void> bootstrapIfNeeded({Duration interval = const Duration(minutes: 15)}) async {
    if (supabase.auth.currentUser == null) return;

    // 進行中のbootstrapLectures()があれば、新規に開始せずその完了を共有して
    // 待つ(bootstrapLectures()自身がdedupeするので、ここでは素通しでよい)。
    // これが無いと、Welcome/Home/AppLifecycleSyncWatcherがほぼ同時に
    // bootstrapIfNeeded()を呼んだ場合、後発の呼び出しが「スロットルされたので
    // 即return」してしまい、実際のPullがまだSyncCursorを書き込む前に
    // hasEverSyncedLectures()を問い合わせて誤判定するレースが起き得る。
    if (_inFlightBootstrap != null) {
      await bootstrapLectures(reason: 'bootstrapIfNeeded/join-in-flight');
      return;
    }

    final last = _lastBootstrapAttemptAt;
    final now = DateTime.now().toUtc();

    final should = (last == null) || now.difference(last) >= interval;
    if (!should) return;

    await bootstrapLectures(reason: 'bootstrapIfNeeded/interval-elapsed');
  }

  /// このユーザーについて、'lecture'エンティティの全件Pullが過去に一度でも
  /// 成功しているかどうかを返す。falseの場合、ローカルDBの「レクチャー0件」は
  /// 「本当に0件」なのか「一度もPullできていないだけ」なのか区別できない
  /// ため、HomePage側はこれをもってEmptyHomeContentとInitialSyncErrorContent
  /// を出し分ける。LocalSyncCursors.lastFullPulledAtはpull()が実際に
  /// ネットワーク呼び出しを完了した時にのみ非nullになる
  /// (lecture_sync_service.dart)ので、新しい永続フラグを追加する必要はない。
  Future<bool> hasEverSyncedLectures() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return false;
    final db = ref.read(appDatabaseProvider);
    final cursor = await db.getSyncCursor(uid, 'lecture');
    return cursor?.lastFullPulledAt != null;
  }

  // --- Lecture Actions (Moved from ViewerController) ---

  /// 分析を開始する。[force]はStart Overなど明示的な再実行時のみtrueにする。
  Future<void> startAnalysis(String lectureId, {bool force = false}) async {
    final link = ref.keepAlive();

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      // expected_chunksは「録音時に実際に切り出したチャンク数」をローカルDBから
      // 渡す。アップロード済み件数から逆算させると、電波が弱くて一部しか届いて
      // いない状態で起動されたときに「これで全部」と誤認され、講義の前半だけで
      // 分析が完了してしまう(エラーにならず静かに欠落する)。
      // ローカル行が無い場合(別端末で録音した講義など)はnullを渡し、
      // JobRepository側のフォールバックに委ねる。
      final local =
          await ref.read(recordingRepositoryDriftProvider).getLecture(lectureId);
      final expectedChunks = local == null
          ? null
          : (local.isRealtime == true ? (local.expectedChunks ?? 0) : 0);

      await ref.read(jobRepositoryProvider).startAnalysis(
            lectureId: lectureId,
            force: force,
            expectedChunks: expectedChunks,
          );
    });

    link.close();
  }

  /// 音声アップロードを止める。deleteLectureとは違い、ファイル本体・アセット行
  /// には一切触れない ―― [resumeUpload]でいつでも再開できるようにするため。
  ///
  /// キャンセルを押した瞬間にちょうどアップロードが完了しかけていた場合、その
  /// 送信自体は止められない(既に投げたHTTPリクエストは取り消せない)ので
  /// そのまま完走させる。その代わり2つの安全策で「アップロードは残るが解析は
  /// 始まらない」を保証する:
  /// 1. ローカル: cancelPendingUploadsForLectureが行を'cancelled'にした後は、
  ///    UploadManagerの自動発火ガードがこの講義への新規start_analysis発火を
  ///    スキップする。
  /// 2. サーバー: 万一(ボタンを押す前に)既に解析が始まってしまっていた場合に
  ///    備え、cancelJobsForLectureをbest-effortで必ず呼んでおく。ジョブが
  ///    存在しなくても無害なので、状態を厳密に判定せず常に呼んで良い。
  Future<void> cancelUpload(String lectureId) async {
    DevLog.add('🛑 [LectureController] cancelUpload called: $lectureId');
    final link = ref.keepAlive();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(recordingRepositoryDriftProvider).cancelPendingUploadsForLecture(lectureId);
      try {
        await ref.read(jobRepositoryProvider).cancelJobsForLecture(lectureId: lectureId);
        DevLog.add('🛑 [LectureController] Server-side cancel-jobs call succeeded (upload stop): $lectureId');
      } catch (e) {
        DevLog.add('⚠️ [LectureController] Server-side job cancel (upload stop) failed (best-effort): $e');
      }
    });
    link.close();
  }

  /// [cancelUpload]で止めたアップロードを再開する。ファイルはcancelUpload側で
  /// 一度も触られていないため、ジョブをqueuedへ戻すだけで通常のリトライ経路に
  /// 自然に乗る。UploadManagerのDB監視は通常ここで自動的に反応するはずだが、
  /// 念のため即座にtryProcessQueue()で後押しする。
  Future<void> resumeUpload(String lectureId) async {
    DevLog.add('▶️ [LectureController] resumeUpload called: $lectureId');
    final link = ref.keepAlive();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(recordingRepositoryDriftProvider).resumePendingUploadsForLecture(lectureId);
      ref.read(uploadManagerProvider).tryProcessQueue();
    });
    link.close();
  }

  /// この講義に紐づく保留中のアップロードジョブ／アセットをローカルDBから消し、
  /// 実体の一時ファイルも掃除する。削除(ゴミ箱行き)の直前に呼ぶ。
  ///
  /// アセット行を消す前にlocalPathを回収しておくこと — 行を消してからでは
  /// パスを辿れず、圧縮済みM4Aが端末に残り続ける。
  Future<void> _cancelPendingUploads(String lectureId) async {
    final repo = ref.read(recordingRepositoryDriftProvider);
    try {
      final localPaths = await repo.getLectureAssetLocalPaths(lectureId);
      await repo.deleteLectureJobsAndAssets(lectureId);
      DevLog.add('🛑 [LectureController] Local upload jobs cancelled: $lectureId');

      for (final path in localPaths) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          DevLog.add('⚠️ [LectureController] Local audio cleanup failed ($path): $e');
        }
      }
    } catch (e, st) {
      // ここで失敗しても削除自体は続行する。ジョブが残ってしまっても、
      // UploadManager側がジョブ実行前にlecture.deletedAtを見て畳むので、
      // 削除済み講義へのアップロード・分析発火は二重に防がれている。
      DevLog.add('⚠️ [LectureController] Failed to cancel local upload jobs: $e\n$st');
    }
  }

  /// 授業を削除する。関連データ（Announcement/ReviewCard/FunFact/
  /// LectureTopic/DeepNote/Keyword）もまとめて論理削除する。
  /// 所属Courseがあった場合、そのTopic Mapのstale化(この講義のノード除去待ち)は
  /// [LectureOutboxPushHandler]がOutbox経由で送る(softDeleteLectureが積んだ
  /// 'lecture' Outbox行のpush時に、courseId/deletedAtから自動判定される)。
  /// これによりオフライン中の削除でも、Lecture本体の同期と同じリトライ保証で
  /// 確実にis_staleが立つ。実際のグラフ修復は行わない — ユーザーの
  /// 「Recreate Topic Map」操作か、Patrolのアイドルタイムアウトが後でまとめて行う
  /// (see topic_map_repository_supabase.dart / task_runners.py の設計議論)。
  Future<void> deleteLecture(String lectureId, {String? courseId}) async {
    DevLog.add('🗑️ [LectureController] deleteLecture called: $lectureId');

    // チュートリアル講義は削除UI側で選択肢自体を出さないが、万一この関数が
    // 別経路から直接呼ばれても、ここで最終的にブロックする。
    final currentLecture =
        await ref.read(lectureRepositoryProvider).watchLectureById(lectureId).first;
    if (currentLecture?.metadata?['is_tutorial'] == true) {
      DevLog.add('🚫 [LectureController] Refused to delete tutorial lecture: $lectureId');
      return;
    }

    final link = ref.keepAlive();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      // 0. まずローカルのアップロードキューを止める。
      // ★ 論理削除より先に行うこと。UploadManagerは_performUpload内で
      // upsertLectureを呼ぶため、削除済み講義のジョブが残っていると、リトライの
      // たびにSupabaseのlectures行が書き戻され、さらに完了時にstart_analysisまで
      // 発火して「削除したはずの講義で分析が始まる」状態になる。
      // 加えて、同じ音声ファイルを選び直して再アップロードした場合、古いジョブが
      // 先に走ってローカルの実体ファイルを消してしまい(アップロード成功後に
      // 削除する仕様)、新しい方が'Local file not found'で永久に失敗していた。
      await _cancelPendingUploads(lectureId);

      // 1. Repository経由で論理削除 + Outbox登録
      // ※ lectureRepositoryProvider は lecture_list_provider.dart で定義されているはずです
      await ref.read(lectureRepositoryProvider).softDeleteLecture(lectureId: lectureId);
      DevLog.add('🗑️ [LectureController] Local soft-delete + outbox enqueue done: $lectureId');

      // 1.5 サーバー側で進行中のパイプラインを止める(best-effort)。
      // これが無いと、削除後もタスクが走り続け、下のカスケード論理削除
      // (削除時点で存在したコンテンツだけが対象)をすり抜けたReview Card /
      // Fun Fact等がdeleted_at=nullの新規行として生成され、削除済み講義に
      // ぶら下がってしまう。クレジットも無駄に消費される。
      // オフライン中は失敗するが、その場合サーバー側のジョブはそもそも
      // 動いていないか、次にオンラインになった時点でユーザーがゴミ箱から
      // 完全削除(hard-delete)すれば回収される。
      try {
        await ref.read(jobRepositoryProvider).cancelJobsForLecture(lectureId: lectureId);
        DevLog.add('🛑 [LectureController] Server-side jobs cancelled: $lectureId');
      } catch (e) {
        DevLog.add('⚠️ [LectureController] Server-side job cancel failed (best-effort): $e');
      }

      // 2. 関連データをカスケードで論理削除する（都度Supabaseへ直接、best-effort）
      // ※ deleteCourse と同様、現時点ではオフラインファースト化していないため、
      //   オフライン中はここが失敗する可能性がある(Lecture自体の削除はOutbox経由で
      //   後から同期されるので問題ないが、関連データの掃除は取りこぼれる)。
      try {
        await Future.wait([
          ref.read(announcementRepositoryProvider).softDeleteForLecture(lectureId),
          ref.read(reviewCardRepositoryProvider).softDeleteForLecture(lectureId),
          ref.read(funFactRepositoryProvider).softDeleteForLecture(lectureId),
          ref.read(lectureTopicRepositoryProvider).softDeleteForLecture(lectureId),
          ref.read(deepNoteRepositoryProvider).softDeleteForLecture(lectureId),
          ref.read(keywordRepositoryProvider).softDeleteForLecture(lectureId),
        ]);
      } catch (e, st) {
        DevLog.add('⚠️ [LectureController] Cascade soft-delete of related data failed: $e\n$st');
      }

      // 3. 即座に同期を試みる (失敗してもOutboxにあるのでOK)
      try {
        await _outbox().pushAll();
        DevLog.add('🗑️ [LectureController] Outbox push after delete completed: $lectureId');
      } catch (e) {
        DevLog.add('⚠️ [LectureController] Background push failed (queued in outbox): $e');
      }
    });
    link.close();
  }

  /// 授業のタイトルと所属コースを更新する。[previousCourseId]と[courseId]が
  /// 異なる場合（＝Course間の移動）、旧Courseのマップからはこの講義のノードを
  /// 除去待ちに、新Courseのマップにはこの講義のトピックを追加待ちにマークする。
  /// この送信は[LectureOutboxPushHandler]がOutbox経由(バックオフ・自動リトライ付き)
  /// で行う — repository層が移動元courseIdを`pendingTopicMapStaleCourseId`に
  /// 退避しているので、オフライン中の移動でも取りこぼれない。
  Future<void> updateLecture({
    required String lectureId,
    required String? title,
    required String? courseId,
    String? previousCourseId,
    DateTime? lectureDatetime,
  }) async {
    final link = ref.keepAlive();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(lectureRepositoryProvider).updateLectureTitleAndCourse(
            lectureId: lectureId,
            title: title,
            courseId: courseId,
            previousCourseId: previousCourseId,
            lectureDatetime: lectureDatetime,
          );

      try {
        await _outbox().pushAll();
      } catch (e) {
        DevLog.add('⚠️ [LectureController] Background push failed (queued in outbox): $e');
      }
    });
    link.close();
  }

  /// ローカル書き込み直後にOutboxを即座に送信したい場合に呼ぶ(例: Review Card/
  /// Deep NoteのLike・Dislike・Saveタップ)。失敗してもOutboxに残っているので、
  /// 次回のbootstrap時に自動でリトライされる。
  Future<void> pushOutboxNow() async {
    final link = ref.keepAlive();
    try {
      await _outbox().pushAll();
    } catch (e) {
      DevLog.add('⚠️ [LectureController] Background push failed (queued in outbox): $e');
    } finally {
      link.close();
    }
  }
}