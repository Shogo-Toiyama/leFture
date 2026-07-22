import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// メインisolate↔ワーカーisolate間でやり取りするメッセージ型。
/// どちらも通常のDartオブジェクト(ネイティブポインタ非保持)なので、
/// isolate間の`SendPort.send`でそのまま送れる。

class VadOfflineIsolateConfig {
  const VadOfflineIsolateConfig({
    required this.recognizerConfig,
    required this.vadModelPath,
    required this.maxSpeechDuration,
    required this.minSilenceDuration,
    required this.minSpeechDuration,
    required this.confirmIntervalDuration,
  });

  final sherpa_onnx.OfflineRecognizerConfig recognizerConfig;
  final String vadModelPath;
  final double maxSpeechDuration;
  final double minSilenceDuration;
  final double minSpeechDuration;

  /// VADの区切りが来ない場合でも、最低これだけの間隔で強制的に1回デコードする
  /// ("マシンガントーク"でも文字起こしが出続けるようにするための保険)。
  final double confirmIntervalDuration;
}

class VadOfflineIsolateReady {
  const VadOfflineIsolateReady();
}

class VadOfflineIsolateDisposeRequest {
  const VadOfflineIsolateDisposeRequest();
}

class VadOfflineIsolateDisposed {
  const VadOfflineIsolateDisposed();
}

/// ワーカーisolateのエントリポイントの型(spawn時の型チェック用)。
typedef VadOfflineIsolateEntry = void Function(SendPort mainSendPort);
