import 'dart:io';
import 'package:record/record.dart';

class AudioRecorderService {
  AudioRecorderService() : _recorder = AudioRecorder();
  final AudioRecorder _recorder;

  Future<bool> isRecording() => _recorder.isRecording();

  Future<void> start({
    required String outputPath,
  }) async {
    // 出力先フォルダが無ければ作る
    final outFile = File(outputPath);
    await outFile.parent.create(recursive: true);

    // record自体にも hasPermission はあるが、
    // アプリ側では permission_handler で統一管理する想定
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: outputPath,
    );
  }

  /// 停止して、保存されたファイルパスを返す（nullなら失敗）
  Future<String?> stop() => _recorder.stop();

  Future<void> dispose() async {
    await _recorder.dispose();
  }
}
