import 'dart:async';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

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

  @override
  Stream<AsrLiveSegment> get segments => _controller.stream;

  @override
  Future<void> start() async {
    sherpa_onnx.initBindings();

    final config = sherpa_onnx.OnlineRecognizerConfig(
      model: sherpa_onnx.OnlineModelConfig(
        transducer: sherpa_onnx.OnlineTransducerModelConfig(
          encoder: p.join(modelDir, 'encoder.onnx'),
          decoder: p.join(modelDir, 'decoder.onnx'),
          joiner: p.join(modelDir, 'joiner.onnx'),
        ),
        tokens: p.join(modelDir, 'tokens.txt'),
      ),
    );

    _recognizer = sherpa_onnx.OnlineRecognizer(config);
    _stream = _recognizer!.createStream();
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

    if (recognizer.isEndpoint(stream)) {
      final text = recognizer.getResult(stream).text.trim();
      if (text.isNotEmpty) {
        _controller.add(AsrLiveSegment(text: text, timestampSec: _samplesFed / _sampleRate));
      }
      recognizer.reset(stream);
    }
  }

  @override
  Future<void> dispose() async {
    _stream?.free();
    _recognizer?.free();
    await _controller.close();
  }
}
