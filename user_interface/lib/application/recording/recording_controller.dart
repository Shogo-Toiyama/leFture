import 'dart:async';
import 'dart:typed_data';
import 'package:lecture_companion_ui/core/services/audio_record/audio_chunker.dart';
import 'package:lecture_companion_ui/core/services/recording_preferences.dart';
import 'package:lecture_companion_ui/core/utils/dev_log.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/repositories/lecture_moment_repository_drift.dart';
import 'package:lecture_companion_ui/application/asr/live_asr_controller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/services/audio_record/audio_recorder_service.dart';
import '../../infrastructure/local_db/repositories/recording_repository_drift.dart';
import 'recording_language_controller.dart';
import 'recording_state.dart';
import 'upload_manager.dart';

part 'recording_controller.g.dart';

/// コースとキーワードから Groq Whisper 用コンテキスト文字列を生成する
Future<String> _buildWhisperContext({
  required String uid,
  required String courseId,
}) async {
  final parts = <String>[];

  try {
    // 1. コースタイトルを取得
    final courseRow = await supabase
        .from('courses')
        .select('course_title, course_code')
        .eq('id', courseId)
        .eq('user_id', uid)
        .maybeSingle();

    if (courseRow != null) {
      final title = courseRow['course_title'] as String? ??
          courseRow['course_code'] as String?;
      if (title != null && title.isNotEmpty) {
        parts.add('Course: $title');
      }
    }

    // 2. 同コースの過去講義キーワードを取得（最新20件）
    final lectureRows = await supabase
        .from('lectures')
        .select('id')
        .eq('course_id', courseId)
        .eq('user_id', uid)
        .limit(10);

    final lectureIds = lectureRows.map((r) => r['id'] as String).toList();

    if (lectureIds.isNotEmpty) {
      final kwRows = await supabase
          .from('keywords')
          .select('keyword')
          .inFilter('lecture_id', lectureIds)
          .limit(20);

      final keywords =
          kwRows.map((r) => r['keyword'] as String).toSet().toList();
      if (keywords.isNotEmpty) {
        parts.add('Keywords: ${keywords.join(', ')}');
      }
    }
  } catch (e) {
    DevLog.add('[WhisperContext] Failed to fetch context: $e');
  }

  return parts.join('\n');
}

// dependencies: [] を明示することで、このproviderがdev_tools/のTestタブから
// ProviderScope(overrides: [...])で差し替え可能な「scoped provider」になる。
// 何もオーバーライドしなければ今まで通りルートの単一インスタンスとして動く。
@Riverpod(keepAlive: true, dependencies: [])
AudioRecorderService audioRecorderService(Ref ref) {
  final svc = AudioRecorderService();
  ref.onDispose(svc.dispose);
  return svc;
}

