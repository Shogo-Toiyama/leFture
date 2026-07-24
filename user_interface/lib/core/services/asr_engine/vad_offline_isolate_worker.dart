import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'package:lecture_companion_ui/core/utils/dev_log.dart';

import 'asr_live_segment.dart';
import 'pcm_utils.dart';
import 'vad_offline_isolate_messages.dart';

/// [VadOfflineEngine]用のバックグラウンドisolateエントリポイント。
/// `sherpa_onnx`のVAD/OfflineRecognizerのdecode呼び出しはブロッキングな同期FFI
/// 呼び出しであり、メインisolate(=UIスレッド)上で呼ぶと画面操作やタイマーが
/// 丸ごと固まってしまう。この関数はメインisolateから`Isolate.spawn`で起動され、
/// 認識処理は全てこの中(専用isolate)だけで完結させる。メインisolateとは
/// PCMバイト列の送信と[AsrLiveSegment]の受信だけをやり取りする。
void vadOfflineIsolateEntry(SendPort mainSendPort) {
  final workerReceivePort = ReceivePort();
  // まずワーカー側の受信ポートをメインへ渡す(以降、mainSendPortはワーカーから
  // メインへの一方向送信に使い続ける — 新たなポート交換は不要)。
  mainSendPort.send(workerReceivePort.sendPort);

  _VadOfflineRecognitionLogic? logic;

  workerReceivePort.listen((dynamic message) async {
    if (message is VadOfflineIsolateConfig) {
      logic = _VadOfflineRecognitionLogic(
        recognizerConfig: message.recognizerConfig,
        vadModelPath: message.vadModelPath,
        maxSpeechDuration: message.maxSpeechDuration,
        minSilenceDuration: message.minSilenceDuration,
        minSpeechDuration: message.minSpeechDuration,
        confirmIntervalDuration: message.confirmIntervalDuration,
        initialOffsetSec: message.initialOffsetSec,
        onSegment: (segment) => mainSendPort.send(segment),
      );
      await logic!.start();
      mainSendPort.send(const VadOfflineIsolateReady());
    } else if (message is Uint8List) {
      logic?.acceptPcm16(message);
    } else if (message is VadOfflineIsolateSetPaused) {
      logic?.setPaused(message.paused);
    } else if (message is VadOfflineIsolateDisposeRequest) {
      await logic?.dispose();
      mainSendPort.send(const VadOfflineIsolateDisposed());
      workerReceivePort.close();
    }
  });
}

/// デコード待ちの1チャンク分。
typedef _PendingChunk = ({Float32List samples, double timestampSec});

/// Tier2(SenseVoice)/Tier3(Whisper)共通の認識ロジック。ワーカーisolate内でのみ
/// 使う(メインisolateからは触らない)。
///
/// 前回(プレビューを0.4秒おきに再デコードする方式)は、実機のCPUが録音の
/// リアルタイム速度に追いつけず、確定処理のキューが無限に溜まっていく問題が
/// 出た(録音を止めても何分も文字起こしが終わらない)。今回はそれをやめて、
/// デコードを次の2つのタイミングでそれぞれ1回だけ行うだけの、最も軽い方式にする:
///
/// 1. VADが発話の区切り(無音)を検知した時
/// 2. 区切りが来ないまま[confirmIntervalDuration]秒経った時("マシンガントーク"の保険)
///
/// それ以外の時間は音声を溜めるだけで、CPUを使う処理は一切行わない。
/// VADのpop()が返す`segment.samples`はデコードに使わない(自前で溜めた
/// バッファと内容が重複するため)。pop()は「発話が区切られた」という合図
/// としてだけ使う。
class _VadOfflineRecognitionLogic {
  _VadOfflineRecognitionLogic({
    required this.recognizerConfig,
    required this.vadModelPath,
    required this.maxSpeechDuration,
    required this.minSilenceDuration,
    required this.minSpeechDuration,
    required this.confirmIntervalDuration,
    required this.onSegment,
    this.initialOffsetSec = 0.0,
  });

