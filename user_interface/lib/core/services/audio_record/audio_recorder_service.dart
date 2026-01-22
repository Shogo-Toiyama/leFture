import 'dart:io';
import 'package:flutter_background/flutter_background.dart'; // 追加
import 'package:record/record.dart';

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _disposed = false;
  
  // 初期化済みかどうかのフラグ
  bool _isBackgroundInitialized = false;

  Future<void> _initBackgroundService() async {
    if (_isBackgroundInitialized) return;

    // Android向けの通知設定
    const androidConfig = FlutterBackgroundAndroidConfig(
      notificationTitle: 'leFture Recording',
      notificationText: 'Recording in progress...',
      notificationImportance: AndroidNotificationImportance.normal,
      notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'), // アイコン
    );

    // 権限と設定を初期化
    _isBackgroundInitialized = await FlutterBackground.initialize(
      androidConfig: androidConfig,
    );
  }

  Future<void> start({required String outputPath}) async {
    if (_disposed) {
      throw StateError('AudioRecorderService is disposed.');
    }

    // ★録音開始前にバックグラウンド実行を有効化
    if (Platform.isAndroid) {
      await _initBackgroundService();
      // 通知を出してサービス開始
      if (_isBackgroundInitialized) {
        await FlutterBackground.enableBackgroundExecution();
      }
    }

    final f = File(outputPath);
    await f.parent.create(recursive: true);

    const config = RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 48000,
      sampleRate: 24000,
      numChannels: 1,
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

  Future<String?> stop() async {
    if (_disposed) return null;

    final recording = await _recorder.isRecording();
    final paused = await _recorder.isPaused();
    
    // ★録音停止したら、バックグラウンド実行もオフにする（通知を消す）
    if (Platform.isAndroid && FlutterBackground.isBackgroundExecutionEnabled) {
      await FlutterBackground.disableBackgroundExecution();
    }

    if (!recording && !paused) return null;
    return _recorder.stop();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    
    // 念のためdispose時にもオフに
    if (Platform.isAndroid && FlutterBackground.isBackgroundExecutionEnabled) {
      await FlutterBackground.disableBackgroundExecution();
    }
    
    await _recorder.dispose();
  }
}