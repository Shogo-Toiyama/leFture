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
    required this.warmupCheckpoints,
    required this.warmupRearmSilenceDuration,
    this.initialOffsetSec = 0.0,
  });

  final sherpa_onnx.OfflineRecognizerConfig recognizerConfig;
  final String vadModelPath;
  final double maxSpeechDuration;
  final double minSilenceDuration;
  final double minSpeechDuration;

  /// VADの区切りが来ない場合でも、最低これだけの間隔で強制的に1回デコードする
  /// ("マシンガントーク"でも文字起こしが出続けるようにするための保険)。
  final double confirmIntervalDuration;

  /// このエンジンが今回のセッションで最初に受け取る音声の、録音全体における
  /// 開始位置(秒)。一時停止→再開のたびに新しいisolateが起動して内部の
  /// サンプルカウントが0から始まってしまうと、確定テキストの`timestampSec`が
  /// 録音全体の経過時間より小さくなり、サーバー側watermarkによる表示フィルタ
  /// (`_LiveTranscriptPanel`)で再開後の字幕が全て消える不具合になるため、
  /// 呼び出し側(RecordingController)が把握している経過秒数をここに渡す。
  final double initialOffsetSec;

  /// 「喋り始めてから何秒の時点で暫定テキストを出すか」のチェックポイント。
  /// 例: [1.0, 3.0] なら、発話開始1秒後と3秒後にそこまでの音声を暫定として
  /// デコードし、いつも通り[confirmIntervalDuration]で確定させる。
  /// 空リストにすると立ち上がりバーストは無効。
  final List<double> warmupCheckpoints;

  /// これだけ無音が続いたら、次に喋り始めた時にまた[warmupCheckpoints]を
  /// 使う(＝長い間の後の「ちゃんと聞こえてるよ」を再度出す)。
  final double warmupRearmSilenceDuration;
}

/// ワーカーisolate→メインisolate: 稼働状況の変化通知。値が変わった時だけ
/// 送る(毎フレーム送るとポートが無駄に混む)。
class VadOfflineIsolateStatus {
  const VadOfflineIsolateStatus({
    required this.speechDetected,
    required this.decoding,
    required this.droppedFinalCount,
  });

  final bool speechDetected;
  final bool decoding;
  final int droppedFinalCount;
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
