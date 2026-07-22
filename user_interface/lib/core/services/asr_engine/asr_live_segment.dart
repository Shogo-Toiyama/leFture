class AsrLiveSegment {
  const AsrLiveSegment({required this.text, required this.timestampSec, required this.isFinal});

  final String text;
  // 録音開始からの経過秒(RecordingState.elapsedSecondsと同じ単位)。
  final double timestampSec;
  // false: まだ確定していない暫定テキスト(endpoint検知前の途中経過)。
  // true: endpoint検知(またはVAD区切り)による確定テキスト。
  final bool isFinal;
}
