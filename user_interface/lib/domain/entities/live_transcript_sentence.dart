class LiveTranscriptSentence {
  const LiveTranscriptSentence({
    required this.chunkIndex,
    required this.text,
    required this.startSec,
  });

  final int chunkIndex;
  final String text;
  final double startSec;
}

/// LiveTranscriptRepository.watchLiveTranscriptが1回のポーリングごとに返す
/// スナップショット。文の一覧に加えて、サーバー側が実際に文字起こしを
/// 終えている範囲の終端(絶対秒)も一緒に返す。
///
/// ★ 文の一覧だけでは「サーバーがどこまで進んだか」を正確に表せない
/// (無音チャンクは文を1つも生まないため)。coverageEndSecは無音チャンクも
/// 含めて計算するので、節電ラベル(AsrTranscriptGap)を「サーバーが追い越した
/// かどうか」で正しく消せるようにするための値。
typedef LiveTranscriptSnapshot = ({
  List<LiveTranscriptSentence> sentences,
  double? coverageEndSec,
});
