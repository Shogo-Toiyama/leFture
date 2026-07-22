import 'dart:async';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'package:lecture_companion_ui/core/utils/dev_log.dart';

import 'asr_engine.dart';
import 'asr_live_segment.dart';
import 'pcm_utils.dart';

/// Tier1: 真のストリーミング認識(英語/中国語)。VAD無し、公式の
/// `streaming_asr`サンプルと同じ形(acceptWaveform→decode→isEndpoint→reset)。
/// エンドポイント検知はモデル自体の無音ルール(rule1/2/3MinTrailingSilence)に
/// 任せる — 逐次デコードなので、Tier2/3のようなキュー詰まりの心配は無い。
class StreamingZipformerEngine implements AsrEngine {
  StreamingZipformerEngine({required this.modelDir});

  /// 展開済みモデルディレクトリ(encoder.onnx/decoder.onnx/joiner.onnx/tokens.txt)。
  final String modelDir;

  static const _sampleRate = 16000;

  sherpa_onnx.OnlineRecognizer? _recognizer;
  sherpa_onnx.OnlineStream? _stream;
  final _controller = StreamController<AsrLiveSegment>.broadcast();
  int _samplesFed = 0;
  String _lastEmittedPartial = '';

  @override
  Stream<AsrLiveSegment> get segments => _controller.stream;

  @override
  Future<void> start() async {
    sherpa_onnx.initBindings();

    final encoderPath = p.join(modelDir, 'encoder.onnx');
    final decoderPath = p.join(modelDir, 'decoder.onnx');
    final joinerPath = p.join(modelDir, 'joiner.onnx');
    final tokensPath = p.join(modelDir, 'tokens.txt');
    DevLog.add(
      '🎙️ [StreamingZipformer] start() — encoder="$encoderPath" decoder="$decoderPath" '
      'joiner="$joinerPath" tokens="$tokensPath" sampleRate=$_sampleRate',
    );

    final config = sherpa_onnx.OnlineRecognizerConfig(
      model: sherpa_onnx.OnlineModelConfig(
        transducer: sherpa_onnx.OnlineTransducerModelConfig(
          encoder: encoderPath,
          decoder: decoderPath,
          joiner: joinerPath,
        ),
        tokens: tokensPath,
      ),
      // デフォルト(rule1=2.4s/rule2=1.2s)だと、間を置かず喋り続ける講義で
      // 確定(endpoint)が遅れてリアルタイム感が失われるため、短めに調整する。
      // rule1: 無音のみ(発話が一度も無くても)で確定するまでの閾値。
      // rule2: 一度発話した後、無音が続いて確定するまでの閾値。
      rule1MinTrailingSilence: 1.0,
      rule2MinTrailingSilence: 0.6,
    );

    _recognizer = sherpa_onnx.OnlineRecognizer(config);
    _stream = _recognizer!.createStream();
    DevLog.add('🎙️ [StreamingZipformer] recognizer + stream ready');
  }

  @override
  void acceptPcm16(Uint8List bytes) {
    final recognizer = _recognizer;
    final stream = _stream;
    if (recognizer == null || stream == null) return;

    final samples = convertPcm16ToFloat32(bytes);
    _samplesFed += samples.length;
    stream.acceptWaveform(samples: samples, sampleRate: _sampleRate);

    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }

    // 確定(isEndpoint)前でも、今デコーダが持っている暫定仮説をそのままUIに流す
    // (isFinal: false)。確定するまで同じ行を上書きし続ける想定
    // (LiveAsrController側でマージする)。
    final partialText = recognizer.getResult(stream).text.trim();
    if (partialText.isNotEmpty && partialText != _lastEmittedPartial) {
      _lastEmittedPartial = partialText;
      DevLog.add(
        '👂 [StreamingZipformer] partial (t=${(_samplesFed / _sampleRate).toStringAsFixed(1)}s): "$partialText"',
      );
      _controller.add(
        AsrLiveSegment(text: partialText, timestampSec: _samplesFed / _sampleRate, isFinal: false),
      );
    }

    if (recognizer.isEndpoint(stream)) {
      final text = recognizer.getResult(stream).text.trim();
      DevLog.add(
        '✅ [StreamingZipformer] endpoint (t=${(_samplesFed / _sampleRate).toStringAsFixed(1)}s): '
        '"${text.isEmpty ? "(empty)" : text}"',
      );
      if (text.isNotEmpty) {
        _controller.add(
          AsrLiveSegment(text: text, timestampSec: _samplesFed / _sampleRate, isFinal: true),
        );
      }
      recognizer.reset(stream);
      _lastEmittedPartial = '';
    }
  }

  @override
  Future<void> dispose() async {
    DevLog.add('🎙️ [StreamingZipformer] dispose() — samplesFed=$_samplesFed');
    _stream?.free();
    _recognizer?.free();
    await _controller.close();
  }
}
