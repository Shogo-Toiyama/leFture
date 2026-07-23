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

/// メインisolate→ワーカーisolate: デコード処理の一時停止/再開を指示する。
/// 一時停止中もサンプルカウント(タイムスタンプの基準)は進め続けるが、
/// VAD/デコードの実処理はスキップする(Liveタブが非表示/アプリが
/// バックグラウンドの間、電力消費を抑えるため)。
class VadOfflineIsolateSetPaused {
  const VadOfflineIsolateSetPaused(this.paused);
  final bool paused;
}

/// ワーカーisolateのエントリポイントの型(spawn時の型チェック用)。
typedef VadOfflineIsolateEntry = void Function(SendPort mainSendPort);
