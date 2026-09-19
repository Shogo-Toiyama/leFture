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

/// Realtime Transcribeがこの録音セッションで無効化された理由。録音開始の
/// 直前(RecordingController._startRecordingSession)に一度だけ確定し、
/// セッション中は変わらない。RecordingPageはこれを見て「なぜ今回は録音後に
/// まとめて文字起こしになるのか」を常時表示バナーでユーザーに伝える——
/// 無言でチャンク送信だけをスキップすると、バックエンドが届かないチャンクを
/// いつまでも待ち続ける事故になるため(2026-09-19に実際に発生)。
enum RealtimeDowngradeReason {
  /// 現在のプランがMax未満。
  requiresUpgrade,

  /// クレジット残高がkMinCreditsForRealtimeTranscribeに満たない。
  insufficientCredits,

  /// プラン/クレジット情報を確認できなかった(オフライン・サーバー障害等)。
  /// 「分からなければ許可」は事故の元になるため、確認できない場合は常に
  /// OFFとして扱う。
  unresolved,
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
    this.realtimeDowngradeReason,
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
  final RealtimeDowngradeReason? realtimeDowngradeReason;
  // フェーズを変えるほどではない一回きりの通知(SnackBar等)。RecordingPageが
  // ref.listenで検知して表示した後、clearTransientNoticeで消す想定。
  // errorMessageと違い、phase==errorの時だけ表示されるものではない。
  final String? transientNotice;
  final double audioLevel;

  String get title {
    if (lecture != null) {
      final t = lecture!.title?.trim();
      if (t != null && t.isNotEmpty) return t;
      final tg = lecture!.titleGenerated?.trim();
      if (tg != null && tg.isNotEmpty) return tg;
    }
    if (draftTitle != null && draftTitle!.trim().isNotEmpty) return draftTitle!.trim();
    return '';
  }
  String? get courseId => draftCourseId;
  String? get lectureId => currentLectureId;

  bool get isBusy =>
      phase == RecordingPhase.requestingPermission ||
      phase == RecordingPhase.uploading;

  bool get isRecording => phase == RecordingPhase.recording;
  bool get isPaused => phase == RecordingPhase.paused;
  bool get canUpload => phase == RecordingPhase.paused && lecture != null;

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
    RealtimeDowngradeReason? realtimeDowngradeReason,
    bool clearRealtimeDowngradeReason = false,
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
      // ★ 明示的な値渡しを常にclearRealtimeDowngradeReasonより優先する
      // (_startRecordingSessionが新しいセッションの判定結果で「上書きしつつ
      // 前回の値は必ず消す」を一度の呼び出しでやるため、両方を同時に渡す)。
      realtimeDowngradeReason: realtimeDowngradeReason ??
          (clearRealtimeDowngradeReason ? null : this.realtimeDowngradeReason),
      transientNotice: clearTransientNotice ? null : (transientNotice ?? this.transientNotice),
      audioLevel: audioLevel ?? this.audioLevel,
    );
  }
}
