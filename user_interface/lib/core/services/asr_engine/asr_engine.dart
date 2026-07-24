import 'dart:typed_data';

import 'asr_live_segment.dart';

/// オンデバイスASRエンジンの共通インターフェース。
/// 現状の実装は共有Whisperモデルを使う[VadOfflineEngine]のみ。
abstract class AsrEngine {
  Future<void> start();

  /// 16bit PCM(リトルエンディアン)の生バイト列を随時渡す。
  /// `AudioChunker.onMasterDataReady`と同じ形式・同じタイミングで呼ばれる想定。
  void acceptPcm16(Uint8List bytes);

  /// Liveタブが非表示/アプリがバックグラウンドの間、実際の認識処理
  /// (VAD推論・デコード)を一時停止する。`acceptPcm16`自体は呼ばれ続ける
  /// 前提で、内部のサンプルカウント(タイムスタンプの基準)だけは
  /// 一時停止中も進め続けること(再開後にタイムスタンプが実時間から
  /// ズレないようにするため)。
  void setDecodingPaused(bool paused);

  /// 確定した発話セグメントのテキスト。
  Stream<AsrLiveSegment> get segments;

  Future<void> dispose();
}
