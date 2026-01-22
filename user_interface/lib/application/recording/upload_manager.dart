import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

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

    // オフラインなら何もしない
    final connectivity = await Connectivity().checkConnectivity();
    if (_isOffline(connectivity)) return;

    _isProcessing = true;

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
          
          // Jobを物理削除してもいいが、履歴として残すなら 'done' でOK
          // ここでは「成功したらキューから消す」運用にするなら deleteJob を呼ぶ

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
    // 1. 必要なデータを集める
    final lecture = await _repo.getLecture(job.lectureId);
    final asset = await _repo.getAsset(job.assetId);

    // データがない場合（Discardされた？）
    if (lecture == null || asset == null) {
      // 復旧不可能なので例外を投げて失敗扱いにする（またはここでJob削除）
      throw Exception('Lecture or Asset not found (maybe discarded?)');
    }

    final localPath = asset.localPath;
    if (localPath == null || !File(localPath).existsSync()) {
      throw Exception('Local file not found at $localPath');
    }

    // 2. Supabaseへの書き込み
    // A) Lecturesテーブル (FK制約のため親から)
    await _lectureWriter.upsertLecture(
      lectureId: lecture.id,
      ownerId: lecture.ownerId,
      folderId: lecture.folderId,
      title: lecture.title,
      lectureDateTimeUtc: lecture.lectureDatetime,
    );

    // B) Storageへファイルアップロード
    //    Assetテーブルにある storagePath 予定地を使う
    //    (ファイル名は assetId.m4a のはず)
    final fileName = '${job.assetId}.m4a'; 
    
    // uploadAudioFileは内部で upsert: true になっているので冪等
    final remotePath = await _uploader.uploadAudioFile(
      userId: lecture.ownerId,
      lectureId: lecture.id,
      localPath: localPath,
      fileName: fileName,
    );

    // C) LectureAssetsテーブル
    await _lectureWriter.upsertAudioAsset(
      assetId: asset.id,
      lectureId: lecture.id,
      ownerId: lecture.ownerId,
      bucket: _uploader.audioBucket,
      path: remotePath,
    );

    // D) ローカルのAsset情報も更新（storagePathが入る）
    await _repo.updateAssetUploaded(
      assetId: asset.id, 
      remotePath: remotePath,
    );
  }
}