enum RecordingPhase {
  idle,
  requestingPermission,
  recording,
  stopping,
  uploading,
  queued,
  uploaded,
  error,
}

class RecordingState {
  const RecordingState({
    required this.phase,
    required this.elapsedSeconds,
    this.lectureId,
    this.localPath,
    this.remotePath,
    this.errorMessage,
  });

  final RecordingPhase phase;
  final int elapsedSeconds;
  final String? lectureId;
  final String? localPath;
  final String? remotePath;
  final String? errorMessage;

  RecordingState copyWith({
    RecordingPhase? phase,
    int? elapsedSeconds,
    String? lectureId,
    String? localPath,
    String? remotePath,
    String? errorMessage,
  }) {
    return RecordingState(
      phase: phase ?? this.phase,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      lectureId: lectureId ?? this.lectureId,
      localPath: localPath ?? this.localPath,
      remotePath: remotePath ?? this.remotePath,
      errorMessage: errorMessage,
    );
  }

  static RecordingState idle() => const RecordingState(
        phase: RecordingPhase.idle,
        elapsedSeconds: 0,
      );
}

