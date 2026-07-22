import 'dart:typed_data';

/// 16bit PCM(リトルエンディアン, `AudioChunker`が扱うのと同じ形式)を
/// sherpa_onnxが要求する[-1.0, 1.0]のFloat32サンプル列に変換する。
Float32List convertPcm16ToFloat32(Uint8List bytes) {
  final byteData = ByteData.sublistView(bytes);
  final sampleCount = bytes.lengthInBytes ~/ 2;
  final samples = Float32List(sampleCount);
  for (var i = 0; i < sampleCount; i++) {
    final int16 = byteData.getInt16(i * 2, Endian.little);
    samples[i] = int16 / 32768.0;
  }
  return samples;
}