  final sherpa_onnx.OfflineRecognizerConfig recognizerConfig;
  final String vadModelPath;
  final double maxSpeechDuration;
  final double minSilenceDuration;
  final double minSpeechDuration;
  final double confirmIntervalDuration;
  final double initialOffsetSec;
  final void Function(AsrLiveSegment segment) onSegment;

  static const _sampleRate = 16000;

  // デコードが実時間に追いつかず溜まってしまった場合、これを超えて古い分は
  // 諦めて間引く(取りこぼすリスクより、録音を止めてもずっと文字起こしが
  // 終わらない状態の方が実害が大きいため)。
  static const _maxPendingChunks = 2;

  sherpa_onnx.OfflineRecognizer? _recognizer;
  sherpa_onnx.VoiceActivityDetector? _vad;

  // まだデコードしていない生サンプル(発話中かどうかに関わらず常に溜める)。
  final List<Float32List> _pendingSamples = [];
  int _pendingSampleCount = 0;
  // 現在の_pendingSamplesの先頭が、録音開始から何サンプル目かを覚えておく
  // (確定テキストのtimestampSecに使う)。
  int _pendingStartSample = 0;
  int _totalSamplesFed = 0;

  // デコード処理は必ず順番通りに処理する(確定テキストの前後関係が崩れないように)。
  final Queue<_PendingChunk> _decodeQueue = Queue();
  bool _isDecoding = false;

  // Liveタブが非表示/アプリがバックグラウンドの間はtrueになる。この間は
  // VAD推論・バッファリング・デコードを一切行わず、サンプルカウント
  // (タイムスタンプの基準)だけを進める。
  bool _paused = false;

  Future<void> start() async {
    sherpa_onnx.initBindings();

    DevLog.add(
      '🎙️ [VadOfflineEngine/worker] start() — vadModelPath="$vadModelPath" '
      'maxSpeechDuration=${maxSpeechDuration}s minSilenceDuration=${minSilenceDuration}s '
      'minSpeechDuration=${minSpeechDuration}s confirmIntervalDuration=${confirmIntervalDuration}s',
    );

    final initialSamples = (initialOffsetSec * _sampleRate).round();
    _totalSamplesFed = initialSamples;
    _pendingStartSample = initialSamples;

    _recognizer = sherpa_onnx.OfflineRecognizer(recognizerConfig);
    _vad = sherpa_onnx.VoiceActivityDetector(
      config: sherpa_onnx.VadModelConfig(
        sileroVad: sherpa_onnx.SileroVadModelConfig(
          model: vadModelPath,
          minSilenceDuration: minSilenceDuration,
          minSpeechDuration: minSpeechDuration,
          maxSpeechDuration: maxSpeechDuration,
        ),
        sampleRate: _sampleRate,
      ),
      // 30秒分のリングバッファ。maxSpeechDurationより十分大きくしておく。
      bufferSizeInSeconds: 30,
    );
    DevLog.add('🎙️ [VadOfflineEngine/worker] recognizer + VAD ready');
  }

  /// Liveタブの表示状態/アプリのフォアグラウンド状態が変わった際に呼ばれる。
  /// 一時停止に入る瞬間は、直前までユーザーが実際に見ていた区間の音声を
  /// 巻き込んで捨ててしまわないよう、まず溜まっている分を通常通りflushして
  /// からフラグを立てる。再開時は特別な処理は不要(次のacceptPcm16から
  /// 通常の蓄積/flushが自然に再開する)。SileroVADの内部状態が一時停止で
  /// 不連続になることによる誤検出を避けるため、再開時にVADをリセットする。
  void setPaused(bool paused) {
    if (_paused == paused) return;
    if (paused) {
      _flushPending();
    } else {
      _vad?.reset();
    }
    _paused = paused;
    DevLog.add('⏸️ [VadOfflineEngine/worker] setPaused($paused)');
  }

