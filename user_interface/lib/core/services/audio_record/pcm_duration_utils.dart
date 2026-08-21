// lib/core/services/audio_record/pcm_duration_utils.dart
//
// master_audio.raw(16kHz, 16bit signed little-endian, mono の生PCM)は
// ヘッダを持たないため、長さ・オフセットは全てバイト数の算術だけで厳密に
// 決まる。Recording Recoveryが必要とする「進捗率」「テールの切り出し位置」の
// 計算をここに切り出し、ファイルI/O・FFmpegから独立してテストできるようにする。
//
// AudioChunker.bytesPerSec/overlapBytesと同じ前提(16kHz * 16bit * mono)を
// 共有しているが、依存を増やさないためここでは定数として持つ。

/// 1秒あたりのバイト数(16kHz * 16bit(2byte) * mono)。AudioChunker.bytesPerSecと同値。
const int kMasterPcmBytesPerSecond = 32000;

/// チャンク間のオーバーラップ秒(AudioChunker.overlapBytesと同値の2秒)。
/// テール回収時、次チャンクは「前チャンクの終端 - overlapSec*2」から始まる
/// (_extractAndEmitChunkの `keepStart = cutPointIndex - overlapBytes` と同じ考え方:
/// 実際に消費されるのは終端からoverlapBytes分手前までなので、次の開始点は
/// 終端から2×overlapSec分手前になる)。
const double kChunkOverlapSec = 2.0;

/// 生PCMのバイト数から再生時間を算出する。誤差は生じない(ヘッダ無しの
/// 固定レートPCMのため)。
Duration pcmBytesToDuration(int byteCount) {
  if (byteCount <= 0) return Duration.zero;
  final micros = (byteCount / kMasterPcmBytesPerSecond * Duration.microsecondsPerSecond).round();
  return Duration(microseconds: micros);
}

/// 秒数から、生PCM上のバイトオフセットを算出する。16bitサンプル境界(2byte)に
/// 必ず揃える(奇数バイトで切ると波形が壊れる)。
int pcmSecondsToByteOffset(double seconds) {
  if (seconds <= 0) return 0;
  final raw = (seconds * kMasterPcmBytesPerSecond).round();
  return raw - (raw % 2);
}

/// FFmpegの[Statistics.getTime]（処理済みメディア時間, ms）と、rawファイルの
/// バイト数から算出した総尺(ms)から、0.0〜1.0の進捗率を返す。
///
/// 総尺が0以下、または未確定(null)の場合はnullを返す(不定進捗として扱う)。
/// processedMsが総尺を超えることがある(FFmpegの最終統計が丸め等でわずかに
/// 超過するケース)ため、1.0にクランプする。
double? computeEncodeProgress({required int processedMs, required int totalDurationMs}) {
  if (totalDurationMs <= 0) return null;
  final ratio = processedMs / totalDurationMs;
  if (ratio < 0) return 0.0;
  if (ratio > 1) return 1.0;
  return ratio;
}

/// Realtime録音のテール(クラッシュ時にAudioChunkerの未flushバッファに
/// あった分)を切り出すべき絶対開始秒を返す。
///
/// [chunkEndTimes]は各チャンクアセットの`endTime`(nullable)。1件でもnullが
/// 混ざっている場合(この機能より前に録られた孤児など)は、正しい継ぎ目が
/// 分からないためテール回収を諦め、nullを返す(呼び出し側は末尾切れを許容する
/// フォールバックへ進む)。
///
/// 空リスト(チャンクが1つも送信されていない)の場合は0.0を返す(録音全体が
/// テール扱いになる)。
double? computeTailStartSec(List<double?> chunkEndTimes) {
  if (chunkEndTimes.isEmpty) return 0.0;
  if (chunkEndTimes.any((e) => e == null)) return null;

  final maxEnd = chunkEndTimes.cast<double>().reduce((a, b) => a > b ? a : b);
  final start = maxEnd - (kChunkOverlapSec * 2);
  return start < 0 ? 0.0 : start;
}
