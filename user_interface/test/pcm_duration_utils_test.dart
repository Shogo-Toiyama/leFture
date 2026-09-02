import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/core/services/audio_record/pcm_duration_utils.dart';

void main() {
  group('pcmBytesToDuration', () {
    test('1秒分のバイト数はちょうど1秒になる', () {
      expect(pcmBytesToDuration(kMasterPcmBytesPerSecond), const Duration(seconds: 1));
    });

    test('0バイトはゼロ', () {
      expect(pcmBytesToDuration(0), Duration.zero);
    });

    test('負の値はゼロとして扱う', () {
      expect(pcmBytesToDuration(-100), Duration.zero);
    });

    test('90分ぶんのバイト数(実測値)から正しい長さを算出する', () {
      // 90分 = 5400秒 * 32000 bytes/sec
      final d = pcmBytesToDuration(5400 * kMasterPcmBytesPerSecond);
      expect(d.inSeconds, 5400);
    });
  });

  group('pcmSecondsToByteOffset', () {
    test('0秒は0バイト', () {
      expect(pcmSecondsToByteOffset(0), 0);
    });

    test('負の秒数は0バイトにクランプする', () {
      expect(pcmSecondsToByteOffset(-5), 0);
    });

    test('1秒はbytesPerSecちょうど', () {
      expect(pcmSecondsToByteOffset(1.0), kMasterPcmBytesPerSecond);
    });

    test('16bitサンプル境界(偶数バイト)に必ず揃える', () {
      // 0.00003125秒 * 32000 = 1バイト相当 -> 奇数になるケースを作る
      final offset = pcmSecondsToByteOffset(1.0 + 1 / kMasterPcmBytesPerSecond);
      expect(offset.isEven, isTrue);
    });
  });

  group('computeEncodeProgress', () {
    test('半分処理していれば0.5', () {
      expect(computeEncodeProgress(processedMs: 5000, totalDurationMs: 10000), 0.5);
    });

    test('総尺0はnull(不定進捗)', () {
      expect(computeEncodeProgress(processedMs: 100, totalDurationMs: 0), isNull);
    });

    test('処理量が総尺を超えても1.0にクランプする', () {
      expect(computeEncodeProgress(processedMs: 12000, totalDurationMs: 10000), 1.0);
    });

    test('開始直後(0ms)は0.0', () {
      expect(computeEncodeProgress(processedMs: 0, totalDurationMs: 10000), 0.0);
    });
  });

  group('computeTailStartSec', () {
    test('チャンクが1つも無ければ0.0(録音全体がテール)', () {
      expect(computeTailStartSec(const []), 0.0);
    });

    test('全チャンクにendTimeが揃っていれば、最大endTime-4秒を返す', () {
      expect(computeTailStartSec(const [10.0, 20.0, 30.0]), 26.0);
    });

    test('1件でもendTimeがnullなら諦めてnullを返す(末尾切れ許容へフォールバック)', () {
      expect(computeTailStartSec(const [10.0, null, 30.0]), isNull);
    });

    test('最大endTimeが4秒未満なら0.0にクランプする(負にしない)', () {
      expect(computeTailStartSec(const [1.0]), 0.0);
    });
  });
}
