// core/services/audio_record/audio_chunker.dart

import 'dart:typed_data';
import 'dart:math' as math;

class AudioChunker {
  final BytesBuilder _buffer = BytesBuilder();
  int _silenceBytesCount = 0; 
  int _logCounter = 0;

  static const int bytesPerSec = 32000;
  static const int overlapBytes = 2 * bytesPerSec; // 2秒

  int _mainChunkStartIndex = 0; 
  bool _isWaitingForTail = false; 
  int _cutPointIndex = 0; 
  int _absoluteBufferStartOffset = 0; // マスター録音の先頭から何バイト目か

  final void Function(Uint8List chunkData, double startTimeSec) onChunkReady;
  
  final void Function(Uint8List masterData)? onMasterDataReady;

  AudioChunker({
    required this.onChunkReady,
    this.onMasterDataReady,
  });

  void processAudioStream(Uint8List newData) {
    if (onMasterDataReady != null) {
      onMasterDataReady!(newData);
    }

    _buffer.add(newData);
    
    int maxAmp = _getMaxAmplitude(newData);
    bool isSilent = maxAmp < 1000; 

    if (isSilent) {
      _silenceBytesCount += newData.length;
    } else {
      _silenceBytesCount = 0; 
    }

    if (_isWaitingForTail) {
      int targetLength = _cutPointIndex + overlapBytes;
      if (_buffer.length >= targetLength) {
        _extractAndEmitChunk(targetLength);
      }
      return; // 待機中は新たなカット判定はしない
    }

    double currentMainDurationSec = (_buffer.length - _mainChunkStartIndex) / bytesPerSec;
    double silenceDurationSec = _silenceBytesCount / bytesPerSec;

    _logCounter++;
    if (_logCounter % 10 == 0) {
      // print('[Chunker] ⏱ メイン長: ${currentMainDurationSec.toStringAsFixed(1)}s | 🔊 音量: $maxAmp | 🔇 無音: ${silenceDurationSec.toStringAsFixed(1)}s');
    }

    bool shouldCut = false;

    if (currentMainDurationSec >= 120.0) {
      shouldCut = true; 
    } else if (currentMainDurationSec >= 90.0 && silenceDurationSec >= 0.3) {
      shouldCut = true; 
    } else if (currentMainDurationSec >= 60.0 && silenceDurationSec >= 0.6) {
      shouldCut = true; 
    } else if (currentMainDurationSec >= 30.0 && silenceDurationSec >= 1.0) {
      shouldCut = true; 
    }

    if (shouldCut) {
      _isWaitingForTail = true;
      _cutPointIndex = _buffer.length; 
    }
  }

  void _extractAndEmitChunk(int targetLength) {
    Uint8List allBytes = _buffer.takeBytes();

    int startExtract = math.max(0, _mainChunkStartIndex - overlapBytes);
    int endExtract = math.min(targetLength, allBytes.length);

    Uint8List chunk = allBytes.sublist(startExtract, endExtract);
    
    double absoluteStartTimeSec = (_absoluteBufferStartOffset + startExtract) / bytesPerSec;

    onChunkReady(chunk, absoluteStartTimeSec);

    int keepStart = math.max(0, _cutPointIndex - overlapBytes);
    Uint8List retainedBytes = allBytes.sublist(keepStart);
    _buffer.add(retainedBytes);

    _absoluteBufferStartOffset += keepStart;
    
    _mainChunkStartIndex = _cutPointIndex - keepStart;
    _isWaitingForTail = false;
    _silenceBytesCount = 0;
  }

  ({Uint8List data, double startTimeSec})? flush() {
    if (_buffer.isEmpty) return null; 
    
    Uint8List allBytes = _buffer.takeBytes();
    
    int startExtract = math.max(0, _mainChunkStartIndex - overlapBytes);
    if (startExtract >= allBytes.length) return null;

    Uint8List chunk = allBytes.sublist(startExtract);
    
    double absoluteStartTimeSec = (_absoluteBufferStartOffset + startExtract) / bytesPerSec;

    _silenceBytesCount = 0;
    _isWaitingForTail = false;
    _mainChunkStartIndex = 0;
    // ★ ここを0にリセットしていたのが一時停止(pause)を挟むたびに録音全体の
    // 絶対時刻の基準が失われるバグの原因だった。flush()は一時停止のたびに
    // 同じAudioChunkerインスタンスに対して呼ばれる(録音開始時に1回しか
    // 生成されないため)。allBytesは(保持分も含めて)すべてこのチャンクとして
    // 消費されバッファには何も残らないので、次にバッファへ積まれるバイトの
    // 絶対位置は「これまでの絶対オフセット + 今回消費した全バイト数」になる
    // (_extractAndEmitChunkの `+= keepStart` と同じ考え方)。
    _absoluteBufferStartOffset += allBytes.length;

    return (data: chunk, startTimeSec: absoluteStartTimeSec);
  }
}

int _getMaxAmplitude(Uint8List data) {
  int maxAmplitude = 0;
  for (int i = 0; i < data.length - 1; i += 2) {
    int sample = (data[i] & 0xFF) | ((data[i + 1] & 0xFF) << 8);
    if (sample >= 32768) {
      sample -= 65536; 
    }
    int amplitude = sample.abs();
    if (amplitude > maxAmplitude) {
      maxAmplitude = amplitude;
    }
  }
  return maxAmplitude;
}