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
