import 'package:flutter/foundation.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';

enum RecordingPhase {
  idle,
  requestingPermission,
  recording,
  paused,
  uploading, // Job作成中/待機中
  queued,    // Outboxに入った
  uploaded,  // (以前の名残として残すか、完了状態として使用)
  error,
}

@immutable
class RecordingState {
  const RecordingState({
    required this.phase,
    required this.elapsedSeconds,
    this.currentLectureId,
    this.lecture,
    this.errorMessage,
    this.draftTitle,
    this.draftFolderId,
  });

  final RecordingPhase phase;
  final int elapsedSeconds;

  final String? currentLectureId;

  final LocalLecture? lecture;

  final String? errorMessage;

  final String? draftTitle;
  final String? draftFolderId;
  // --- UI互換性のためのGetter (これがあればPage側の修正は最小限で済みます) ---

  String get title => lecture?.title ?? draftTitle ?? '';
  String? get folderId => lecture != null ? lecture!.folderId : draftFolderId;
  String? get lectureId => currentLectureId;
  
  // assetIdはDB内で管理されるようになったので、UIが知る必要は基本なくなりますが、
  // もし表示に必要なら別途持たせる必要があります。今回は一旦外します。
  
  /// まだファイルとして確定していない一時的なパスが必要な場合のために
  /// Controller内で保持するか、ここに持たせるかですが、
  /// 録音完了時のパス受け渡しはController内で行うためStateからは削除可能です。
  /// (もし再生機能などで必要なら復活させます)

  bool get isBusy =>
      phase == RecordingPhase.requestingPermission ||
      phase == RecordingPhase.uploading;

  bool get isRecording => phase == RecordingPhase.recording;
  bool get isPaused => phase == RecordingPhase.paused;

  // Uploadできる条件: Paused(録音停止中) かつ DBのデータがあること
  bool get canUpload => phase == RecordingPhase.paused && lecture != null;

  factory RecordingState.idle() {
    return const RecordingState(
      phase: RecordingPhase.idle,
      elapsedSeconds: 0,
      currentLectureId: null,
      lecture: null,
      errorMessage: null,
    );
  }

  RecordingState copyWith({
    RecordingPhase? phase,
    int? elapsedSeconds,
    String? currentLectureId,
    LocalLecture? lecture,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? title,
    String? folderId,
    bool forceClearFolderId = false,
  }) {
    return RecordingState(
      phase: phase ?? this.phase,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      currentLectureId: currentLectureId ?? this.currentLectureId,
      lecture: lecture ?? this.lecture,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      draftTitle: title ?? draftTitle,
      draftFolderId: forceClearFolderId ? null : (folderId ?? draftFolderId),
    );
  }
}