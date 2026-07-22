import 'dart:async';
import 'dart:collection';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'asr_engine.dart';
import 'asr_live_segment.dart';
import 'pcm_utils.dart';

/// Tier2(SenseVoice)/Tier3(Whisper)共通の実装。どちらも非ストリーミング
/// (一発勝負)の認識モデルなので、Silero VADで発話区切りを検知し、区切られた
/// セグメントだけをオフライン認識にかける。
///
/// 講義中は無音が長く続かない("マシンガントーク")ことがあるため、
/// [maxSpeechDuration]を安全側(短め)にしてセグメントが際限なく伸びるのを防ぐ。
/// さらに、認識が音声に追いつかず未処理セグメントが溜まった場合は
/// [maxPendingSegments]を超えた古いものから間引き、遅延が拡大し続けるのを防ぐ
/// (「リアルタイムなのに処理が追いつかなくなる」ことが最も避けたい事態のため)。
class VadOfflineEngine implements AsrEngine {
  VadOfflineEngine({
    required this.recognizerConfig,
    required this.vadModelPath,
    required this.maxSpeechDuration,
    this.minSilenceDuration = 0.5,
    this.minSpeechDuration = 0.25,
    this.maxPendingSegments = 2,
  });

  /// SenseVoice/Whisperどちらの設定を積むかは呼び出し側(AsrEngineFactory)が決める。
  final sherpa_onnx.OfflineRecognizerConfig recognizerConfig;
  final String vadModelPath;
  final double maxSpeechDuration;
  final double minSilenceDuration;
  final double minSpeechDuration;
  final int maxPendingSegments;

  static const _sampleRate = 16000;

  sherpa_onnx.OfflineRecognizer? _recognizer;
  sherpa_onnx.VoiceActivityDetector? _vad;
  final _controller = StreamController<AsrLiveSegment>.broadcast();
  final Queue<({Float32List samples, double timestampSec})> _pending = Queue();
  bool _isProcessing = false;

  @override
  Stream<AsrLiveSegment> get segments => _controller.stream;

  @override
  Future<void> start() async {
    sherpa_onnx.initBindings();

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
  }

  @override
  void acceptPcm16(Uint8List bytes) {
    final vad = _vad;
    if (vad == null) return;

    final samples = convertPcm16ToFloat32(bytes);
    vad.acceptWaveform(samples);

    while (!vad.isEmpty()) {
      final segment = vad.front();
      vad.pop();
      // segment.startはVAD開始(=録音開始)からのサンプルオフセットなので、
      // そのまま経過秒に変換できる。
      _enqueue(segment.samples, segment.start / _sampleRate);
    }
  }

  void _enqueue(Float32List samples, double timestampSec) {
    _pending.add((samples: samples, timestampSec: timestampSec));
    while (_pending.length > maxPendingSegments) {
      _pending.removeFirst();
      dev.log('⚠️ [VadOfflineEngine] Dropping stale segment — falling behind live audio');
    }
    unawaited(_processQueueIfIdle());
  }

  Future<void> _processQueueIfIdle() async {
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      final recognizer = _recognizer;
      if (recognizer == null) return;
      while (_pending.isNotEmpty) {
        final item = _pending.removeFirst();
        final stream = recognizer.createStream();
        stream.acceptWaveform(samples: item.samples, sampleRate: _sampleRate);
        recognizer.decode(stream);
        final text = recognizer.getResult(stream).text.trim();
        stream.free();
        if (text.isNotEmpty) {
          _controller.add(AsrLiveSegment(text: text, timestampSec: item.timestampSec));
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  @override
  Future<void> dispose() async {
    _vad?.free();
    _recognizer?.free();
    await _controller.close();
  }
}
