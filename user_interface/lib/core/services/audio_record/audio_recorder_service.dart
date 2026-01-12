import 'dart:io';
import 'package:record/record.dart';

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _disposed = false;

  Future<void> start({required String outputPath}) async {
    if (_disposed) {
      throw StateError('AudioRecorderService is disposed.');
    }

    // Ensure parent dir exists
    final f = File(outputPath);
    await f.parent.create(recursive: true);

    const config = RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 96000,
      sampleRate: 44100,
    );

    await _recorder.start(config, path: outputPath);
  }

  Future<void> pause() async {
    if (_disposed) return;
    if (await _recorder.isRecording()) {
      await _recorder.pause();
    }
  }

  Future<void> resume() async {
    if (_disposed) return;
    if (await _recorder.isPaused()) {
      await _recorder.resume();
    }
  }

  /// Finalize file. (pausedでもrecordingでもOK)
  Future<String?> stop() async {
    if (_disposed) return null;

    final recording = await _recorder.isRecording();
    final paused = await _recorder.isPaused();
    if (!recording && !paused) return null;

    return _recorder.stop();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _recorder.dispose();
  }
}