// audioRecorderServiceに依存していることを明示しないと、dev_tools/側で
// ProviderScopeを使ってaudioRecorderServiceProviderをオーバーライドしても
// このControllerには一切伝播しない(常にルートコンテナの本物のマイクを使う
// インスタンスを参照し続ける)。Riverpodの仕様上、これが必須。
@Riverpod(keepAlive: true, dependencies: [audioRecorderService])
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
  LectureMomentRepositoryDrift get _momentRepo => ref.read(lectureMomentRepositoryDriftProvider);

  @override
  RecordingState build() {
    ref.onDispose(() {
      _dbSubscription?.cancel();
      _timer?.cancel();
    });

    // Preferences から保存済みの設定を読み込む
    final prefs = RecordingPreferences();
    return RecordingState.idle().copyWith(
      realtimeTranscribe: prefs.getRealtimeTranscribe(),
      autoStartAnalysis: prefs.getAutoStartAnalysis(),
    );
  }

  void _startWatchingLecture(String lectureId) {
    _dbSubscription?.cancel();
    _dbSubscription = _repo.watchLecture(lectureId).listen((localLecture) {
      state = state.copyWith(lecture: localLecture);
    });
  }

  // --- User Actions ---

  Future<void> toggleStartStopResume() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'You must be signed in to record.',
      );
      return;
    }

    // 1. Idle -> Start
    if (state.phase == RecordingPhase.idle) {
      await _startRecordingSession();
      return;
    }

    // 2. Recording -> Pause
    if (state.phase == RecordingPhase.recording) {
      await _recorder.pause(); 
      _timer?.cancel();

      final flushed = _chunker?.flush();
      if (flushed != null && flushed.data.isNotEmpty) {
        final path = await _recorder.savePcmAsM4a(flushed.data, state.currentLectureId!);
        
        await _repo.attachAudioAndEnqueueUpload(
          userId: user.id,
          lectureId: state.currentLectureId!,
          localPath: path,
          sequenceIndex: _currentChunkIndex,
          startTime: flushed.startTimeSec,
        );
        _currentChunkIndex++; 
      }

      state = state.copyWith(phase: RecordingPhase.paused);
      return;
    }

    // 3. Paused -> Resume
    if (state.phase == RecordingPhase.paused) {
      await _recorder.resume();
      _startTimer();
      state = state.copyWith(phase: RecordingPhase.recording);
      return;
    }
  }

  /// RecordingPageに入った瞬間に呼ぶ早期リクエスト。「授業が始まってしまった!」
  /// という時に録音開始がもたつかないよう、実際に録音ボタンを押すより前に
  /// 済ませておく。結果を待たず、UI状態(RecordingPhaseなど)にも反映しない
  /// ——実際の可否判定・エラー表示は_startRecordingSession側の既存フローに任せる。
  /// 既にpermanentlyDeniedの場合は再プロンプトしても意味が無いのでスキップする。
  Future<void> requestMicPermissionEarly() async {
    final status = await Permission.microphone.status;
    if (status.isGranted || status.isPermanentlyDenied) return;
    await Permission.microphone.request();
  }

  Future<void> _startRecordingSession() async {
    DevLog.add('[StartSession] 1/8 begin');
    final user = supabase.auth.currentUser;
    if (user == null) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'You must be signed in to record.',
      );
      return;
    }

    DevLog.add('[StartSession] 2/8 requesting mic/notification permissions...');
    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
      Permission.notification,
    ].request();
    DevLog.add('[StartSession] 3/8 permission result: $statuses');

    if (statuses[Permission.microphone] != PermissionStatus.granted) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'Microphone permission is required.',
      );
      return;
    }

    state = state.copyWith(phase: RecordingPhase.requestingPermission, clearErrorMessage: true);

    try {
      DevLog.add('[StartSession] 4/8 creating draft lecture...');
      final lectureId = await _repo.createDraftLecture(
        userId: user.id,
        presetCourseId: state.courseId,
        presetTitle: state.title.isNotEmpty ? state.title : null,
        autoStartAnalysis: state.autoStartAnalysis,
        isRealtime: state.realtimeTranscribe,
      );
      DevLog.add('[StartSession] 5/8 draft lecture created: $lectureId');

      // コースが選択されていればWhisperコンテキストをフェッチして保存
      final courseId = state.courseId;
      if (courseId != null) {
        final context = await _buildWhisperContext(uid: user.id, courseId: courseId);
        if (context.isNotEmpty) {
          await _repo.saveWhisperContext(lectureId: lectureId, whisperContext: context);
        }
      }

      state = state.copyWith(currentLectureId: lectureId);
      _startWatchingLecture(lectureId);

      _currentChunkIndex = 0;

      _chunker = AudioChunker(
        onChunkReady: (Uint8List chunkData, double startTimeSec) async {
          // Realtime Transcribe が Off の場合、チャンク送信をスキップ
          if (!state.realtimeTranscribe) {
            DevLog.add('[Chunker] Realtime Transcribe is OFF, skipping chunk upload for Chunk $_currentChunkIndex');
            _currentChunkIndex++;
            return;
          }

          // ★ awaitを挟む前に同期的に採番する: onChunkReadyはAudioChunkerから
          // awaitされずに呼ばれるため、チャンクが立て続けに来ると(15倍速テスト等)
          // 前のチャンクのFFmpegエンコード待ち中に次のチャンクのこのコールバックが
          // 走り出す。_currentChunkIndexの読み取り＋インクリメントがawaitの後だと、
          // 2つの異なるチャンクが同じsequenceIndexを取得してしまう競合状態になる。
          final chunkIndex = _currentChunkIndex++;
          DevLog.add('[Chunker] Chunk $chunkIndex is ready! Size: ${chunkData.length} (Start: ${startTimeSec}s)');

          final path = await _recorder.savePcmAsM4a(chunkData, lectureId);

          await _repo.attachAudioAndEnqueueUpload(
            userId: user.id,
            lectureId: lectureId,
            localPath: path,
            sequenceIndex: chunkIndex,
            startTime: startTimeSec,
          );

          _uploadMgr.tryProcessQueue();
        },
        onMasterDataReady: (Uint8List masterData) async {
          await _recorder.appendMasterRawData(masterData, lectureId);
          // マスター音声への追記と並行して、オンデバイスASRエンジンにも同じ
          // 生PCMを流し込む(Realtime Transcribe OFF、またはモデル未準備の
          // 場合はLiveAsrController側が何もしないので安全)。
          ref.read(liveAsrControllerProvider.notifier).acceptPcm16(masterData);
        },
      );

      if (state.realtimeTranscribe) {
        final recordingLanguage = ref.read(recordingLanguageControllerProvider);
        ref.read(liveAsrControllerProvider.notifier).start(recordingLanguage);
      }

      DevLog.add('[StartSession] 6/8 calling _recorder.startStream()...');
      final audioStream = await _recorder.startStream();
      DevLog.add('[StartSession] 7/8 _recorder.startStream() returned, subscribing...');

      _audioStreamSub = audioStream.listen(
        (data) {
          _chunker!.processAudioStream(data);
        },
        onError: (Object e, StackTrace st) {
          DevLog.add('🔴 [StartSession] audioStream error: $e\n$st');
        },
      );

      _startTimer();
      state = state.copyWith(phase: RecordingPhase.recording);
      DevLog.add('[StartSession] 8/8 recording phase active');

    } catch (e, st) {
      DevLog.add('🔴 [StartSession] failed: $e\n$st');
      state = state.copyWith(phase: RecordingPhase.error, errorMessage: 'Failed to start: $e');
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      DevLog.add('[Timer] Tick: ${state.elapsedSeconds + 1} (Phase: ${state.phase})');
      state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
    });
  }

  Future<void> setAutoStartAnalysis(bool value) async {
    state = state.copyWith(autoStartAnalysis: value);
    // Preferences に保存
    await RecordingPreferences().setAutoStartAnalysis(value);

    final lecture = state.lecture;
    if (lecture != null) {
      await _repo.updateLectureAutoStartAnalysis(
        userId: lecture.userId,
        lectureId: lecture.id,
        autoStartAnalysis: value,
      );
    }
  }

  Future<void> setRealtimeTranscribe(bool value) async {
    if (state.phase == RecordingPhase.idle) {
      state = state.copyWith(realtimeTranscribe: value);
      // Preferences に保存
      await RecordingPreferences().setRealtimeTranscribe(value);
    }
  }

  Future<void> addReaction(String momentType) async {
    final lectureId = state.currentLectureId;
    if (lectureId == null) return;
    await _momentRepo.addMoment(
      lectureId: lectureId,
      momentType: momentType,
      timestampSec: state.elapsedSeconds,
    );
    ref.read(lectureControllerProvider.notifier).pushOutboxNow();
  }

  Future<void> addNote(String text) async {
    final lectureId = state.currentLectureId;
    if (lectureId == null) return;
    await _momentRepo.addMoment(
      lectureId: lectureId,
      momentType: 'note',
      noteText: text,
      timestampSec: state.elapsedSeconds,
    );
    ref.read(lectureControllerProvider.notifier).pushOutboxNow();
  }

  Future<void> deleteMoment(String id) async {
    await _momentRepo.deleteMoment(id);
    ref.read(lectureControllerProvider.notifier).pushOutboxNow();
  }

  Future<void> setTitle(String newTitle) async {
    state = state.copyWith(title: newTitle);
    final lecture = state.lecture;
    if (lecture != null) {
      await _repo.updateLectureTitle(
        userId: lecture.userId,
        lectureId: lecture.id,
        title: newTitle,
      );
    }
  }

  Future<void> setCourseId(String? courseId) async {
    state = state.copyWith(
      courseId: courseId,
      forceClearCourseId: courseId == null,
    );
    final lecture = state.lecture;
    if (lecture != null) {
      await _repo.updateLectureCourse(
        userId: lecture.userId,
        lectureId: lecture.id,
        courseId: courseId,
      );
    }
  }

  Future<void> upload() async {
    if (!state.canUpload) return;

    final lecture = state.lecture;
    if (lecture == null) return;

    state = state.copyWith(phase: RecordingPhase.uploading, clearErrorMessage: true);

    try {
      await _audioStreamSub?.cancel();
      await _recorder.stop();
      await ref.read(liveAsrControllerProvider.notifier).stop();
      _timer?.cancel();

      // 1. マスター生PCMデータをAAC (M4A) に圧縮エンコード
      final masterM4aPath = await _recorder.encodeMasterRawToM4a(lecture.id);

      // 2. 最後のチャンクをフラッシュして登録（Realtime Transcribe が On の場合のみ）
      if (state.realtimeTranscribe) {
        final finalFlushed = _chunker?.flush();
        if (finalFlushed != null && finalFlushed.data.isNotEmpty) {
          DevLog.add('[Chunker] Final chunk is ready! Size: ${finalFlushed.data.length} bytes (Start: ${finalFlushed.startTimeSec}s)');

          final path = await _recorder.savePcmAsM4a(finalFlushed.data, lecture.id);

          await _repo.attachAudioAndEnqueueUpload(
            userId: lecture.userId,
            lectureId: lecture.id,
            localPath: path,
            sequenceIndex: _currentChunkIndex,
            startTime: finalFlushed.startTimeSec,
          );
          _currentChunkIndex++;
        }
      } else {
        DevLog.add('[Upload] Realtime Transcribe is OFF, skipping final chunk upload');
        _chunker?.flush(); // メモリ解放のためflushは呼ぶが結果は使わない
      }

      // 3. マスターオーディオのアップロードジョブを登録
      await _repo.enqueueMasterAudioUpload(
        userId: lecture.userId,
        lectureId: lecture.id,
        localPath: masterM4aPath,
      );

      await _repo.finishLectureRecording(
        lectureId: lecture.id,
        expectedChunks: _currentChunkIndex,
      );

      state = state.copyWith(phase: RecordingPhase.queued);
      _uploadMgr.tryProcessQueue();

    } catch (e) {
      state = state.copyWith(
        phase: RecordingPhase.error, 
        errorMessage: 'Save failed: $e'
      );
    }
  }

  Future<void> cancelAndDiscard() async {
    await _audioStreamSub?.cancel();
    await _recorder.stop();
    await ref.read(liveAsrControllerProvider.notifier).stop();
    _timer?.cancel();
    _dbSubscription?.cancel();

    if (state.currentLectureId != null) {
      await _recorder.cleanUpMasterAudioFiles(state.currentLectureId!);
      await _repo.deleteLectureAndAssets(state.currentLectureId!);
    }

    state = RecordingState.idle();
  }

  Future<void> uploadAudioFile(String localFilePath) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'You must be signed in to upload.',
      );
      return;
    }

    if (state.courseId == null) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'Please select a course before uploading.',
      );
      return;
    }

    state = state.copyWith(phase: RecordingPhase.uploading, clearErrorMessage: true);

    try {
      DevLog.add('[UploadAudioFile] 1/4 creating draft lecture...');
      final lectureId = await _repo.createDraftLecture(
        userId: user.id,
        presetCourseId: state.courseId,
        presetTitle: state.title.isNotEmpty ? state.title : null,
        autoStartAnalysis: state.autoStartAnalysis,
        isRealtime: false, // 外部ファイルは常にプレレコ
      );
      DevLog.add('[UploadAudioFile] 2/4 draft lecture created: $lectureId');

      // コースが選択されていればWhisperコンテキストをフェッチして保存
      final courseId = state.courseId;
      if (courseId != null) {
        final context = await _buildWhisperContext(uid: user.id, courseId: courseId);
        if (context.isNotEmpty) {
          await _repo.saveWhisperContext(lectureId: lectureId, whisperContext: context);
        }
      }

      DevLog.add('[UploadAudioFile] 3/4 enqueueing master audio upload...');
      await _repo.enqueueMasterAudioUpload(
        userId: user.id,
        lectureId: lectureId,
        localPath: localFilePath,
      );

      DevLog.add('[UploadAudioFile] 4/4 finishing lecture recording...');
      await _repo.finishLectureRecording(
        lectureId: lectureId,
        expectedChunks: 0, // プレレコなので expectedChunks=0
      );

      state = state.copyWith(phase: RecordingPhase.queued);
      _uploadMgr.tryProcessQueue();

    } catch (e) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'Upload failed: $e'
      );
    }
  }

  Future<void> openSettingsIfNeeded() async {
    await openAppSettings();
  }
}