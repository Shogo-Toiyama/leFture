import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:lecture_companion_ui/core/utils/dev_log.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
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
      if (!_isOffline(event)) {
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

  bool _isOffline(dynamic results) {
    if (results is List<ConnectivityResult>) {
      return results.contains(ConnectivityResult.none);
    }
    if (results is ConnectivityResult) {
      return results == ConnectivityResult.none;
    }
    return false;
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
      if (_isOffline(connectivity)) {
        DevLog.add('📡 [UploadManager] Offline detected, skipping this round.');
        return;
      }

      while (true) {
        // オフラインになったら中断
        final currentConn = await Connectivity().checkConnectivity();
        if (_isOffline(currentConn)) break;

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
          
          // Q1. この授業の未送信ジョブはまだ残っているか？
          final remainingJobs = await _repo.getPendingJobsForLecture(job.lectureId);
          
          // Q2. この授業はすでに録音終了（Done）しているか？
          final lecture = await _repo.getLecture(job.lectureId);
          if (lecture == null) {
            DevLog.add('Lecture not found (maybe discarded?)');
            continue;
          }
          final expectedChunks = lecture.expectedChunks;
          
          // A. もし「未送信がゼロ」かつ「録音が終了している」なら、全部送り切った証拠！！
          if (remainingJobs.isEmpty && expectedChunks != null) {
            DevLog.add('🎉 全てのチャンクの送信完了！分析開始の号砲を鳴らします！');
            
            try {
              // 1. Supabaseから現在のユーザーのJWTトークンを取得
              final session = supabase.auth.currentSession;
              final jwt = session?.accessToken;

              if (jwt == null) {
                throw Exception('ログインしていません。分析を開始できません。');
              }

              // 2. Cloud RunのURL (_postToCloudRunで使っているのと同じドメイン)
              final url = Uri.parse('https://lefture-511705914929.us-west1.run.app/start-analysis');

              // 3. 直接Cloud RunへHTTP POSTリクエスト！
              final response = await http.post(
                url,
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $jwt', // 👈 ここでトークンを渡す！
                },
                body: jsonEncode({
                  'lecture_id': lecture.id,
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
              // ※ ここでエラーが起きても、データはStorageに安全に保管されているので、
              // 画面上から「再分析」ボタンなどでリトライできる作りにすれば完璧です！
            }
          }
        } catch (e) {
          // 失敗...
          // リトライ回数を増やし、次のリトライ時刻を設定
          final nextAttempt = job.attemptCount + 1;
          // 指数バックオフ: 30秒, 60秒, 120秒 ...
          final delaySeconds = 30 * pow(2, nextAttempt - 1); 
          final nextRetry = DateTime.now().toUtc().add(Duration(seconds: delaySeconds.toInt()));

          await _repo.updateJobStatus(
            jobId: job.id,
            status: 'retry_wait',
            lastError: e.toString(),
            nextRetryAt: nextRetry,
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
      lectureDateTimeUtc: lecture.lectureDatetime,
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
      });
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

  /// Cloud Runへ直接マスターオーディオ(M4A)ファイルを投げるメソッド
  Future<void> _postMasterAudioToCloudRun({
    required String localPath,
    required String lectureId,
  }) async {
    final uri = Uri.parse('https://lefture-511705914929.us-west1.run.app/worker/upload-master-audio');

    final request = http.MultipartRequest('POST', uri);
    request.fields['lecture_id'] = lectureId;
    request.files.add(await http.MultipartFile.fromPath('file', localPath));

    final response = await request.send().timeout(
      const Duration(minutes: 5),
      onTimeout: () => throw TimeoutException(
        'Cloud Run timed out while uploading master audio for lecture $lectureId',
      ),
    );

    if (response.statusCode != 200) {
      final respStr = await response.stream.bytesToString();
      throw Exception('Cloud Run master upload error (${response.statusCode}): $respStr');
    }

    DevLog.add('🚀 [UploadManager] Cloud RunにMaster Audio $lectureId を送信完了！');
  }
}