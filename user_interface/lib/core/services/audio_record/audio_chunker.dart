// core/services/audio_record/audio_chunker.dart

import 'dart:typed_data';
import 'dart:math' as math;

class AudioChunker {
  final BytesBuilder _buffer = BytesBuilder();
  int _silenceBytesCount = 0; 
  int _logCounter = 0;

  static const int BYTES_PER_SEC = 32000;
  static const int OVERLAP_BYTES = 2 * BYTES_PER_SEC; // 2秒

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
      int targetLength = _cutPointIndex + OVERLAP_BYTES;
      if (_buffer.length >= targetLength) {
        _extractAndEmitChunk(targetLength);
      }
      return; // 待機中は新たなカット判定はしない
    }

    double currentMainDurationSec = (_buffer.length - _mainChunkStartIndex) / BYTES_PER_SEC;
    double silenceDurationSec = _silenceBytesCount / BYTES_PER_SEC;

    _logCounter++;
    if (_logCounter % 10 == 0) {
      // print('[Chunker] ⏱ メイン長: ${currentMainDurationSec.toStringAsFixed(1)}s | 🔊 音量: $maxAmp | 🔇 無音: ${silenceDurationSec.toStringAsFixed(1)}s');
    }

    bool shouldCut = false;
    String cutReason = ''; 

    if (currentMainDurationSec >= 120.0) {
      shouldCut = true; 
      cutReason = '2分強制カット';
    } else if (currentMainDurationSec >= 90.0 && silenceDurationSec >= 0.3) {
      shouldCut = true; 
      cutReason = '1分半 ＆ 0.3秒無音';
    } else if (currentMainDurationSec >= 60.0 && silenceDurationSec >= 0.6) {
      shouldCut = true; 
      cutReason = '1分 ＆ 0.6秒無音';
    } else if (currentMainDurationSec >= 30.0 && silenceDurationSec >= 1.0) {
      shouldCut = true; 
      cutReason = '30秒 ＆ 1.0秒無音';
    }

    if (shouldCut) {
      // print('✂️ [Chunker] カット判定！あと2秒の尻尾を待ちます。理由: $cutReason');
      _isWaitingForTail = true;
      _cutPointIndex = _buffer.length; 
    }
  }

  void _extractAndEmitChunk(int targetLength) {
    Uint8List allBytes = _buffer.takeBytes();

    int startExtract = math.max(0, _mainChunkStartIndex - OVERLAP_BYTES);
    int endExtract = math.min(targetLength, allBytes.length);

    Uint8List chunk = allBytes.sublist(startExtract, endExtract);
    
    double absoluteStartTimeSec = (_absoluteBufferStartOffset + startExtract) / BYTES_PER_SEC;

    onChunkReady(chunk, absoluteStartTimeSec);

    int keepStart = math.max(0, _cutPointIndex - OVERLAP_BYTES);
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
    
    int startExtract = math.max(0, _mainChunkStartIndex - OVERLAP_BYTES);
    if (startExtract >= allBytes.length) return null;

    Uint8List chunk = allBytes.sublist(startExtract);
    
    double absoluteStartTimeSec = (_absoluteBufferStartOffset + startExtract) / BYTES_PER_SEC;

    _silenceBytesCount = 0;
    _isWaitingForTail = false;
    _mainChunkStartIndex = 0; 
    _absoluteBufferStartOffset = 0;
    
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