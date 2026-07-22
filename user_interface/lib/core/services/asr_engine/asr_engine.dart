import 'dart:typed_data';

import 'asr_live_segment.dart';

/// オンデバイスASRエンジンの共通インターフェース。
/// 実装は3種類(streaming_zipformer/sense_voice/whisper)あるが、呼び出し側
/// (LiveAsrController)から見た使い方は共通にする。
abstract class AsrEngine {
  Future<void> start();

  /// 16bit PCM(リトルエンディアン)の生バイト列を随時渡す。
  /// `AudioChunker.onMasterDataReady`と同じ形式・同じタイミングで呼ばれる想定。
  void acceptPcm16(Uint8List bytes);

  /// 確定した発話セグメントのテキスト。
  Stream<AsrLiveSegment> get segments;

  Future<void> dispose();
}
