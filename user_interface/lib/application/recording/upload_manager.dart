import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
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

          await _performUpload(job);

          // 成功！ -> Jobを完了にする
          await _repo.updateJobStatus(
            jobId: job.id,
            status: 'done',
            lastError: null,
          );

          // チャンク音声はアップロード完了後、ローカルの一時ファイルはもう不要。
          // マスター音声側(_performUpload内)では既に削除しているが、こちらの
          // チャンク側は削除処理が漏れていたため、ここで同様に掃除する。
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
            continue;
          }
          // 削除済み講義では分析を発火させない。削除処理(LectureController.
          // deleteLecture)はこの講義のジョブを消してから論理削除するが、
          // ちょうどこのジョブが実行中だった場合だけはすり抜けるため、
          // 発火の直前でもう一度確認する。
          if (lecture.deletedAt != null) {
            DevLog.add('🗑️ [UploadManager] Lecture is deleted, skipping start-analysis trigger.');
            continue;
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
            continue;
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
              continue;
            }
            // コースが未選択の場合は自動分析を開始しない
            if (lecture.courseId == null) {
              DevLog.add('⏸️ コース未選択のため、自動分析はスキップします（手動でStart Analysisが必要）。');
              continue;
            }

            // 二重発火ガード。保存時(RecordingController._maybeEnqueueStartAnalysis)
            // も号砲を鳴らしうるため、既にジョブがあるなら何もしない。
            if (await _repo.hasStartAnalysisJobForLecture(lecture.id)) {
              DevLog.add('⏭️ [UploadManager] start_analysisジョブが既に存在するため、二重発火を回避します。');
              continue;
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
              continue;
            }
            if (lecture.courseId == null) {
              DevLog.add('⏸️ コース未選択のため、自動分析はスキップします（手動でStart Analysisが必要）。');
              continue;
            }

            DevLog.add('🎉 マスター音声の送信完了！分析開始の号砲を鳴らします！');
            await _repo.enqueueStartAnalysis(
              userId: lecture.userId,
              lectureId: lecture.id,
              assetId: job.assetId,
            );
          }
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
          // 指数バックオフ: 30秒, 60秒, 120秒 ... 上限5分(300秒)でそれ以上は伸ばさない
          const maxBackoffSeconds = 5 * 60;
          final delaySeconds = min(30 * pow(2, nextAttempt - 1).toInt(), maxBackoffSeconds);
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

  Future<void> _performUpload(LocalUploadJob job) async {
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
      return;
    }

    // start_analysisジョブはファイルを送るわけではなく、Cloud Runの
    // /start-analysisを叩くだけなので、ローカルファイルの存在チェックより前で分岐する
    // (紐づくassetIdは他ジョブ完了時の使い回しで、ローカルファイルは既に削除済みのことがある)。
    if (job.kind == 'start_analysis') {
      await _callStartAnalysis(
        lectureId: lecture.id,
        expectedChunks: (lecture.isRealtime == true) ? (lecture.expectedChunks ?? 0) : 0,
      );
      return;
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
        await _postMasterAudioToCloudRun(
          localPath: localPath,
          lectureId: lecture.id,
        );
        
        // アップロード成功後、ローカルの一時圧縮ファイルを削除する
        try {
          final file = File(localPath);
          if (await file.exists()) {
            await file.delete();
            DevLog.add('🧹 [UploadManager] Master audio local file deleted.');
          }
        } catch (cleanupError) {
          DevLog.add('⚠️ [UploadManager] Master audio cleanup failed: $cleanupError');
        }
      } catch (e) {
        DevLog.add('❌ [UploadManager] マスターオーディオ通信エラー、後でリトライします: $e');
        rethrow;
      }
      return;
    }

    // 従来のチャンク処理（kind == 'audio_upload' の想定）
    // Realtime Transcribe が Off の講義では個別チャンクを送信しない
    // (CheckAndAssemble が expected_chunks=0 のまま誤発火するのを防ぐ二重の安全策)
    if (lecture.isRealtime == false) {
      DevLog.add('⏭️ [UploadManager] Realtime Transcribe is OFF, discarding stray chunk job: Chunk ${asset.sequenceIndex}');
      return;
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

  /// マスターオーディオ(M4A)をR2へ直接アップロードするメソッド。
  /// Cloud Runには32MBのリクエストボディ上限があり、64kbpsの音声でも約70分の
  /// 録音で超えてしまう（60〜90分超の講義は普通にあるため構造的な問題だった）。
  /// そのためCloud Runは「署名付きURLの発行」と「完了記録」だけを行い、
  /// 実際のファイル転送はR2へ直接行う。
  Future<void> _postMasterAudioToCloudRun({
    required String localPath,
    required String lectureId,
  }) async {
    // 1. 署名付きアップロードURLをCloud Runから取得（小さいJSONリクエスト）
    const contentType = 'audio/x-m4a';
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

    final uploadUrl = jsonDecode(requestUrlResponse.body)['upload_url'] as String;

    // 2. R2へ直接PUT（Cloud Runを経由しないので32MB上限に引っかからない）
    // ★ Content-Typeはバックエンドが署名付きURLを発行した際の値と完全に
    // 一致させる必要がある（不一致だとR2が署名検証で拒否する）。
    final fileBytes = await File(localPath).readAsBytes();
    final putResponse = await http
        .put(
          Uri.parse(uploadUrl),
          headers: {'Content-Type': contentType},
          body: fileBytes,
        )
        .timeout(
          const Duration(minutes: 5),
          onTimeout: () => throw TimeoutException(
            'R2 timed out while uploading master audio for lecture $lectureId',
          ),
        );

    if (putResponse.statusCode != 200) {
      throw Exception('R2 upload error (${putResponse.statusCode}): ${putResponse.body}');
    }

    // 3. アップロード完了をCloud Runに通知し、lectures.audio_pathを更新してもらう
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