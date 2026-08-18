import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'package:lefture/core/utils/dev_log.dart';

import 'asr_engine.dart';
import 'asr_engine_status.dart';
import 'asr_live_segment.dart';
import 'vad_offline_isolate_messages.dart';
import 'vad_offline_isolate_worker.dart';

/// 共有Whisperモデル向けの[AsrEngine]実装。
///
/// `sherpa_onnx`のVAD/OfflineRecognizerのdecode呼び出しは同期・ブロッキングな
/// FFI呼び出しで、これをメインisolate(=UIスレッド)上で呼ぶと、画面操作
/// (録音停止ボタンが押せない等)やTimer表示が丸ごと固まる不具合が実機で
/// 確認された。そのため実際の認識処理は全てバックグラウンドisolate
/// ([vadOfflineIsolateEntry])の中で行い、このクラスはPCMバイト列の送信と
/// 認識結果[AsrLiveSegment]の受信だけを担う薄いプロキシになっている。
///
/// 確定テキストのデコードは「VADが発話の区切りを検知した時」または
/// 「[confirmIntervalDuration]秒経っても区切りが来ない時」の2つのタイミングで
/// 1回だけ行う。加えて、喋り始めの立ち上がりだけ[warmupCheckpoints]の時点で
/// 暫定テキストを出す(詳細はワーカー側のドキュメントを参照)。
class VadOfflineEngine implements AsrEngine {
  VadOfflineEngine({
    required this.recognizerConfig,
    required this.vadModelPath,
    required this.maxSpeechDuration,
    this.minSilenceDuration = 0.5,
    this.minSpeechDuration = 0.25,
    this.confirmIntervalDuration = 10.0,
    this.warmupCheckpoints = const [1.0, 3.0],
    this.warmupRearmSilenceDuration = 5.0,
    this.initialOffsetSec = 0.0,
  });

  /// Whisperの設定は呼び出し側(AsrEngineFactory)が組み立てる。
  final sherpa_onnx.OfflineRecognizerConfig recognizerConfig;
  final String vadModelPath;
  final double maxSpeechDuration;
  final double minSilenceDuration;
  final double minSpeechDuration;

  /// VADの区切りが来ない場合でも、最低これだけの間隔で強制的に1回デコードする。
  final double confirmIntervalDuration;

  /// 喋り始めてから何秒の時点で暫定テキストを出すか。ウィンドウの区切り方は
  /// 変えないため、確定テキストの品質には影響しない。
  final List<double> warmupCheckpoints;

  /// これだけ無音が続いたら、次の発話でまた[warmupCheckpoints]を使う。
  final double warmupRearmSilenceDuration;

  /// 一時停止→再開のたびに新しいisolateが起動して内部のサンプルカウントが
  /// 0から始まってしまうと、確定テキストのtimestampSecが録音全体の経過時間
  /// より小さくなり、サーバー側watermarkによる表示フィルタで再開後の字幕が
  /// 全て消えてしまう。呼び出し側が把握している経過秒数をここに渡す。
  final double initialOffsetSec;

  Isolate? _isolate;
  ReceivePort? _mainReceivePort;
  StreamSubscription? _portSub;
  SendPort? _workerSendPort;
  Completer<void>? _readyCompleter;
  Completer<void>? _disposedCompleter;
  final _controller = StreamController<AsrLiveSegment>.broadcast();
  final _statusController = StreamController<AsrEngineStatus>.broadcast();

  @override
  Stream<AsrLiveSegment> get segments => _controller.stream;

  @override
  Stream<AsrEngineStatus> get status => _statusController.stream;

  @override
  Future<void> start() async {
    DevLog.add(
      '🎙️ [VadOfflineEngine] start() — spawning background isolate '
      '(vadModelPath="$vadModelPath" maxSpeechDuration=${maxSpeechDuration}s '
      'confirmIntervalDuration=${confirmIntervalDuration}s)',
    );

    final mainReceivePort = ReceivePort();
    _mainReceivePort = mainReceivePort;
    _readyCompleter = Completer<void>();

    _portSub = mainReceivePort.listen(_handleWorkerMessage);
    _isolate = await Isolate.spawn(vadOfflineIsolateEntry, mainReceivePort.sendPort);
    await _readyCompleter!.future;
    DevLog.add('🎙️ [VadOfflineEngine] background isolate ready');
  }

  void _handleWorkerMessage(dynamic message) {
    if (message is SendPort) {
      _workerSendPort = message;
      message.send(
        VadOfflineIsolateConfig(
          recognizerConfig: recognizerConfig,
          vadModelPath: vadModelPath,
          maxSpeechDuration: maxSpeechDuration,
          minSilenceDuration: minSilenceDuration,
          minSpeechDuration: minSpeechDuration,
          confirmIntervalDuration: confirmIntervalDuration,
          warmupCheckpoints: warmupCheckpoints,
          warmupRearmSilenceDuration: warmupRearmSilenceDuration,
          initialOffsetSec: initialOffsetSec,
        ),
      );
    } else if (message is VadOfflineIsolateReady) {
      _readyCompleter?.complete();
    } else if (message is AsrLiveSegment) {
      if (!_controller.isClosed) _controller.add(message);
    } else if (message is VadOfflineIsolateStatus) {
      if (!_statusController.isClosed) {
        _statusController.add(
          AsrEngineStatus(
            speechDetected: message.speechDetected,
            decoding: message.decoding,
            droppedFinalCount: message.droppedFinalCount,
          ),
        );
      }
    } else if (message is VadOfflineIsolateDisposed) {
      _disposedCompleter?.complete();
    }
  }

  @override
  void acceptPcm16(Uint8List bytes) {
    // ワーカーisolateへ送るだけ(処理自体はワーカー側で行われる)。
    // `SendPort.send`は即座にメッセージをキューイングするだけの非ブロッキング
    // 呼び出しなので、ここでUIスレッドが待たされることは無い。
    _workerSendPort?.send(bytes);
  }

  @override
  void setDecodingPaused(bool paused) {
    // ack待ちは不要(境界を跨いだ数百ms程度のズレは実害が無いため)。
    _workerSendPort?.send(VadOfflineIsolateSetPaused(paused));
  }

  @override
  Future<void> dispose() async {
    DevLog.add('🎙️ [VadOfflineEngine] dispose() requested');

    final workerPort = _workerSendPort;
    if (workerPort != null) {
      _disposedCompleter = Completer<void>();
      workerPort.send(const VadOfflineIsolateDisposeRequest());
      try {
        // ワーカー側のVAD/Recognizerの解放を待ってから終了する。何らかの理由で
        // 応答が来なくても無限に待たないよう、安全弁としてタイムアウトを設ける。
        await _disposedCompleter!.future.timeout(const Duration(seconds: 3));
      } catch (e) {
        DevLog.add('⚠️ [VadOfflineEngine] worker did not confirm dispose in time: $e');
      }
    }

    await _portSub?.cancel();
    _mainReceivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    await _controller.close();
    await _statusController.close();
    DevLog.add('🎙️ [VadOfflineEngine] dispose() complete');
  }
}
