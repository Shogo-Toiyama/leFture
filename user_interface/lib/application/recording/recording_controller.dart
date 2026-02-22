import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:lecture_companion_ui/core/services/audio_record/audio_chunker.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/services/audio_record/audio_recorder_service.dart';
import '../../infrastructure/local_db/repositories/recording_repository_drift.dart';
import 'recording_state.dart';
import 'upload_manager.dart'; // Step 2で修正しますが、今はトリガー用として残します

part 'recording_controller.g.dart';

@Riverpod(keepAlive: true)
AudioRecorderService audioRecorderService(Ref ref) {
  final svc = AudioRecorderService();
  ref.onDispose(svc.dispose);
  return svc;
}

@Riverpod(keepAlive: true)
class RecordingController extends _$RecordingController {
  StreamSubscription? _dbSubscription;
  Timer? _timer;
  AudioChunker? _chunker;
  StreamSubscription? _audioStreamSub;
  int _currentChunkIndex = 0;

  // 依存サービス
  RecordingRepositoryDrift get _repo => ref.read(recordingRepositoryDriftProvider);
  AudioRecorderService get _recorder => ref.read(audioRecorderServiceProvider);
  UploadManager get _uploadMgr => ref.read(uploadManagerProvider);

  @override
  RecordingState build() {
    // Controller破棄時に監視系をストップ
    ref.onDispose(() {
      _dbSubscription?.cancel();
      _timer?.cancel();
    });

    return RecordingState.idle();
  }

  // --- 内部メソッド: DB監視開始 ---
  void _startWatchingLecture(String lectureId) {
    _dbSubscription?.cancel();
    _dbSubscription = _repo.watchLecture(lectureId).listen((localLecture) {
      // DBが更新されるたびにStateを更新
      // これにより setTitle などを呼んだ直後にここが反応してUIが変わる
      state = state.copyWith(lecture: localLecture);
    });
  }

  // --- User Actions ---

