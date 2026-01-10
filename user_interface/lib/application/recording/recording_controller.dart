import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/audio_record/audio_recorder_service.dart';
import '../../core/services/audio_record/pending_upload_store.dart';
import '../../infrastructure/supabase/services/storage_upload_service.dart';
import 'recording_state.dart';

part 'recording_controller.g.dart';

@riverpod
AudioRecorderService audioRecorderService(Ref ref) {
  final svc = AudioRecorderService();
  ref.onDispose(svc.dispose);
  return svc;
}

@riverpod
PendingUploadStore pendingUploadStore(Ref ref) {
  return PendingUploadStore();
}

@riverpod
StorageUploadService storageUploadService(Ref ref) {
  return StorageUploadService(Supabase.instance.client);
}

@riverpod
class RecordingController extends _$RecordingController {
  Timer? _timer;

  AudioRecorderService get _recorder => ref.read(audioRecorderServiceProvider);
  StorageUploadService get _uploader => ref.read(storageUploadServiceProvider);
  PendingUploadStore get _store => ref.read(pendingUploadStoreProvider);

  @override
  RecordingState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    return RecordingState.idle();
  }

  Future<void> start({String? lectureId}) async {
    final lectureId = const Uuid().v4();

    state = state.copyWith(
      phase: RecordingPhase.requestingPermission,
      elapsedSeconds: 0,
      lectureId: lectureId,
      errorMessage: null,
      localPath: null,
      remotePath: null,
    );

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      final msg = mic.isPermanentlyDenied
          ? 'Microphone permission is permanently denied. Please enable it in Settings.'
          : 'Microphone permission is required to record.';
      state = state.copyWith(phase: RecordingPhase.error, errorMessage: msg);
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final fileName = '${const Uuid().v4()}.m4a';
    final outPath = p.join(dir.path, 'recordings', fileName);

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

  Future<void> stopAndUpload() async {
    final lectureId = state.lectureId;
    if (lectureId == null) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'Internal error: lectureId is missing.',
      );
      return;
    }

    if (state.phase != RecordingPhase.recording) return;

    state = state.copyWith(phase: RecordingPhase.stopping);

    _timer?.cancel();
    _timer = null;

    final path = await _recorder.stop();
    if (path == null) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        errorMessage: 'Failed to stop recording.',
      );
      return;
    }

    state = state.copyWith(phase: RecordingPhase.uploading, localPath: path);

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      await _enqueue(userId: 'anonymous', lectureId: lectureId, localPath: path);
      state = state.copyWith(phase: RecordingPhase.queued);
      return;
    }

    final fileName = p.basename(path);

    try {
      final fullPath = await _uploader.uploadAudioFile(
        userId: user.id,
        lectureId: lectureId,
        localPath: path,
        fileName: fileName,
      );

      state = state.copyWith(
        phase: RecordingPhase.uploaded,
        remotePath: fullPath,
      );
    } catch (_) {
      await _enqueue(userId: user.id, lectureId: lectureId, localPath: path);
      state = state.copyWith(
        phase: RecordingPhase.queued,
        errorMessage: 'Upload failed, will retry when online.',
      );
    }
  }


  Future<void> openSettingsIfNeeded() async {
    await openAppSettings();
  }

  Future<void> _enqueue({
    required String userId,
    required String lectureId,
    required String localPath,
  }) async {
    final job = PendingUploadJob(
      id: const Uuid().v4(),
      userId: userId,
      lectureId: lectureId,
      localPath: localPath,
      fileName: p.basename(localPath),
      createdAtIso: DateTime.now().toIso8601String(),
    );
    await _store.add(job);
  }
}
