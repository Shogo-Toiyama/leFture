import 'package:flutter/foundation.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database.dart';

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
    this.currentLectureId,
    this.lecture,
    this.errorMessage,
    this.draftTitle,
    this.draftCourseId,
    this.autoStartAnalysis = true,
    this.realtimeTranscribe = false,
  });

  final RecordingPhase phase;
  final int elapsedSeconds;
  final String? currentLectureId;
  final LocalLecture? lecture;
  final String? errorMessage;
  final String? draftTitle;
  final String? draftCourseId;
  final bool autoStartAnalysis;
  final bool realtimeTranscribe;

  // LocalLecture.courseId は build_runner 実行後に使用可能になる
  String get title => lecture?.title ?? draftTitle ?? '';
  String? get courseId => draftCourseId;
  String? get lectureId => currentLectureId;

  bool get isBusy =>
      phase == RecordingPhase.requestingPermission ||
      phase == RecordingPhase.uploading;

  bool get isRecording => phase == RecordingPhase.recording;
  bool get isPaused => phase == RecordingPhase.paused;
  bool get canUpload => 
      (phase == RecordingPhase.paused || phase == RecordingPhase.recording) && 
      lecture != null;

  factory RecordingState.idle() {
    return const RecordingState(
      phase: RecordingPhase.idle,
      elapsedSeconds: 0,
      autoStartAnalysis: true,
      realtimeTranscribe: false,
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
    String? courseId,
    bool forceClearCourseId = false,
    bool? autoStartAnalysis,
    bool? realtimeTranscribe,
  }) {
    return RecordingState(
      phase: phase ?? this.phase,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      currentLectureId: currentLectureId ?? this.currentLectureId,
      lecture: lecture ?? this.lecture,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      draftTitle: title ?? draftTitle,
      draftCourseId: forceClearCourseId ? null : (courseId ?? draftCourseId),
      autoStartAnalysis: autoStartAnalysis ?? this.autoStartAnalysis,
      realtimeTranscribe: realtimeTranscribe ?? this.realtimeTranscribe,
    );
  }
}
