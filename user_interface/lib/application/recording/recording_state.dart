import 'package:flutter/foundation.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';

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
    this.transientNotice,
    this.audioLevel = 0.0,
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
  // フェーズを変えるほどではない一回きりの通知(SnackBar等)。RecordingPageが
  // ref.listenで検知して表示した後、clearTransientNoticeで消す想定。
  // errorMessageと違い、phase==errorの時だけ表示されるものではない。
  final String? transientNotice;
  final double audioLevel;

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
      audioLevel: 0.0,
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
    String? transientNotice,
    bool clearTransientNotice = false,
    double? audioLevel,
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
      transientNotice: clearTransientNotice ? null : (transientNotice ?? this.transientNotice),
      audioLevel: audioLevel ?? this.audioLevel,
    );
  }
}
