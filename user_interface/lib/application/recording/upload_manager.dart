import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:background_downloader/background_downloader.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:lefture/core/services/background_task.dart';
import 'package:lefture/core/utils/connectivity_utils.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/core/utils/network_constants.dart';
import 'package:lefture/domain/exceptions/insufficient_credits_exception.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show StreamProvider;
import 'package:http/http.dart' as http;

import '../../infrastructure/supabase/services/lecture_write_service.dart';
import '../../infrastructure/local_db/repositories/recording_repository_drift.dart';
import '../../infrastructure/local_db/app_database.dart';

part 'upload_manager.g.dart';

/// マスター音声のPUTをOSネイティブのバックグラウンド転送(iOS: URLSession,
/// Android: WorkManager)へ引き渡す際に使うタスクグループ名。このグループに
/// 登録したコールバックだけがこれらのタスクの更新を受け取る(他のグループ/
/// updatesストリームには流れない)。
const _masterAudioUploadGroup = 'lefture_master_audio_upload';

/// [UploadManager._performUpload]の戻り値。マスター音声のPUTはOSの
/// バックグラウンド転送に引き渡した時点で「一旦ここでの仕事は終わり」だが、
/// 通常の同期的な完了(チャンク送信・start_analysis呼び出し等)と違い、
/// 成功時の後始末(ジョブをdoneにする・analysis自動発火判定)はまだ行って
/// いない — それは後で[UploadManager._handleMasterAudioTaskUpdate]が
/// 転送の完了を検知してから行う。呼び出し元(_processQueue)はこの違いを
/// 見て、後始末を今すぐ行うか(completed)後回しにするか(handedOffToBackground)
/// を判断する。
enum _UploadOutcome { completed, handedOffToBackground }

@Riverpod(keepAlive: true)
UploadManager uploadManager(Ref ref) {
  final mgr = UploadManager(
    repo: ref.read(recordingRepositoryDriftProvider),
    lectureWriter: ref.read(lectureWriteServiceProvider),
  );
  
  // アプリ起動中ずっと監視させる
  mgr.initialize();
  
  ref.onDispose(mgr.dispose);
  return mgr;
}

/// UIが「自動分析開始の呼び出しが失敗してリトライ待ちになっている」ことを
/// 表示するためのwatch。lastErrorが入っていれば、少なくとも1回は失敗している。
final startAnalysisJobsProvider =
    StreamProvider.family<List<LocalUploadJob>, String>((ref, lectureId) {
  return ref.watch(recordingRepositoryDriftProvider).watchStartAnalysisJobsForLecture(lectureId);
});

/// UIが「分析開始の号砲は既に鳴らしてある」ことを表示するためのwatch。
/// 上のstartAnalysisJobsProviderと違い'done'も含む — 詳細は
/// RecordingRepositoryDrift.watchStartAnalysisJobsIncludingDoneForLectureの
/// コメントを参照(アップロード完了直後、サーバーのjob作成をポーリングで
/// 検知するまでの数秒間だけStart Analysisボタンが再表示される「ちらつき」
/// を埋めるためのもの)。
final startAnalysisJobsIncludingDoneProvider =
    StreamProvider.family<List<LocalUploadJob>, String>((ref, lectureId) {
  return ref
      .watch(recordingRepositoryDriftProvider)
      .watchStartAnalysisJobsIncludingDoneForLecture(lectureId);
});

/// この講義の音声アップロード(チャンク/マスター)がまだ残っているかのwatch。
/// 空でない間は音声がクラウドに揃っていないため、UIはStart Analysisを
/// 押させてはいけない(押せてしまうと、audio_path未設定のまま
/// TRANSCRIBE_MASTERが走って「音声ファイルがありません」で失敗する)。
final pendingAudioUploadJobsProvider =
    StreamProvider.family<List<LocalUploadJob>, String>((ref, lectureId) {
  return ref
      .watch(recordingRepositoryDriftProvider)
      .watchPendingAudioUploadJobsForLecture(lectureId);
});

/// UIの音声プレビュー(NotStartedView)用watch。マスター音声アセット行
/// (ローカルDB、pull同期を待たない即時反映)を直接見る。
final masterAudioAssetProvider =
    StreamProvider.family<LocalLectureAsset?, String>((ref, lectureId) {
  return ref
      .watch(recordingRepositoryDriftProvider)
      .watchMasterAudioAsset(lectureId);
});

/// UIが「アップロードをユーザーが自分で止めた」ことを表示するためのwatch。
final cancelledAudioUploadJobsProvider =
    StreamProvider.family<List<LocalUploadJob>, String>((ref, lectureId) {
  return ref
      .watch(recordingRepositoryDriftProvider)
      .watchCancelledAudioUploadJobsForLecture(lectureId);
});

class UploadManager {
  UploadManager({
    required RecordingRepositoryDrift repo,
    required LectureWriteService lectureWriter,
  })  : _repo = repo,
        _lectureWriter = lectureWriter;

  final RecordingRepositoryDrift _repo;
  final LectureWriteService _lectureWriter;

  StreamSubscription? _jobSubscription;
  StreamSubscription? _connectivitySubscription;
  Timer? _periodicRetryTimer;
  bool _isProcessing = false;

