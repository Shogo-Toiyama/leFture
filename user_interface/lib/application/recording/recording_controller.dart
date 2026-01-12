import 'dart:async';
import 'dart:io';

import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/audio_record/audio_recorder_service.dart';
import '../../core/services/audio_record/pending_upload_store.dart';
import '../../infrastructure/supabase/services/lecture_write_service.dart';
import '../../infrastructure/supabase/services/storage_upload_service.dart';
import 'recording_state.dart';
import 'upload_manager.dart';
import 'dart:developer' as dev;

part 'recording_controller.g.dart';

@Riverpod(keepAlive: true)
AudioRecorderService audioRecorderService(Ref ref) {
  final svc = AudioRecorderService();
  ref.onDispose(svc.dispose);
  return svc;
}

@Riverpod(keepAlive: true)
PendingUploadStore pendingUploadStore(Ref ref) => PendingUploadStore();

@Riverpod(keepAlive: true)
StorageUploadService storageUploadService(Ref ref) => StorageUploadService(supabase);

@Riverpod(keepAlive: true)
LectureWriteService lectureWriteService(Ref ref) => LectureWriteService(supabase);

@Riverpod(keepAlive: true)
UploadManager uploadManager(Ref ref) {
  final mgr = UploadManager(
    store: ref.read(pendingUploadStoreProvider),
    uploader: ref.read(storageUploadServiceProvider),
    lectureWriter: ref.read(lectureWriteServiceProvider),
  );
  ref.onDispose(mgr.dispose);
  return mgr;
}

@Riverpod(keepAlive: true)
class RecordingController extends _$RecordingController {
  Timer? _timer;
  Timer? _metadataDebounce;

  AudioRecorderService get _recorder => ref.read(audioRecorderServiceProvider);
  StorageUploadService get _uploader => ref.read(storageUploadServiceProvider);
  PendingUploadStore get _store => ref.read(pendingUploadStoreProvider);
  LectureWriteService get _lectureWriter => ref.read(lectureWriteServiceProvider);
  UploadManager get _uploadMgr => ref.read(uploadManagerProvider);

  @override
  RecordingState build() {
    ref.onDispose(() {
      stdout.writeln('[Controller] DISPOSED! (Timer cancelled)');
      _timer?.cancel();
      _timer = null;
      _metadataDebounce?.cancel();
      _metadataDebounce = null;
    });

    return RecordingState.idle(
      lectureId: const Uuid().v4(),
      assetId: const Uuid().v4(),
      title: '',
      folderId: null,
    );
  }

  void newDraft({String? folderId}) {
    state = RecordingState.idle(
      lectureId: const Uuid().v4(),
      assetId: const Uuid().v4(),
      title: '',
      folderId: folderId,
    );
  }

  void setTitle(String v) {
    state = state.copyWith(title: v, clearMetadataWarning: true);
    if (state.phase == RecordingPhase.idle) return;
    _scheduleMetadataSync();
  }

  void setFolderId(String? folderId) {
    state = state.copyWith(
      folderId: folderId, 
      setFolderIdToNull: folderId == null, 
      clearMetadataWarning: true
    );
    if (state.phase == RecordingPhase.idle) return;
    _scheduleMetadataSync();
  }

  void _scheduleMetadataSync() {
    _metadataDebounce?.cancel();
    _metadataDebounce = Timer(const Duration(milliseconds: 600), () async {
      await _syncLectureMetadataBestEffort();
    });
  }

  Future<void> _syncLectureMetadataBestEffort() async {
    final user = supabase.auth.currentUser;
    final lectureId = state.lectureId;
    if (user == null || lectureId == null) return;

    try {
      await _lectureWriter.upsertLecture(
        lectureId: lectureId,
        ownerId: user.id,
        folderId: state.folderId,
        title: state.title,
        lectureDateTimeUtc: DateTime.now().toUtc(),
      );
    } on PostgrestException catch (e) {
      dev.log('Lecture upsert failed: ${e.message} code=${e.code} details=${e.details}');
      state = state.copyWith(
        metadataWarning: 'Metadata sync failed: ${e.message}',
      );
    } catch (e) {
      dev.log('Lecture upsert failed: $e');
      state = state.copyWith(
        metadataWarning: 'Metadata sync failed (will retry).',
      );
    }
  }

  Future<void> toggleStartStopResume() async {
    // idle → start
    if (state.phase == RecordingPhase.idle) {
      await _startInternal();
      return;
    }

    // recording → pause
    if (state.phase == RecordingPhase.recording) {
      await _pauseInternal();
      return;
    }

    // paused → resume
    if (state.phase == RecordingPhase.paused) {
      await _resumeInternal();
      return;
    }
  }

