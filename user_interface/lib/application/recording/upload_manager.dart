import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:lefture/core/utils/connectivity_utils.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
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
  bool _isProcessing = false;

  void initialize() {
    // 1. ネットワーク復帰監視
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((event) {
      if (!isConnectivityOffline(event)) {
        _processQueue(); // ネットが戻ったら処理開始
      }
    });

    // 2. DB監視 (Jobが追加されたり、リトライ待ちが解けたりしたら反応)
    _jobSubscription = _repo.watchPendingJobs().listen((jobs) {
      // 未処理のジョブがあり、かつ今処理中でなければ開始
      if (jobs.isNotEmpty && !_isProcessing) {
        _processQueue();
      }
    });
  }

  void dispose() {
    _jobSubscription?.cancel();
    _connectivitySubscription?.cancel();
  }

  /// 外部から手動で呼び出す用（Refreshボタンなど）
  void tryProcessQueue() => _processQueue();

  Future<void> _processQueue() async {
    // 二重実行防止
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // オフラインなら何もしない
      // ★ この判定をtry内に置くのが重要: tryの外でreturnすると、finallyで
      // _isProcessingをfalseに戻す処理を素通りしてしまい、一度オフライン判定
      // (誤検知含む)が起きただけでアップロードが永久に止まってしまうバグになる。
      final connectivity = await Connectivity().checkConnectivity();
      if (isConnectivityOffline(connectivity)) {
        DevLog.add('📡 [UploadManager] Offline detected, skipping this round.');
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
          // やることなし
          break;
        }

        // 先頭の1件を取り出す
        final job = readyJobs.first;

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
          final expectedChunks = lecture.expectedChunks;
          
          // リアルタイム時の自動発火判定
          if (lecture.isRealtime == true && remainingJobs.isEmpty && expectedChunks != null) {
            if (lecture.autoStartAnalysis == false) {
              DevLog.add('⏸️ 自動分析がOFFのため、自動発火はスキップします（手動でStart Analysisが必要）。');
              continue;
            }
            // コースが未選択の場合は自動分析を開始しない
            if (lecture.courseId == null) {
              DevLog.add('⏸️ コース未選択のため、自動分析はスキップします（手動でStart Analysisが必要）。');
              continue;
            }

            DevLog.add('🎉 全てのチャンクの送信完了！分析開始の号砲を鳴らします！');
            await _triggerStartAnalysis(lectureId: lecture.id, expectedChunks: expectedChunks);
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
            await _triggerStartAnalysis(lectureId: lecture.id, expectedChunks: 0);
          }
        } catch (e) {
          // 失敗...
          // リトライ回数を増やし、次のリトライ時刻を設定
          // ★ attemptCountを実際にDBへ書き戻す（以前はここが抜けていて常に0のまま
          // だったため、指数バックオフのつもりが実質「常に30秒固定」になっていた）
          final nextAttempt = job.attemptCount + 1;
          // 指数バックオフ: 30秒, 60秒, 120秒 ... 上限5分(300秒)でそれ以上は伸ばさない
          const maxBackoffSeconds = 5 * 60;
          final delaySeconds = min(30 * pow(2, nextAttempt - 1).toInt(), maxBackoffSeconds);
          final nextRetry = DateTime.now().toUtc().add(Duration(seconds: delaySeconds));

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
    final asset = await _repo.getAsset(job.assetId);

    // データがない場合（ユーザーが途中でDiscardして消した等）
    if (lecture == null || asset == null) {
      throw Exception('Lecture or Asset not found (maybe discarded?)');
    }

    final localPath = asset.localPath;
    if (localPath == null || !File(localPath).existsSync()) {
      throw Exception('Local file not found at $localPath');
    }

    // 2. Supabaseへの書き込み (Lecturesテーブル)
    await _lectureWriter.upsertLecture(
      lectureId: lecture.id,
      userId: lecture.userId,
      courseId: lecture.courseId,
      title: lecture.title,
      lectureDateTimeUtc: lecture.lectureDatetime ?? lecture.createdAt,
    );

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
    final seqStr = asset.sequenceIndex.toString().padLeft(3, '0');
    final fileName = 'chunk_$seqStr.m4a';
    final storagePath = '${lecture.userId}/${lecture.id}/audio_chunks/$fileName';

    // 4. lecture_transcripts テーブルに「PROCESSING」を登録
    try {
      await supabase.from('lecture_transcripts').upsert({
        'lecture_id': lecture.id,
        'chunk_index': asset.sequenceIndex,
        'storage_path': storagePath, // 予測されるパスを先に入れておく
        'status': 'PROCESSING',
        'start_time': asset.startTime,
      }, onConflict: 'lecture_id,chunk_index');
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

  Future<void> _triggerStartAnalysis({
    required String lectureId,
    required int expectedChunks,
  }) async {
    try {
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
      } else {
        throw Exception('Cloud Runエラー (${response.statusCode}): ${response.body}');
      }
    } catch (invokeError) {
      DevLog.add('❌ start_analysis の呼び出しでエラー: $invokeError');
    }
  }
}