import 'dart:async';
import 'dart:developer';
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
    // 1. Idle -> Start (新規作成)
    if (state.phase == RecordingPhase.idle) {
      await _startRecordingSession();
      return;
    }

    // 2. Recording -> Pause (一時停止)
    if (state.phase == RecordingPhase.recording) {
      await _recorder.pause();
      _timer?.cancel();
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
        // UI側で初期フォルダ指定があれば引数に追加しても良い
      );

      // B. DB監視開始
      state = state.copyWith(currentLectureId: lectureId);
      _startWatchingLecture(lectureId);

      // C. 録音ファイルのパス決定
      final dir = await getApplicationDocumentsDirectory();
      final tempPath = p.join(dir.path, 'lectures', lectureId, 'audio', 'recording.m4a');
      
      // D. 録音開始
      await _recorder.start(outputPath: tempPath);

      // E. タイマー開始
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
    final lecture = state.lecture;
    if (lecture == null) return;

    // Stateを直接いじらず、DBを更新する。
    // -> _watchLecture が検知して state.lecture を更新してくれる。
    await _repo.updateLectureTitle(
      ownerId: lecture.ownerId,
      lectureId: lecture.id,
      title: newTitle,
    );
  }

  /// フォルダ変更 (DB即時反映)
  Future<void> setFolderId(String? folderId) async {
    final lecture = state.lecture;
    if (lecture == null) return;

    await _repo.updateLectureFolder(
      ownerId: lecture.ownerId,
      lectureId: lecture.id,
      folderId: folderId,
    );
  }

  /// Uploadボタン押下時: 録音停止 -> DBにJob作成 -> UploadManagerキック
  Future<void> upload() async {
    if (!state.canUpload) return;

    final lecture = state.lecture;
    if (lecture == null) return;

    // バリデーション: タイトルが空ならデフォルトを入れるなど
    if (lecture.title?.isEmpty ?? true) {
      // 必須ならエラーにするか、自動で名前をつける
      await setTitle('Untitled Lecture'); 
    }

    state = state.copyWith(phase: RecordingPhase.uploading, clearErrorMessage: true);

    try {
      // 1. 録音停止 & ファイル確定
      final path = await _recorder.stop();
      _timer?.cancel();

      if (path == null) {
        throw Exception('Recording file not found.');
      }

      // 2. DBトランザクション実行 (Step 0の成果)
      //    Asset情報とUploadJobを一括登録
      await _repo.attachAudioAndEnqueueUpload(
        ownerId: lecture.ownerId,
        lectureId: lecture.id,
        localPath: path,
      );

      // 3. 完了状態へ
      //    (UploadManagerは裏で動くので、UIとしては "Queued" か "Done" に遷移)
      state = state.copyWith(phase: RecordingPhase.queued);

      // 4. UploadManagerに通知
      _uploadMgr.tryProcessQueue();

      // UI側で少し待ってから閉じる処理が入っているため、uploadedへの遷移も可
      // state = state.copyWith(phase: RecordingPhase.uploaded);

    } catch (e) {
      state = state.copyWith(
        phase: RecordingPhase.error, 
        errorMessage: 'Save failed: $e'
      );
    }
  }

  /// キャンセル・破棄
  Future<void> cancelAndDiscard() async {
    // 録音停止
    await _recorder.stop();
    _timer?.cancel();
    _dbSubscription?.cancel();

    // 実際のファイル削除やDBの論理削除などはここで行う
    // (Repositoryに deleteLecture などのメソッドがあれば呼ぶ)
    
    // アイドルに戻す
    state = RecordingState.idle();
  }

  Future<void> openSettingsIfNeeded() async {
    await openAppSettings();
  }
}