  Future<void> _startInternal() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'You must be signed in to record.',
      );
      return;
    }

    final lectureId = state.lectureId ?? const Uuid().v4();
    final assetId = state.assetId ?? const Uuid().v4();

    state = state.copyWith(
      phase: RecordingPhase.requestingPermission,
      lectureId: lectureId,
      assetId: assetId,
      elapsedSeconds: 0,
      clearErrorMessage: true,
    );

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      final msg = mic.isPermanentlyDenied
          ? 'Microphone permission is permanently denied. Please enable it in Settings.'
          : 'Microphone permission is required to record.';
      state = state.copyWith(phase: RecordingPhase.error, errorMessage: msg);
      return;
    }

    // Start時点で lectures を upsert（backend都合が良い）
    await _syncLectureMetadataBestEffort();

    final dir = await getApplicationDocumentsDirectory();
    final outPath = p.join(
      dir.path,
      'recordings',
      lectureId,
      'audio',
      '$assetId.m4a',
    );

    await Directory(p.dirname(outPath)).create(recursive: true);
    await _recorder.start(outputPath: outPath);

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
    });

    state = state.copyWith(
      phase: RecordingPhase.recording,
      localPath: outPath,
    );
  }

  Future<void> _pauseInternal() async {
    if (state.phase != RecordingPhase.recording) return;

    await _recorder.pause();
    _timer?.cancel();
    _timer = null;

    state = state.copyWith(phase: RecordingPhase.paused);
  }

  Future<void> _resumeInternal() async {
    if (state.phase != RecordingPhase.paused) return;

    await _recorder.resume();

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      stdout.writeln('[Timer] Tick: ${state.elapsedSeconds + 1} (Phase: ${state.phase})');
      state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
    });

    state = state.copyWith(phase: RecordingPhase.recording);
  }

  /// Uploadボタン（paused の時だけ有効）
  Future<void> upload() async {
    if (!state.canUpload) return;

    final user = supabase.auth.currentUser;
    final lectureId = state.lectureId;
    final assetId = state.assetId;
    final localPath = state.localPath;

    if (user == null || lectureId == null || assetId == null || localPath == null) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'Internal error: missing ids or local path.',
      );
      return;
    }

    state = state.copyWith(phase: RecordingPhase.uploading, clearErrorMessage: true);

    // 念のため metadata を反映（title/folder変更の最後）
    await _syncLectureMetadataBestEffort();

    // paused中の録音を finalize
    final finalizedPath = await _recorder.stop();
    if (finalizedPath == null) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'Failed to finalize recording.',
      );
      return;
    }

    final fileName = '$assetId.m4a';

    try {
      final remotePath = await _uploader.uploadAudioFile(
        userId: user.id,
        lectureId: lectureId,
        localPath: finalizedPath,
        fileName: fileName,
      );

      // Upload成功 → lecture_assets を作る（backendが拾いやすい）
      await _lectureWriter.upsertAudioAsset(
        assetId: assetId,
        lectureId: lectureId,
        ownerId: user.id,
        bucket: _uploader.audioBucket,
        path: remotePath,
      );

      state = state.copyWith(
        phase: RecordingPhase.uploaded,
        localPath: finalizedPath,
        remotePath: remotePath,
      );
    } catch (_) {
      // 失敗 → キューに積む（assetIdをjob.idとして使う）
      final job = PendingUploadJob(
        id: assetId,
        userId: user.id,
        lectureId: lectureId,
        localPath: finalizedPath,
        fileName: fileName,
        createdAtIso: DateTime.now().toUtc().toIso8601String(),
      );
      await _store.add(job);

      // オンラインなら即処理も試す
      _uploadMgr.tryProcessQueue();

      state = state.copyWith(
        phase: RecordingPhase.queued,
        errorMessage: 'Upload failed, will retry when online.',
      );
    }
  }

  Future<void> cancelAndDiscard() async {
    // 録音中なら止める
    if (state.isRecording || state.isPaused) {
      await _recorder.stop();
      _timer?.cancel();
    }

    final localPath = state.localPath;
    final lectureId = state.lectureId;
    final user = supabase.auth.currentUser;

    // 1. ローカルファイルの削除
    if (localPath != null) {
      final file = File(localPath);
      if (await file.exists()) {
        await file.delete();
      }
    }

    // 2. Supabase上のデータを論理削除 (is_deleted = true)
    if (user != null && lectureId != null) {
      try {
        await _lectureWriter.upsertLecture(
          lectureId: lectureId,
          ownerId: user.id,
          isDeleted: true, // ★ここで削除フラグを立てる
        );
      } catch (e) {
        // 削除リクエスト失敗はログに出す程度で、ユーザーフローは止めない
        dev.log('Failed to mark lecture as deleted: $e');
      }
    }

    // 3. 状態をアイドルに戻す（UI側で pop するので必須ではないが安全のため）
    state = RecordingState.idle();
  }

  Future<void> openSettingsIfNeeded() async {
    await openAppSettings();
  }
}