  void acceptPcm16(Uint8List bytes) {
    final vad = _vad;
    if (vad == null) return;

    final samples = convertPcm16ToFloat32(bytes);

    if (_paused) {
      // VAD推論・バッファリング・デコードは一切行わない。タイムスタンプが
      // 実時間からズレないよう、サンプルカウントの歩みだけは進め続ける。
      _totalSamplesFed += samples.length;
      _pendingStartSample = _totalSamplesFed;
      return;
    }

    vad.acceptWaveform(samples);
    _totalSamplesFed += samples.length;

    _pendingSamples.add(samples);
    _pendingSampleCount += samples.length;

    var vadConfirmed = false;
    while (!vad.isEmpty()) {
      final segment = vad.front();
      vad.pop();
      // segment.samplesはデコードに使わない(自前バッファと重複するため)。
      // pop()は「発話が区切られた」という合図としてだけ使う。
      DevLog.add(
        '👂 [VadOfflineEngine/worker] VAD segment confirmed: start=${(segment.start / _sampleRate).toStringAsFixed(1)}s',
      );
      vadConfirmed = true;
    }

    final confirmIntervalSamples = (confirmIntervalDuration * _sampleRate).round();
    final reachedCeiling = _pendingSampleCount >= confirmIntervalSamples;

    if (vadConfirmed || reachedCeiling) {
      if (!vadConfirmed && reachedCeiling) {
        DevLog.add(
          '⏱️ [VadOfflineEngine/worker] no VAD pause within ${confirmIntervalDuration}s — flushing anyway',
        );
      }
      _flushPending();
    }
  }

  void _flushPending() {
    if (_pendingSamples.isEmpty) return;

    final snapshot = _concat(_pendingSamples);
    final timestampSec = _pendingStartSample / _sampleRate;
    _pendingSamples.clear();
    _pendingSampleCount = 0;
    _pendingStartSample = _totalSamplesFed;

    _decodeQueue.add((samples: snapshot, timestampSec: timestampSec));
    unawaited(_processDecodeQueue());
  }

  Future<void> _processDecodeQueue() async {
    if (_isDecoding) return;
    _isDecoding = true;
    try {
      final recognizer = _recognizer;
      if (recognizer == null) return;

      while (_decodeQueue.isNotEmpty) {
        while (_decodeQueue.length > _maxPendingChunks) {
          _decodeQueue.removeFirst();
          DevLog.add(
            '⚠️ [VadOfflineEngine/worker] falling behind live audio — dropping a stale pending chunk',
          );
        }

        final job = _decodeQueue.removeFirst();
        final stream = recognizer.createStream();
        stream.acceptWaveform(samples: job.samples, sampleRate: _sampleRate);
        recognizer.decode(stream);
        final text = recognizer.getResult(stream).text.trim();
        stream.free();

        DevLog.add(
          '✅ [VadOfflineEngine/worker] decode result (t=${job.timestampSec.toStringAsFixed(1)}s): '
          '"${text.isEmpty ? "(empty)" : text}"',
        );
        if (text.isNotEmpty) {
          onSegment(AsrLiveSegment(text: text, timestampSec: job.timestampSec, isFinal: true));
        }
      }
    } catch (e, st) {
      DevLog.add('🚨 [VadOfflineEngine/worker] decode failed: $e\n$st');
    } finally {
      _isDecoding = false;
    }
  }

  Float32List _concat(List<Float32List> chunks) {
    var total = 0;
    for (final c in chunks) {
      total += c.length;
    }
    final merged = Float32List(total);
    var offset = 0;
    for (final c in chunks) {
      merged.setAll(offset, c);
      offset += c.length;
    }
    return merged;
  }

  Future<void> dispose() async {
    DevLog.add('🎙️ [VadOfflineEngine/worker] dispose()');
    _vad?.free();
    _recognizer?.free();
  }
}
