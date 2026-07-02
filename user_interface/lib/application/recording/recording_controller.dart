import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:lecture_companion_ui/core/services/audio_record/audio_chunker.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/services/audio_record/audio_recorder_service.dart';
import '../../infrastructure/local_db/repositories/recording_repository_drift.dart';
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
    log('[WhisperContext] Failed to fetch context: $e');
  }

  return parts.join('\n');
}

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
    ref.onDispose(() {
      _dbSubscription?.cancel();
      _timer?.cancel();
    });
    return RecordingState.idle();
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
        final path = await _recorder.savePcmAsWav(flushed.data, state.currentLectureId!);
        
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

  Future<void> _startRecordingSession() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'You must be signed in to record.',
      );
      return;
    }

    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
      Permission.notification,
    ].request();

    if (statuses[Permission.microphone] != PermissionStatus.granted) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'Microphone permission is required.',
      );
      return;
    }

    state = state.copyWith(phase: RecordingPhase.requestingPermission, clearErrorMessage: true);

    try {
      final lectureId = await _repo.createDraftLecture(
        userId: user.id,
        presetCourseId: state.courseId,
        presetTitle: state.title.isNotEmpty ? state.title : null,
      );

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
          log('[Chunker] Chunk $_currentChunkIndex is ready! Size: ${chunkData.length} (Start: ${startTimeSec}s)');
          
          final path = await _recorder.savePcmAsWav(chunkData, lectureId);
          
          await _repo.attachAudioAndEnqueueUpload(
            userId: user.id,
            lectureId: lectureId,
            localPath: path,
            sequenceIndex: _currentChunkIndex,
            startTime: startTimeSec,
          );
          
          _currentChunkIndex++; 
          _uploadMgr.tryProcessQueue();
        },
        onMasterDataReady: (Uint8List masterData) async {
          await _recorder.appendMasterRawData(masterData, lectureId);
        },
      );

      final audioStream = await _recorder.startStream();

      _audioStreamSub = audioStream.listen((data) {
        _chunker!.processAudioStream(data);
      });

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

    if (lecture.title?.isEmpty ?? true) {
      await setTitle('Untitled Lecture'); 
    }

    state = state.copyWith(phase: RecordingPhase.uploading, clearErrorMessage: true);

    try {
      await _audioStreamSub?.cancel();
      await _recorder.stop();
      _timer?.cancel();

      // 1. マスター生PCMデータをAAC (M4A) に圧縮エンコード
      final masterM4aPath = await _recorder.encodeMasterRawToM4a(lecture.id);

      // 2. 最後のチャンクをフラッシュして登録
      final finalFlushed = _chunker?.flush();
      if (finalFlushed != null && finalFlushed.data.isNotEmpty) {
        log('[Chunker] Final chunk is ready! Size: ${finalFlushed.data.length} bytes (Start: ${finalFlushed.startTimeSec}s)');
        
        final path = await _recorder.savePcmAsWav(finalFlushed.data, lecture.id);
        
        await _repo.attachAudioAndEnqueueUpload(
          userId: lecture.userId,
          lectureId: lecture.id,
          localPath: path,
          sequenceIndex: _currentChunkIndex, 
          startTime: finalFlushed.startTimeSec,
        );
        _currentChunkIndex++;
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
    _timer?.cancel();
    _dbSubscription?.cancel();
    
    if (state.currentLectureId != null) {
      await _recorder.cleanUpMasterAudioFiles(state.currentLectureId!);
      await _repo.deleteLectureAndAssets(state.currentLectureId!);
    }
    
    state = RecordingState.idle();
  }

  Future<void> openSettingsIfNeeded() async {
    await openAppSettings();
  }
}