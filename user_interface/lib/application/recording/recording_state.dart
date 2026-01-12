import 'package:flutter/foundation.dart';

enum RecordingPhase {
  idle,
  requestingPermission,
  recording,
  paused,
  uploading,
  queued,
  uploaded,
  error,
}

@immutable
class RecordingState {
  const RecordingState({
    required this.phase,
    required this.elapsedSeconds,
    required this.title,
    required this.folderId,
    required this.lectureId,
    required this.assetId,
    required this.localPath,
    required this.remotePath,
    required this.errorMessage,
    required this.metadataWarning,
  });

  final RecordingPhase phase;
  final int elapsedSeconds;

  /// lecture metadata
  final String? title;
  final String? folderId;

  /// stable ids per “one recording session”
  final String? lectureId;
  final String? assetId;

  /// file paths
  final String? localPath;
  final String? remotePath;

  /// UI message
  final String? errorMessage;

  /// metadata sync warning (non-fatal)
  final String? metadataWarning;

  bool get isBusy =>
      phase == RecordingPhase.requestingPermission ||
      phase == RecordingPhase.uploading;

  bool get isRecording => phase == RecordingPhase.recording;
  bool get isPaused => phase == RecordingPhase.paused;

  bool get canUpload => phase == RecordingPhase.paused && localPath != null;

  factory RecordingState.idle({
    String? lectureId,
    String? assetId,
    String title = '',
    String? folderId,
  }) {
    return RecordingState(
      phase: RecordingPhase.idle,
      elapsedSeconds: 0,
      title: title,
      folderId: folderId,
      lectureId: lectureId,
      assetId: assetId,
      localPath: null,
      remotePath: null,
      errorMessage: null,
      metadataWarning: null,
    );
  }

  RecordingState copyWith({
    RecordingPhase? phase,
    int? elapsedSeconds,
    String? title,
    String? folderId,
    String? lectureId,
    String? assetId,
    String? localPath,
    String? remotePath,
    String? errorMessage,
    String? metadataWarning,
    bool setFolderIdToNull = false,
    bool clearErrorMessage = false,
    bool clearMetadataWarning = false,
  }) {
    return RecordingState(
      phase: phase ?? this.phase,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      title: title ?? this.title,
      folderId: setFolderIdToNull ? null : (folderId ?? this.folderId),
      lectureId: lectureId ?? this.lectureId,
      assetId: assetId ?? this.assetId,
      localPath: localPath ?? this.localPath,
      remotePath: remotePath ?? this.remotePath,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      metadataWarning: clearMetadataWarning
          ? null
          : (metadataWarning ?? this.metadataWarning),
    );
  }
}