  /// 新規録音セッションの開始準備（Startボタン押下）
  Future<void> toggleStartStopResume() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'You must be signed in to record.',
      );
      return;
    }

    // 1. Idle -> Start (新規作成)
    if (state.phase == RecordingPhase.idle) {
      await _startRecordingSession();
      return;
    }

    // 2. Recording -> Pause (一時停止)
    if (state.phase == RecordingPhase.recording) {
      // ストリームは一旦止まる（または一時停止する）
      await _recorder.pause(); 
      _timer?.cancel();

      // ここでバケツの中身を安全にFlush（保存＆キュー追加）
      final pausedChunk = _chunker?.flush();
      if (pausedChunk != null && pausedChunk.isNotEmpty) {
        final path = await _recorder.savePcmAsWav(pausedChunk, state.currentLectureId!);
        await _repo.attachAudioAndEnqueueUpload(
          ownerId: user.id,
          lectureId: state.currentLectureId!,
          localPath: path,
          sequenceIndex: _currentChunkIndex,
        );
        _currentChunkIndex++; // ちゃんと番号も進める
      }

      state = state.copyWith(phase: RecordingPhase.paused);
      return;
    }

    // 3. Paused -> Resume (再開)
    if (state.phase == RecordingPhase.paused) {
      await _recorder.resume();
      _startTimer();
      state = state.copyWith(phase: RecordingPhase.recording);
      return;
    }
  }

  Future<void> _startRecordingSession() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'You must be signed in to record.',
      );
      return;
    }

    // マイク＆通知権限チェック
    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
      Permission.notification,
    ].request();

    // マイク権限チェック
    if (statuses[Permission.microphone] != PermissionStatus.granted) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'Microphone permission is required.',
      );
      return;
    }

    state = state.copyWith(phase: RecordingPhase.requestingPermission, clearErrorMessage: true);

    try {
      // A. DBにDraft作成 (ここでIDが確定)
      //    (Step 0の RecordingRepositoryDrift を使用)
      final lectureId = await _repo.createDraftLecture(
        ownerId: user.id,
        presetFolderId: state.folderId, // ← Getter経由で draftFolderId が渡される
        presetTitle: state.title.isNotEmpty ? state.title : null,
      );

      // B. DB監視開始
      state = state.copyWith(currentLectureId: lectureId);
      _startWatchingLecture(lectureId);

      _currentChunkIndex = 0; // 録音開始時にチャンク番号をリセット

      // C. Chunker（分割職人）の準備と、分割完了時のルールを決める
      _chunker = AudioChunker(
        onChunkReady: (Uint8List chunkData) async {
          log('[Chunker] Chunk $_currentChunkIndex is ready! Size: ${chunkData.length}');
          
          // ① チャンクデータをWAVとして保存（Serviceに追加したメソッドを呼ぶ）
          final path = await _recorder.savePcmAsWav(chunkData, lectureId);
          
          // ② DBのキューに積む（順番も記録する！）
          await _repo.attachAudioAndEnqueueUpload(
            ownerId: user.id,
            lectureId: lectureId,
            localPath: path,
            sequenceIndex: _currentChunkIndex,
          );
          
          _currentChunkIndex++; // 次のチャンクのために番号を増やす
          
          // ③ アップロードのキューを回す
          _uploadMgr.tryProcessQueue();
        },
      );

      // D. マイクのStream（川の流れ）を開通させる
      // ※ Service側の start() を startStream() に変更した想定
      final audioStream = await _recorder.startStream();

      // E. 川の流れを監視して、データを随時Chunkerに流し込む
      _audioStreamSub = audioStream.listen((data) {
        _chunker!.processAudioStream(data);
      });

      // F. タイマー開始
      _startTimer();
      state = state.copyWith(phase: RecordingPhase.recording);

    } catch (e) {
      state = state.copyWith(phase: RecordingPhase.error, errorMessage: 'Failed to start: $e');
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      log('[Timer] Tick: ${state.elapsedSeconds + 1} (Phase: ${state.phase})');
      state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
    });
  }

  /// タイトル変更 (DB即時反映)
  Future<void> setTitle(String newTitle) async {
    state = state.copyWith(title: newTitle);
    final lecture = state.lecture;
    if (lecture != null) {
      await _repo.updateLectureTitle(
        ownerId: lecture.ownerId,
        lectureId: lecture.id,
        title: newTitle,
      );
    }
  }

  /// フォルダ変更 (DB即時反映)
  Future<void> setFolderId(String? folderId) async {
    state = state.copyWith(
      folderId: folderId,
      forceClearFolderId: folderId == null,
    );
    final lecture = state.lecture;
    if (lecture != null) {
      await _repo.updateLectureFolder(
        ownerId: lecture.ownerId,
        lectureId: lecture.id,
        folderId: folderId,
      );
    }
  }

  /// Uploadボタン押下時: 録音停止 -> DBにJob作成 -> UploadManagerキック
  Future<void> upload() async {
    if (!state.canUpload) return;

    final lecture = state.lecture;
    if (lecture == null) return;

    if (lecture.title?.isEmpty ?? true) {
      await setTitle('Untitled Lecture'); 
    }

    state = state.copyWith(phase: RecordingPhase.uploading, clearErrorMessage: true);

    try {
      // 1. 川の流れ（Stream）の監視をストップし、マイク自体も止める
      await _audioStreamSub?.cancel();
      await _recorder.stop();
      _timer?.cancel();

      // 2. Chunkerのバケツに残っている最後のデータを絞り出す (Flush)
      final finalChunk = _chunker?.flush();
      
      // 3. もし端数データが残っていたら、最後のファイルとして保存してキューに積む
      if (finalChunk != null && finalChunk.isNotEmpty) {
        log('[Chunker] Final chunk is ready! Size: ${finalChunk.length} bytes');
        
        final path = await _recorder.savePcmAsWav(finalChunk, lecture.id);
        
        await _repo.attachAudioAndEnqueueUpload(
          ownerId: lecture.ownerId,
          lectureId: lecture.id,
          localPath: path,
          sequenceIndex: _currentChunkIndex, // 最後の番号を付ける
        );
      }

      // 4. キューに入れたので、完了状態（Queued）にする
      state = state.copyWith(phase: RecordingPhase.queued);

      // 5. UploadManagerを叩いて、溜まっているファイルの送信を始める
      _uploadMgr.tryProcessQueue();

    } catch (e) {
      state = state.copyWith(
        phase: RecordingPhase.error, 
        errorMessage: 'Save failed: $e'
      );
    }
  }

  /// キャンセル・破棄
  Future<void> cancelAndDiscard() async {
    // ストリームの監視を解除して録音停止
    await _audioStreamSub?.cancel();
    await _recorder.stop();
    _timer?.cancel();
    _dbSubscription?.cancel();

    // ※ Discardなので、_chunker?.flush() は呼ばずにバケツの中身は捨てます！
    
    // DBからこのLectureと、今までキューに積んだチャンクを全削除
    if (state.currentLectureId != null) {
      await _repo.deleteLectureAndAssets(state.currentLectureId!);
    }
    
    // アイドルに戻す
    state = RecordingState.idle();
  }

  Future<void> openSettingsIfNeeded() async {
    await openAppSettings();
  }
}