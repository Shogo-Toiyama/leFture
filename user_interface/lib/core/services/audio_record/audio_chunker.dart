// core/services/audio_record/audio_chunker.dart

import 'dart:typed_data';

class AudioChunker {
  final BytesBuilder _buffer = BytesBuilder();
  int _silenceBytesCount = 0; 
  
  // デバッグ用：ログの出力頻度を下げるためのカウンター
  int _logCounter = 0;

  final void Function(Uint8List chunkData) onChunkReady;
  AudioChunker({required this.onChunkReady});

  void processAudioStream(Uint8List newData) {
    _buffer.add(newData);
    
    // 1. 今回のデータの「最大音量」を取得する
    int maxAmp = _getMaxAmplitude(newData);
    bool isSilent = maxAmp < 1000; // 1000は実際のログを見て調整してね！

    if (isSilent) {
      _silenceBytesCount += newData.length;
    } else {
      _silenceBytesCount = 0; 
    }

    double currentDurationSec = _buffer.length / 32000.0;
    double silenceDurationSec = _silenceBytesCount / 32000.0;

    // 💡 [デバッグログ] 定期的に現在の状態を出力（大体0.2〜0.5秒に1回出ます）
    _logCounter++;
    if (_logCounter % 10 == 0) {
      // print('[Chunker] ⏱ ${currentDurationSec.toStringAsFixed(1)}s | 🔊 音量: $maxAmp | 🔇 無音: ${silenceDurationSec.toStringAsFixed(1)}s');
    }

    bool shouldCut = false;
    String cutReason = ''; // デバッグ用に理由を保存

    if (currentDurationSec >= 120.0) {
      shouldCut = true; 
      cutReason = '2分強制カット';
    } else if (currentDurationSec >= 90.0 && silenceDurationSec >= 0.2) {
      shouldCut = true; 
      cutReason = '1分半 ＆ 0.2秒無音';
    } else if (currentDurationSec >= 60.0 && silenceDurationSec >= 0.4) {
      shouldCut = true; 
      cutReason = '1分 ＆ 0.4秒無音';
    } else if (currentDurationSec >= 30.0 && silenceDurationSec >= 0.6) {
      shouldCut = true; 
      cutReason = '30秒 ＆ 0.6秒無音';
    }

    if (shouldCut) {
      // 💡 [デバッグログ] カットされた瞬間の理由と時間をドンと出す！
      // print('✂️ [Chunker] カット実行！理由: $cutReason (録音時間: ${currentDurationSec.toStringAsFixed(2)}s)');
      
      final chunkData = _buffer.takeBytes();
      onChunkReady(chunkData);
      
      _silenceBytesCount = 0;
    }
  }

  Uint8List? flush() {
    if (_buffer.isEmpty) return null; 
    
    // 💡 [デバッグログ] Flushが呼ばれたことを確認
    // print('🧹 [Chunker] Flush（絞り出し）実行！(残量: ${(_buffer.length / 32000.0).toStringAsFixed(2)}s)');
    
    final chunkData = _buffer.takeBytes();
    _silenceBytesCount = 0; 
    return chunkData;
  }
}

// 修正版：振幅（最大音量）を計算して返す関数
int _getMaxAmplitude(Uint8List data) {
  int maxAmplitude = 0;
  
  for (int i = 0; i < data.length - 1; i += 2) {
    int sample = (data[i] & 0xFF) | ((data[i + 1] & 0xFF) << 8);
    
    // 【重要】16ビットの符号付き整数（マイナスの波）に変換する処理
    if (sample >= 32768) {
      sample -= 65536; 
    }
    
    int amplitude = sample.abs(); // 絶対値で音の大きさを取る
    if (amplitude > maxAmplitude) {
      maxAmplitude = amplitude;
    }
  }
  return maxAmplitude;
}