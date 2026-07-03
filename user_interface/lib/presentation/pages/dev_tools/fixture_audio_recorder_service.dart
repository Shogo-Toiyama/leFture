// presentation/pages/dev_tools/fixture_audio_recorder_service.dart
//
// デバッグ専用: 実マイクの代わりに、事前に用意したPCMファイル（本番と同じ
// pcm16bits/16kHz/monoのヘッダなしraw音声）を実時間ペースで流し込む
// AudioRecorderService。startStream() だけを差し替え、savePcmAsWav /
// appendMasterRawData / encodeMasterRawToM4a / pause / resume / stop は
// 親クラスのファイルI/O実装をそのまま使う（実機マイクに依存しないため安全）。
//
// AudioChunker はバイト数（BYTES_PER_SEC = 32000 = 16kHz×16bit×mono）で
// チャンクの切れ目を判定しており壁時計時間には依存しないが、Groqのレート
// リミットを避けるため、あえて speedMultiplier=1.0（実時間）でペーシングする。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_background/flutter_background.dart';

import '../../../core/services/audio_record/audio_recorder_service.dart';

class FixtureAudioRecorderService extends AudioRecorderService {
  FixtureAudioRecorderService({
    required this.fixturePcmPath,
    this.speedMultiplier = 1.0,
  });

  /// 本番のマイクストリームと同じ形式（s16le, 16000Hz, mono, ヘッダなし）の
  /// rawファイルへの絶対パス。
  final String fixturePcmPath;

  /// 1.0 = 実時間ペース（デフォルト）。2.0にすると2倍速で流れる。
  final double speedMultiplier;

  static const int _bytesPerSec = 32000; // 16kHz * 16bit(2byte) * mono
  static const int _tickMs = 100; // ~100ms相当ずつemitする
  static final int _bytesPerTick = (_bytesPerSec * _tickMs / 1000).round();

  final Completer<void> _doneCompleter = Completer<void>();
  bool _cancelled = false;
  bool _isBackgroundInitialized = false;

  /// fixtureを最後まで流し終えたら完了する Future。
  Future<void> get done => _doneCompleter.future;

  @override
  Future<Stream<Uint8List>> startStream() async {
    // AudioRecorderService._initBackgroundService() はprivateでサブクラスから
    // 呼べないため、同等のロジックをここに複製する（意図的な重複）。
    // 無効化(disableBackgroundExecution)側は継承したstop()/dispose()が
    // FlutterBackground.isBackgroundExecutionEnabled という静的フラグを見て
    // 処理してくれるため、そちらはオーバーライド不要。
    if (Platform.isAndroid) {
      const androidConfig = FlutterBackgroundAndroidConfig(
        notificationTitle: 'leFture Test Recording',
        notificationText: 'Simulated recording in progress...',
        notificationImportance: AndroidNotificationImportance.normal,
        notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
      );
      _isBackgroundInitialized = await FlutterBackground.initialize(androidConfig: androidConfig);
      if (_isBackgroundInitialized) {
        await FlutterBackground.enableBackgroundExecution();
      }
    }

    final file = File(fixturePcmPath);
    if (!await file.exists()) {
      throw StateError('Fixture PCM file not found at $fixturePcmPath');
    }

    final controller = StreamController<Uint8List>();
    unawaited(_pump(file, controller));
    return controller.stream;
  }

  Future<void> _pump(File file, StreamController<Uint8List> controller) async {
    final raf = await file.open();
    try {
      final tickDelay = Duration(
        milliseconds: (_tickMs / speedMultiplier).round(),
      );

      while (!_cancelled) {
        final bytes = await raf.read(_bytesPerTick);
        if (bytes.isEmpty) break;

        controller.add(Uint8List.fromList(bytes));
        await Future.delayed(tickDelay);
      }
    } catch (e, st) {
      if (!controller.isClosed) controller.addError(e, st);
    } finally {
      await raf.close();
      await controller.close();
      if (!_doneCompleter.isCompleted) _doneCompleter.complete();
    }
  }

  /// 途中で強制終了したい場合（Discardなど）に呼ぶ。
  void cancelPump() {
    _cancelled = true;
  }
}
