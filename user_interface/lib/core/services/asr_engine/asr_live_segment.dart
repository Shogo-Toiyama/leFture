class AsrLiveSegment {
  const AsrLiveSegment({required this.text, required this.timestampSec});

  final String text;
  // 録音開始からの経過秒(RecordingState.elapsedSecondsと同じ単位)。
  final double timestampSec;
}
