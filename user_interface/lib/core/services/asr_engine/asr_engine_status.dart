/// 一時停止中(Liveタブ非表示/バックグラウンド)も、直前この秒数ぶんの生音声
/// だけは捨てずに持っておく設計値。中断がこの秒数以内に収まれば、実際には
/// 何も欠けない([VadOfflineEngine]がこの値そのままリングバッファに使う)。
/// UI側([RecordingPage]の欠落区間の案内表示)も同じ値をしきい値として使う
/// ことで、「案内が出ない区間は本当に何も欠けていない」という保証を成立させる。
const double kAsrLivePreBufferSeconds = 3.0;

/// オンデバイスASRエンジンの稼働状況。認識テキスト([AsrLiveSegment])とは
/// 別に、UIが「今ちゃんと音が届いていて処理が動いているか」を示すために使う。
///
/// 文字起こしは仕組み上どうしても数秒待たされるため、その間ユーザーには
/// 「本当に録音・認識されているのか」が分からない。テキスト以外にも常時動く
/// 手がかりを出すのがこの状態の目的。
class AsrEngineStatus {
  const AsrEngineStatus({
    this.speechDetected = false,
    this.decoding = false,
    this.droppedFinalCount = 0,
  });

  /// VADが今この瞬間、発話を検知しているか。
  final bool speechDetected;

  /// デコード(認識)を実行中か。
  final bool decoding;

  /// 端末の処理が実時間に追いつかず、やむを得ず捨てた「確定」チャンクの累計。
  /// 0より大きい＝その区間の文字起こしが永久に欠けているということなので、
  /// 黙って捨てずUIに出す。暫定チャンクの破棄はここには数えない
  /// (あちらは捨てても後から確定テキストが同じ区間を埋めるため)。
  final int droppedFinalCount;

  static const idle = AsrEngineStatus();

  AsrEngineStatus copyWith({bool? speechDetected, bool? decoding, int? droppedFinalCount}) {
    return AsrEngineStatus(
      speechDetected: speechDetected ?? this.speechDetected,
      decoding: decoding ?? this.decoding,
      droppedFinalCount: droppedFinalCount ?? this.droppedFinalCount,
    );
  }
}
