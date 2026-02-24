import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:http/http.dart' as http;

import '../../infrastructure/supabase/services/lecture_write_service.dart';
import '../../infrastructure/supabase/services/storage_upload_service.dart';
import '../../infrastructure/local_db/repositories/recording_repository_drift.dart';
import '../../infrastructure/local_db/app_database.dart';

part 'upload_manager.g.dart';

@Riverpod(keepAlive: true)
UploadManager uploadManager(Ref ref) {
  final mgr = UploadManager(
    repo: ref.read(recordingRepositoryDriftProvider),
    uploader: ref.read(storageUploadServiceProvider),
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
    required StorageUploadService uploader,
    required LectureWriteService lectureWriter,
  })  : _repo = repo,
        _uploader = uploader,
        _lectureWriter = lectureWriter;

  final RecordingRepositoryDrift _repo;
  final StorageUploadService _uploader;
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

    // オフラインなら何もしない
    final connectivity = await Connectivity().checkConnectivity();
    if (_isOffline(connectivity)) return;

    try {
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
            print('Lecture not found (maybe discarded?)');
            continue;
          }
          final expectedChunks = lecture.expectedChunks;
          
          // A. もし「未送信がゼロ」かつ「録音が終了している」なら、全部送り切った証拠！！
          if (remainingJobs.isEmpty && expectedChunks != null) {
            print('🎉 全てのチャンクの送信完了！分析開始の号砲を鳴らします！');
            
            try {
              // SupabaseのEdge Functionを呼び出す
              await supabase.functions.invoke('start_analysis', body: {
                'lecture_id': lecture.id,
                'expected_chunks': expectedChunks, 
              });
              print('🚀 start_analysis の呼び出し成功！');
            } catch (invokeError) {
              print('❌ start_analysis の呼び出しでエラー: $invokeError');
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
      ownerId: lecture.ownerId,
      folderId: lecture.folderId,
      title: lecture.title,
      lectureDateTimeUtc: lecture.lectureDatetime,
    );

    final seqStr = asset.sequenceIndex.toString().padLeft(3, '0');
    final fileName = 'chunk_$seqStr.wav'; 
    final storagePath = 'chunks/$fileName';

    // 3. lecture_transcripts テーブルに「PROCESSING」を登録
    try {
      await supabase.from('lecture_transcripts').upsert({
        'lecture_id': lecture.id,
        'chunk_index': asset.sequenceIndex,
        'storage_path': storagePath, // 予測されるパスを先に入れておく
        'status': 'PROCESSING',
      });
      print('📝 [UploadManager] 処理開始(PROCESSING)をDBに登録しました: Chunk ${asset.sequenceIndex}');
    } catch (e) {
      print('❌ [UploadManager] DBへの受付票登録に失敗: $e');
      rethrow; 
    }

    // 4. Cloud RunへのPOST と Storageへのアップロードを「並列」で実行
    String? remotePath;
    try {
      await Future.wait([
        // A) StorageへWAVファイルをアップロード (終わったら remotePath に代入)
        _uploader.uploadAudioFile(
          userId: lecture.ownerId,
          lectureId: lecture.id,
          localPath: localPath,
          fileName: storagePath,
        ).then((path) => remotePath = path),
        
        // B) Cloud Runに直接POSTして文字起こしを開始
        _postToCloudRun(
          localPath: localPath,
          lectureId: lecture.id,
          chunkIndex: asset.sequenceIndex,
        ),
      ]);
    } catch (e) {
      print('❌ [UploadManager] 通信エラー、後でリトライします: $e');
      rethrow; 
    }

    // 5. 両方成功したら、ローカルのAsset情報も更新（アップロード完了の目印）
    if (remotePath != null) {
      await _repo.updateAssetUploaded(
        assetId: asset.id, 
        remotePath: remotePath!,
      );
    }
  }

  /// Cloud RunのFastAPIへ直接WAVファイルを投げるメソッド
  Future<void> _postToCloudRun({
    required String localPath,
    required String lectureId,
    required int chunkIndex,
  }) async {
    // Cloud RunのURL
    final uri = Uri.parse('https://lefture-511705914929.us-west1.run.app/worker/transcribe-chunk');
    
    final request = http.MultipartRequest('POST', uri);
    
    // Cloud Run側が「どのデータか」分かるようにメタデータを送る
    request.fields['lecture_id'] = lectureId;
    request.fields['chunk_index'] = chunkIndex.toString();
    
    // WAVファイルをバイナリとして添付
    request.files.add(await http.MultipartFile.fromPath('file', localPath));

    // 送信してレスポンスを待つ
    final response = await request.send();
    
    if (response.statusCode != 200) {
      final respStr = await response.stream.bytesToString();
      throw Exception('Cloud Run error (${response.statusCode}): $respStr');
    }
    
    print('🚀 [UploadManager] Cloud RunにChunk $chunkIndex を送信完了！');
  }
}