  void initialize() {
    // 診断用: initialize()自体が本当に呼ばれているかを切り分けるためのログ。
    // ここが1行も出ない場合、uploadManagerProviderがまだどこからもwatch/read
    // されていない(Providerが生成されていない)ことを意味する。
    DevLog.add('🚀 [UploadManager] initialize() called');

    // 0. マスター音声PUT用のバックグラウンド転送(background_downloader)の
    // コールバックを登録する。ドキュメント通り、必ずstart()より前に登録する
    // (でないとアプリがサスペンド中に完了/失敗していたタスクの更新を
    // start()がflushする際に取りこぼす)。
    FileDownloader().registerCallbacks(
      group: _masterAudioUploadGroup,
      taskStatusCallback: _handleMasterAudioTaskUpdate,
    );
    // start()はDB追跡(trackTasks)・サスペンド中に処理された更新の取り込み
    // (resumeFromBackground)・OSに存在を忘れられたタスクの再エンキュー
    // (rescheduleKilledTasks、5秒後)をまとめて行う。initialize()自体は
    // 同期メソッドなので、ここではawaitせずfire-and-forgetする。
    unawaited(FileDownloader().start(autoCleanDatabase: true));

    // 1. ネットワーク復帰監視
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((event) {
      DevLog.add('📶 [UploadManager] Connectivity changed: $event');
      if (!isConnectivityOffline(event)) {
        _processQueue(); // ネットが戻ったら処理開始
      }
    });

    // 1.5 定期的な再チェック(接続変化・新規ジョブ追加のどちらも起きない間、
    // retry_wait中のジョブを永久に起こす手段が無かった)。
    // ★ 実際に発生したバグ: あるジョブが失敗してnextRetryAtを未来に設定した後、
    // その時刻を過ぎても「起こしてくれる外部イベント」(接続変化 or 新規ジョブ)が
    // 一切来なければ、_processQueue()は二度と呼ばれず、そのジョブは無期限に
    // retry_wait状態のまま放置されていた。バックオフの最短間隔(30秒)より
    // 極端に粗くならない程度の間隔でポーリングする。
    _periodicRetryTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!_isProcessing) {
        _processQueue();
      }
    });

    // 2. DB監視 (Jobが追加されたり、リトライ待ちが解けたりしたら反応)
    _jobSubscription = _repo.watchPendingJobs().listen((jobs) {
      // 診断用: DB監視ストリーム自体が発火しているか、その時点で何件
      // 保留ジョブがあるかを確認する(initialize()直後に1回、購読開始時点の
      // スナップショットが必ず流れてくるはず)。
      DevLog.add('👀 [UploadManager] watchPendingJobs emitted ${jobs.length} job(s)');
      // 未処理のジョブがあり、かつ今処理中でなければ開始
      if (jobs.isNotEmpty && !_isProcessing) {
        _processQueue();
      }
    });
  }

  void dispose() {
    _jobSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _periodicRetryTimer?.cancel();
  }

  /// 外部から手動で呼び出す用（Refreshボタンなど）
  void tryProcessQueue() => _processQueue();

  Future<void> _processQueue() async {
    // 二重実行防止
    // ★ ここで無言でreturnしていると、万一どこかのawaitが詰まって
    // _isProcessingがtrueのまま戻らなくなった場合、以降のトリガー
    // (接続復帰・DB変化)が全部無反応になってもDevLogに何の手がかりも
    // 残らない。診断のため一度だけ経緯をログする。
    if (_isProcessing) {
      DevLog.add('⏭️ [UploadManager] _processQueue already running, skip.');
      return;
    }
    _isProcessing = true;

    try {
      // オフラインなら何もしない
      // ★ この判定をtry内に置くのが重要: tryの外でreturnすると、finallyで
      // _isProcessingをfalseに戻す処理を素通りしてしまい、一度オフライン判定
      // (誤検知含む)が起きただけでアップロードが永久に止まってしまうバグになる。
      final connectivity = await Connectivity().checkConnectivity();
      if (isConnectivityOffline(connectivity)) {
        DevLog.add('📡 [UploadManager] Offline detected (raw: $connectivity), skipping this round.');
        return;
      }

      while (true) {
        // オフラインになったら中断
        final currentConn = await Connectivity().checkConnectivity();
        if (isConnectivityOffline(currentConn)) break;

        // 1. 次にやるべきジョブをDBから取得
        // (watchではなくgetで最新を取るのが安全)
        final allJobs = await _repo.getPendingJobs();
        
        // リトライ待ち時間(nextRetryAt)を過ぎているものだけフィルタ
        final now = DateTime.now().toUtc();
        final readyJobs = allJobs.where((j) {
          if (j.status == 'done') return false;
          if (j.nextRetryAt == null) return true;
          return j.nextRetryAt!.isBefore(now);
        }).toList();

        if (readyJobs.isEmpty) {
          // やることなし。allJobsに何か残っているのに全部readyでない場合は、
          // nextRetryAtがまだ先(バックオフ待ち)ということなので、それも
          // 診断のためログに残す(「何も起きていないように見える」原因が
          // 「本当に何もしていない」のか「待たされているだけ」なのか区別するため)。
          if (allJobs.isNotEmpty) {
            final waiting = allJobs
                .map((j) => '${j.kind}#${j.id.substring(0, 8)}(next=${j.nextRetryAt?.toLocal()}, attempt=${j.attemptCount})')
                .join(', ');
            DevLog.add('⏳ [UploadManager] ${allJobs.length} job(s) queued but none ready yet: $waiting');
          }
          break;
        }

        // 先頭の1件を取り出す
        final job = readyJobs.first;
        DevLog.add('🔄 [UploadManager] Attempting ${job.kind}#${job.id.substring(0, 8)} (lecture ${job.lectureId}, attempt ${job.attemptCount + 1})');

        try {
          // ステータスを「処理中」に変えてもいいが、
          // シンプルにするため「失敗したらリトライ時刻更新」「成功したら削除orDone」の2択で進める

          final outcome = await _performUpload(job);

          if (outcome == _UploadOutcome.handedOffToBackground) {
            // マスター音声のPUTはOSのバックグラウンド転送(background_downloader)
            // へ引き渡し済み。成功/失敗の後始末(ジョブをdoneにする・analysis
            // 自動発火判定)は_handleMasterAudioTaskUpdateが転送の完了を検知して
            // から行うので、ここではまだ行わない。次のジョブへ進む。
            DevLog.add('📤 [UploadManager] ${job.kind}#${job.id.substring(0, 8)} handed off to background transfer.');
            continue;
          }

          await _onJobSucceeded(job);
        } catch (e) {
          final nextAttempt = job.attemptCount + 1;

          if (e is InsufficientCreditsException) {
            // クレジット不足は「待てば直る」類の失敗ではないため、指数バックオフで
            // 延々とリトライしても無意味(かつCloud Runへの無駄なリクエストが
            // 積み重なる)。nextRetryAtを事実上「無期限」に設定して自動リトライを
            // 止める一方、statusは'retry_wait'のまま・lastErrorも残すことで、
            // startAnalysisJobsProvider(NotStartedViewが監視)には引き続き見える
            // ようにする——UI側はこのlastErrorを見てクレジット不足ダイアログを出す。
            // ユーザーがクレジットを追加した後は、手動の「Start Analysis」ボタン
            // (別経路のJobRepository.startAnalysis)で再開できる。
            DevLog.add('💳 [UploadManager] ${job.kind}#${job.id.substring(0, 8)} failed: insufficient credits, will not auto-retry: $e');
            await _repo.updateJobStatus(
              jobId: job.id,
              status: 'retry_wait',
              lastError: e.toString(),
              nextRetryAt: DateTime.now().toUtc().add(const Duration(days: 3650)),
              attemptCount: nextAttempt,
            );
            continue;
          }

          // リトライ回数を増やし、次のリトライ時刻を設定
          // ★ attemptCountを実際にDBへ書き戻す（以前はここが抜けていて常に0のまま
          // だったため、指数バックオフのつもりが実質「常に30秒固定」になっていた）
          final delaySeconds = _backoffSeconds(nextAttempt);
          final nextRetry = DateTime.now().toUtc().add(Duration(seconds: delaySeconds));

          // ★ _performUpload内の個別catchブロックに頼らず、ここで必ず1回
          // ログを出す。以前は_performUploadの入り口付近(Lecture not found/
          // Asset not found/Local file not found)にログの無いthrowがあり、
          // それらの失敗が完全に無音でDBのlastErrorにだけ記録されていた
          // (=DevLogからは「何も起きていない」ように見える不具合の原因)。
          // ここに集約しておけば、今後どこで例外が投げられても必ず可視化される。
          DevLog.add('❌ [UploadManager] ${job.kind}#${job.id.substring(0, 8)} failed (attempt $nextAttempt, next retry in ${delaySeconds}s): $e');

          await _repo.updateJobStatus(
            jobId: job.id,
            status: 'retry_wait',
            lastError: e.toString(),
            nextRetryAt: nextRetry,
            attemptCount: nextAttempt,
          );

          // エラーが出たので、一旦ループを抜けるか、次のジョブへ行くか。
          // ここでは「次のジョブ」へ行くために continue する（並列処理っぽく見える）
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// ジョブが成功した後の後始末。通常の同期経路(_processQueue、[job]がこの
  /// 呼び出し時点で成功済み)と、マスター音声のバックグラウンド転送の完了を
  /// 検知した経路([_handleMasterAudioTaskUpdate])の両方から呼ばれる共有ロジック
  /// (元は_processQueueの中にベタ書きされていたものを抽出した)。
  Future<void> _onJobSucceeded(LocalUploadJob job) async {
    // 成功！ -> Jobを完了にする
    await _repo.updateJobStatus(
      jobId: job.id,
      status: 'done',
      lastError: null,
    );

    // チャンク音声はアップロード完了後、ローカルの一時ファイルはもう不要。
    // マスター音声側は別経路(_performUpload/_handleMasterAudioTaskUpdate)で
    // 既に削除しているため、ここではチャンクのみを対象にする。
    if (job.kind == 'audio_upload') {
      final asset = await _repo.getAsset(job.assetId);
      final localPath = asset?.localPath;
      if (localPath != null) {
        try {
          final file = File(localPath);
          if (await file.exists()) {
            await file.delete();
            DevLog.add('🧹 [UploadManager] Chunk audio local file deleted.');
          }
        } catch (cleanupError) {
          DevLog.add('⚠️ [UploadManager] Chunk audio cleanup failed: $cleanupError');
        }
      }
    }

    // Assetの状態も「アップロード済み」に更新する。
    // ★ 以前はJobのstatusしか更新しておらず、Asset.uploadStatusが永久に
    // 'queued'のままだった。これによりサインアウト時の「未アップロードの
    // 録音」判定(local_data_wipe_service.dart)が常にtrueになり、実際は
    // 同期済みでもサインアウトがブロックされ続けるバグになっていた。
    if (job.kind == 'audio_upload' || job.kind == 'master_audio_upload') {
      final uploadedAsset = await _repo.getAsset(job.assetId);
      if (uploadedAsset != null) {
        await _repo.updateAssetUploaded(
          assetId: job.assetId,
          remotePath: uploadedAsset.storagePath ?? '',
        );
      }
    }

    // Q1. この授業の未送信「チャンク」ジョブはまだ残っているか？
    // ★ マスター音声(kind: master_audio_upload)は分析の入力ではなく再生用途
    // でしかないため、ここでは意図的に見ない。マスター音声の失敗・保留が
    // 分析開始を永久にブロックしてしまう問題を避けるため。
    final remainingJobs = await _repo.getPendingChunkJobsForLecture(job.lectureId);

    // Q2. この授業はすでに録音終了（Done）しているか？
    final lecture = await _repo.getLecture(job.lectureId);
    if (lecture == null) {
      DevLog.add('Lecture not found (maybe discarded?)');
      return;
    }
    // 削除済み講義では分析を発火させない。削除処理(LectureController.
    // deleteLecture)はこの講義のジョブを消してから論理削除するが、
    // ちょうどこのジョブが実行中だった場合だけはすり抜けるため、
    // 発火の直前でもう一度確認する。
    if (lecture.deletedAt != null) {
      DevLog.add('🗑️ [UploadManager] Lecture is deleted, skipping start-analysis trigger.');
      return;
    }
    final expectedChunks = lecture.expectedChunks;

    // ★ ユーザーが「アップロードを止める」を押した講義では、たとえ
    // (ボタンを押した瞬間に送信中だった)このジョブが今まさに成功しても
    // 自動発火してはいけない。cancelPendingUploadsForLectureは対象ジョブを
    // 'cancelled'にするだけでファイルは消さないため、この講義に他の
    // 'cancelled'な音声ジョブが残っているかどうかで「止めた意思表示が
    // あったか」を判定できる(再開すればqueuedに戻るので自然に消える)。
    final cancelled = await _repo.hasCancelledUploadJobsForLecture(job.lectureId);
    if (cancelled) {
      DevLog.add('⏸️ [UploadManager] Upload was cancelled for this lecture, skipping auto-start trigger.');
      return;
    }

    // リアルタイム時の自動発火判定
    // ★ job.kindを'audio_upload'に限定する: これが無いと、後段でstart_analysis
    // ジョブ自体が完了した時にもこの条件(remainingJobs.isEmpty等)を満たしてしまい、
    // start_analysisジョブを再エンキュー→それがまた完了→再エンキュー…と
    // 無限ループしてしまう。
    if (job.kind == 'audio_upload' &&
        lecture.isRealtime == true &&
        remainingJobs.isEmpty &&
        expectedChunks != null) {
      if (lecture.autoStartAnalysis == false) {
        DevLog.add('⏸️ 自動分析がOFFのため、自動発火はスキップします（手動でStart Analysisが必要）。');
        return;
      }
      // コースが未選択の場合は自動分析を開始しない
      if (lecture.courseId == null) {
        DevLog.add('⏸️ コース未選択のため、自動分析はスキップします（手動でStart Analysisが必要）。');
        return;
      }

      // 二重発火ガード。保存時(RecordingController._maybeEnqueueStartAnalysis)
      // も号砲を鳴らしうるため、既にジョブがあるなら何もしない。
      if (await _repo.hasStartAnalysisJobForLecture(lecture.id)) {
        DevLog.add('⏭️ [UploadManager] start_analysisジョブが既に存在するため、二重発火を回避します。');
        return;
      }

      DevLog.add('🎉 全てのチャンクの送信完了！分析開始の号砲を鳴らします！');
      await _repo.enqueueStartAnalysis(
        userId: lecture.userId,
        lectureId: lecture.id,
        assetId: job.assetId,
      );
    } else if (job.kind == 'audio_upload' &&
        lecture.isRealtime == true &&
        remainingJobs.isEmpty &&
        expectedChunks == null) {
      // 録音中(まだ保存を押していない)にチャンクを送り終えた場合は
      // 必ずここに来る —— expectedChunksは保存時にしか書かれないため。
      // 異常ではなく、保存時にRecordingController側が号砲を鳴らす。
      DevLog.add(
        'ℹ️ [UploadManager] チャンク送信完了時点ではまだ録音が保存されていません(expectedChunks未確定)。分析開始は保存時に予約されます。',
      );
    }

    // プレレコーデッド時の自動発火判定
    if (lecture.isRealtime == false && job.kind == 'master_audio_upload') {
      if (lecture.autoStartAnalysis == false) {
        DevLog.add('⏸️ 自動分析がOFFのため、自動発火はスキップします（手動でStart Analysisが必要）。');
        return;
      }
      if (lecture.courseId == null) {
        DevLog.add('⏸️ コース未選択のため、自動分析はスキップします（手動でStart Analysisが必要）。');
        return;
      }

      DevLog.add('🎉 マスター音声の送信完了！分析開始の号砲を鳴らします！');
      await _repo.enqueueStartAnalysis(
        userId: lecture.userId,
        lectureId: lecture.id,
        assetId: job.assetId,
      );
    }
  }

  /// 失敗時の指数バックオフ秒数(30秒, 60秒, 120秒 ... 上限5分)。
  /// _processQueueの通常経路と_handleMasterAudioTaskUpdateの両方で使う。
  int _backoffSeconds(int attempt) {
    const maxBackoffSeconds = 5 * 60;
    return min(30 * pow(2, attempt - 1).toInt(), maxBackoffSeconds);
  }

  Future<_UploadOutcome> _performUpload(LocalUploadJob job) async {
    // 1. 必要なデータをローカルDBから集める
    final lecture = await _repo.getLecture(job.lectureId);

    // データがない場合（ユーザーが途中でDiscardして消した等）
    if (lecture == null) {
      throw Exception('Lecture not found (maybe discarded?)');
    }

    // 削除済み(ゴミ箱行き)の講義に対しては、何も送らずジョブを畳む。
    // ★ 例外ではなくreturnで「成功」扱いにするのが重要 —— 投げるとリトライ待ちの
    // ジョブとして残り続け、そのたびにupsertLectureで削除済みlectures行を
    // Supabaseへ書き戻してしまう。
    if (lecture.deletedAt != null) {
      DevLog.add('🗑️ [UploadManager] Lecture is deleted, dropping ${job.kind} job.');
      return _UploadOutcome.completed;
    }

    // start_analysisジョブはファイルを送るわけではなく、Cloud Runの
    // /start-analysisを叩くだけなので、ローカルファイルの存在チェックより前で分岐する
    // (紐づくassetIdは他ジョブ完了時の使い回しで、ローカルファイルは既に削除済みのことがある)。
    if (job.kind == 'start_analysis') {
      await _callStartAnalysis(
        lectureId: lecture.id,
        expectedChunks: (lecture.isRealtime == true) ? (lecture.expectedChunks ?? 0) : 0,
      );
      return _UploadOutcome.completed;
    }

    final asset = await _repo.getAsset(job.assetId);
    if (asset == null) {
      throw Exception('Asset not found (maybe discarded?)');
    }

    final localPath = asset.localPath;
    if (localPath == null || !File(localPath).existsSync()) {
      throw Exception('Local file not found at $localPath');
    }

    // 2. Supabaseへの書き込み (Lecturesテーブル)
    // ★ 以前はここだけtry/catchもDevLogも無く、失敗してもDBのlastErrorに
    // 静かに記録されるだけで誰にも気づかれなかった(マスター音声/チャンク送信の
    // 通信処理には全部❌ログがあるのに、ここだけ抜けていた)。結果、実際には
    // 毎回リトライして毎回失敗しているのに、ユーザーからもDevLogからも
    // 「何も起きていない」ように見えるバグになっていた。
    try {
      await _lectureWriter.upsertLecture(
        lectureId: lecture.id,
        userId: lecture.userId,
        courseId: lecture.courseId,
        title: lecture.title,
        lectureDateTimeUtc: lecture.lectureDatetime ?? lecture.createdAt,
        recordingLanguage: lecture.recordingLanguage,
        displayLanguage: lecture.displayLanguage,
      );
    } catch (e) {
      DevLog.add('❌ [UploadManager] Lecture upsert失敗、後でリトライします: $e');
      rethrow;
    }

    // 3. ジョブの種類に応じてアップロード処理を分岐
    if (job.kind == 'master_audio_upload') {
      try {
        // ①署名付きURLの取得は軽量なJSONリクエストなので今まで通り同期的に行う。
        final uploadUrl = await _requestMasterAudioUploadUrl(lectureId: lecture.id);
        // ②の重いPUTはOSネイティブのバックグラウンド転送(iOS: URLSession,
        // Android: WorkManager)へ引き渡す。ここで完了を待たない — アプリが
        // ロック/バックグラウンドに回っても、OSが裏で転送を完了させる。
        // ③(Cloud Runへの完了通知)と成功時の後始末は、転送の完了を
        // _handleMasterAudioTaskUpdateが検知してから行う。
        await _enqueueMasterAudioBackgroundUpload(
          jobId: job.id,
          localPath: localPath,
          uploadUrl: uploadUrl,
        );
      } catch (e) {
        DevLog.add('❌ [UploadManager] マスターオーディオのバックグラウンド転送開始に失敗、後でリトライします: $e');
        rethrow;
      }
      return _UploadOutcome.handedOffToBackground;
    }

    // 従来のチャンク処理（kind == 'audio_upload' の想定）
    // Realtime Transcribe が Off の講義では個別チャンクを送信しない
    // (CheckAndAssemble が expected_chunks=0 のまま誤発火するのを防ぐ二重の安全策)
    if (lecture.isRealtime == false) {
      DevLog.add('⏭️ [UploadManager] Realtime Transcribe is OFF, discarding stray chunk job: Chunk ${asset.sequenceIndex}');
      return _UploadOutcome.completed;
    }

    final seqStr = asset.sequenceIndex.toString().padLeft(3, '0');
    final fileName = 'chunk_$seqStr.m4a';
    final storagePath = '${lecture.userId}/${lecture.id}/audio_chunks/$fileName';

    // 4. lecture_transcripts テーブルに「PROCESSING」を登録
    try {
      // ★ 他のSupabase呼び出し(lectures upsert)と同じく、これもタイムアウトが
      // 無いと応答が返ってこない限り永久に待ち続け、アップロードキュー全体を
      // 静かにフリーズさせてしまう。
      await supabase
          .from('lecture_transcripts')
          .upsert({
            'lecture_id': lecture.id,
            'chunk_index': asset.sequenceIndex,
            'storage_path': storagePath, // 予測されるパスを先に入れておく
            'status': 'PROCESSING',
            'start_time': asset.startTime,
          }, onConflict: 'lecture_id,chunk_index')
          .timeout(networkTimeout);
      DevLog.add('📝 [UploadManager] 処理開始(PROCESSING)をDBに登録しました: Chunk ${asset.sequenceIndex}');
    } catch (e) {
      DevLog.add('❌ [UploadManager] DBへの受付票登録に失敗: $e');
      rethrow; 
    }

    // 5. Cloud Run に直接 POST して文字起こしを開始（バックエンドが R2 に保存する）
    try {
      await _postToCloudRun(
        localPath: localPath,
        lectureId: lecture.id,
        chunkIndex: asset.sequenceIndex,
        startTime: asset.startTime,
        whisperContext: lecture.whisperContext ?? '',
      );
    } catch (e) {
      DevLog.add('❌ [UploadManager] 通信エラー、後でリトライします: $e');
      rethrow;
    }
    return _UploadOutcome.completed;
  }

  /// Cloud RunのFastAPIへ直接M4A(AAC)ファイルを投げるメソッド
  Future<void> _postToCloudRun({
    required String localPath,
    required String lectureId,
    required int chunkIndex,
    required double startTime,
    String whisperContext = '',
  }) async {
    // Cloud RunのURL
    final uri = Uri.parse('https://lefture-511705914929.us-west1.run.app/worker/transcribe-chunk');

    final request = http.MultipartRequest('POST', uri);

    // Cloud Run側が「どのデータか」分かるようにメタデータを送る
    request.fields['lecture_id'] = lectureId;
    request.fields['chunk_index'] = chunkIndex.toString();
    request.fields['start_time'] = startTime.toString();
    if (whisperContext.isNotEmpty) {
      request.fields['whisper_context'] = whisperContext;
    }
    
    // M4A(AAC)ファイルをバイナリとして添付
    request.files.add(await http.MultipartFile.fromPath('file', localPath));

    // 送信してレスポンスを待つ
    // ★ タイムアウトを必ず設定する: Cloud Run側がハングした場合、これが無いと
    // _processQueue の直列ループが永久に停止し、以降の全チャンクが送信されなくなる。
    final response = await request.send().timeout(
      const Duration(seconds: 90),
      onTimeout: () => throw TimeoutException(
        'Cloud Run timed out while transcribing chunk $chunkIndex',
      ),
    );

    if (response.statusCode != 200) {
      final respStr = await response.stream.bytesToString();
      throw Exception('Cloud Run error (${response.statusCode}): $respStr');
    }

    DevLog.add('🚀 [UploadManager] Cloud RunにChunk $chunkIndex を送信完了！');
  }

  /// マスターオーディオ(M4A)のアップロードは3ステップに分かれる:
  /// ①署名付きURLの発行(Cloud Run、軽量JSON) ②R2への直接PUT(重い・時間が
  /// かかる — Cloud Runには32MBのリクエストボディ上限があり、64kbpsの音声でも
  /// 約70分の録音で超えてしまうため、Cloud Runを経由せずR2へ直接送る)
  /// ③アップロード完了をCloud Runに通知しlectures.audio_pathを更新してもらう。
  ///
  /// ②だけをbackground_downloaderのバックグラウンド転送タスクに引き渡し、
  /// ①と③はDartプロセス内(①は_performUpload、③は転送完了を検知した
  /// _handleMasterAudioTaskUpdate)で行う。

  /// ①署名付きアップロードURLをCloud Runから取得する。
  Future<String> _requestMasterAudioUploadUrl({required String lectureId}) async {
    final requestUrlUri = Uri.parse(
      'https://lefture-511705914929.us-west1.run.app/worker/request-master-audio-upload-url',
    );
    final requestUrlResponse = await http
        .post(
          requestUrlUri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'lecture_id': lectureId}),
        )
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException(
            'Cloud Run timed out while requesting master audio upload URL for lecture $lectureId',
          ),
        );

    if (requestUrlResponse.statusCode != 200) {
      throw Exception(
        'Cloud Run request-upload-url error (${requestUrlResponse.statusCode}): ${requestUrlResponse.body}',
      );
    }

    return jsonDecode(requestUrlResponse.body)['upload_url'] as String;
  }

  /// ②R2への直接PUTを、OSネイティブのバックグラウンド転送タスクとして
  /// enqueueする。ここでは転送の完了を待たない — taskIdをjob.idに揃えて
  /// おくことで、[_handleMasterAudioTaskUpdate]がどのジョブの転送かを
  /// 引き当てられるようにする。
  Future<void> _enqueueMasterAudioBackgroundUpload({
    required String jobId,
    required String localPath,
    required String uploadUrl,
  }) async {
    const contentType = 'audio/x-m4a';
    // 絶対パスのままだとiOS/Androidでアプリ再起動を跨いだ時に無効になりうる
    // ため、baseDirectory/directory/filenameへ分解する(パッケージ推奨パターン)。
    final (baseDir, directory, filename) = await Task.split(filePath: localPath);

    final task = UploadTask(
      taskId: jobId,
      url: uploadUrl,
      filename: filename,
      baseDirectory: baseDir,
      directory: directory,
      httpRequestMethod: 'PUT',
      post: 'binary',
      // ★ binaryアップロードでは、実際に送信されるContent-Typeヘッダーは
      // headers['Content-Type']ではなく、ここのmimeTypeから決まる
      // (プラグインのネイティブ実装が binary upload 時に
      // connection.setRequestProperty("Content-Type", task.mimeType) で
      // 強制的に上書きするため — headers側に書いても無視される)。
      // 未指定だとfilenameの拡張子から自動推測された別の値になり、R2の
      // 署名付きURL(audio/x-m4aで署名済み)と食い違って403 Forbiddenになる
      // (実機で確認済み)。必ずここで明示すること。
      mimeType: contentType,
      headers: const {
        // 未指定だとプラグインが既定でContent-Dispositionヘッダーを
        // 付けてしまう。R2の署名付きURLはContent-Typeしか署名に含めて
        // いないため、余計なヘッダーが付くと署名検証エラー(403)になる
        // おそれがある。空文字を指定して明示的に省略させる。
        'Content-Disposition': '',
      },
      group: _masterAudioUploadGroup,
      updates: Updates.status,
    );

    final enqueued = await FileDownloader().enqueue(task);
    if (!enqueued) {
      throw Exception('Failed to enqueue background upload task for job $jobId');
    }

    await _repo.updateJobStatus(
      jobId: jobId,
      status: 'uploading_background',
      lastError: null,
    );
    DevLog.add('📤 [UploadManager] Master audio PUT handed off to background transfer (job $jobId).');
  }

  /// ③アップロード完了をCloud Runに通知し、lectures.audio_pathを更新してもらう。
  Future<void> _completeMasterAudioUpload({required String lectureId}) async {
    final completeUri = Uri.parse(
      'https://lefture-511705914929.us-west1.run.app/worker/complete-master-audio-upload',
    );

    final completeResponse = await http
        .post(
          completeUri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'lecture_id': lectureId}),
        )
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException(
            'Cloud Run timed out while completing master audio upload for lecture $lectureId',
          ),
        );

    if (completeResponse.statusCode != 200) {
      throw Exception(
        'Cloud Run complete-upload error (${completeResponse.statusCode}): ${completeResponse.body}',
      );
    }

    DevLog.add('🚀 [UploadManager] Master Audio $lectureId をR2へ直接送信完了！');
  }

  /// background_downloaderがマスター音声PUTタスクの状態変化を通知してくる
  /// たびに呼ばれる(アプリ生存中はリアルタイムに、サスペンド中に完了/失敗
  /// していた分はinitialize()のFileDownloader().start()がリプレイする)。
  void _handleMasterAudioTaskUpdate(TaskStatusUpdate update) {
    unawaited(_processMasterAudioTaskUpdate(update));
  }

  Future<void> _processMasterAudioTaskUpdate(TaskStatusUpdate update) async {
    final jobId = update.task.taskId;
    final job = await _repo.getJobById(jobId);
    if (job == null) {
      // discard/削除等でジョブ行自体が既に消えている場合。転送自体はもう
      // 意味を持たないので何もしない。
      DevLog.add(
        '⚠️ [UploadManager] Background task update for unknown job $jobId (status=${update.status}), ignoring.',
      );
      return;
    }

    switch (update.status) {
      case TaskStatus.complete:
        if (update.responseStatusCode != null && update.responseStatusCode != 200) {
          await _failMasterAudioJob(
            job,
            'R2 upload error (${update.responseStatusCode}): ${update.responseBody}',
          );
          return;
        }
        try {
          // ★ ここ(PUT完了の通知を受け取った直後)はURLSessionの保護区間の
          // 外。iOSがバックグラウンドURLSessionイベントの処理のためにアプリを
          // 一瞬起こしているだけの可能性があり、その猶予は短い。Cloud Runへの
          // 完了通知(ネットワーク往復)がその猶予を超えると、実行そのものを
          // 打ち切られてしまう——PUT自体は無事終わっているのに③が呼べず
          // 「アップロードは完了しているのにサーバー側は何も知らない」という
          // 一番困る状態になる。BackgroundTaskで明示的に実行猶予を要求する。
          await BackgroundTask.protect('lefture.completeMasterAudioUpload', () async {
            await _completeMasterAudioUpload(lectureId: job.lectureId);

            // アップロード成功後、ローカルの一時圧縮ファイルを削除する。
            final asset = await _repo.getAsset(job.assetId);
            final localPath = asset?.localPath;
            if (localPath != null) {
              try {
                final file = File(localPath);
                if (await file.exists()) {
                  await file.delete();
                  DevLog.add('🧹 [UploadManager] Master audio local file deleted.');
                }
              } catch (cleanupError) {
                DevLog.add('⚠️ [UploadManager] Master audio cleanup failed: $cleanupError');
              }
            }

            await _onJobSucceeded(job);
          });
        } catch (e) {
          await _failMasterAudioJob(job, e.toString());
        }
      case TaskStatus.failed:
      case TaskStatus.notFound:
        await _failMasterAudioJob(
          job,
          update.exception?.description ?? 'Background upload failed (${update.status})',
        );
      case TaskStatus.canceled:
        // ユーザーがcancelUploadを押した場合、DB側は既にcancelPendingUploadsFor
        // Lectureによって'cancelled'になっている想定なので、ここでは何もしない
        // (上書きしてretry_waitに戻すと、止めたはずのアップロードが再開して
        // しまう)。
        DevLog.add('🛑 [UploadManager] Background master audio upload canceled for job $jobId.');
      case TaskStatus.enqueued:
      case TaskStatus.running:
      case TaskStatus.waitingToRetry:
      case TaskStatus.paused:
        // 中間状態。何もしない。
        break;
    }
  }

  /// マスター音声のバックグラウンド転送が失敗した時の後始末。
  /// _processQueueの通常経路と同じ指数バックオフでretry_waitに戻すことで、
  /// 次のポーリング/DB監視で自然に再試行される(再試行時は_performUploadが
  /// 新しい署名付きURLを取り直してから再度バックグラウンド転送を開始する)。
  Future<void> _failMasterAudioJob(LocalUploadJob job, String error) async {
    final nextAttempt = job.attemptCount + 1;
    final delaySeconds = _backoffSeconds(nextAttempt);
    final nextRetry = DateTime.now().toUtc().add(Duration(seconds: delaySeconds));

    DevLog.add(
      '❌ [UploadManager] Background master audio upload failed for ${job.id} '
      '(attempt $nextAttempt, next retry in ${delaySeconds}s): $error',
    );

    await _repo.updateJobStatus(
      jobId: job.id,
      status: 'retry_wait',
      lastError: error,
      nextRetryAt: nextRetry,
      attemptCount: nextAttempt,
    );
  }

  /// ★ 以前はここで例外を握りつぶしてDevLogに書くだけだったため、失敗しても
  /// 誰にも気づかれず、講義が音声だけアップロードされて分析が永遠に始まらない
  /// まま放置される事故が起きた。今は呼び出し元(_performUpload経由でstart_analysis
  /// ジョブとして実行される)の共通リトライ機構に乗せるため、例外はそのまま
  /// 投げっぱなしにする(呼び出し元がlastError記録とバックオフ再試行を行う)。
  Future<void> _callStartAnalysis({
    required String lectureId,
    required int expectedChunks,
  }) async {
    final session = supabase.auth.currentSession;
    final jwt = session?.accessToken;

    if (jwt == null) {
      throw Exception('ログインしていません。分析を開始できません。');
    }

    final url = Uri.parse('https://lefture-511705914929.us-west1.run.app/start-analysis');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode({
        'lecture_id': lectureId,
        'expected_chunks': expectedChunks,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 202) {
      DevLog.add('🚀 start_analysis (Cloud Run) の呼び出し成功！');
      return;
    }

    if (response.statusCode == 402) {
      // job_repository.dart(手動Start Analysisボタン側)と同じパース処理。
      // ここでも型付きの例外を投げないと、_processQueue側で「クレジット不足は
      // 待っても解決しない」ことを判定できず、無限に指数バックオフでリトライ
      // し続けてしまう。
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final detail = body['detail'] as Map<String, dynamic>?;
        if (detail != null && detail['error_code'] != null) {
          throw InsufficientCreditsException(
            errorCode: detail['error_code'] as String,
            message: detail['message'] as String? ?? 'Insufficient credits.',
          );
        }
      } on InsufficientCreditsException {
        rethrow;
      } catch (_) {
        // パース失敗時は下の汎用Exceptionにフォールスルーする
      }
    }

    throw Exception('Cloud Runエラー (${response.statusCode}): ${response.body}');
  }
}