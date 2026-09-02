// lib/application/recording/recovery/recovery_models.dart
//
// Recording Recoveryが扱う状態のデータクラス群。AsrModelManagerの
// AsrLanguageModelState(application/asr/asr_model_manager.dart)と同じ
// 「status enum + progress + errorMessage」の形に揃えてある。

import 'package:flutter/foundation.dart';

/// 起動時に検出された、キル/クラッシュで取り残された録音。
///
/// この時点でDB行(LocalLectures)は必ず存在する(RecordingRecoveryServiceが
/// 検出時に、無ければ最小限のdraft行を再生成する)ので、タイトル・録音言語・
/// Realtime有無等はUI側がrecordingRepositoryDriftProvider.watchLecture経由で
/// 別途取得する。ここに持つのはファイルシステム由来の情報だけ。
@immutable
class OrphanRecording {
  const OrphanRecording({
    required this.lectureId,
    required this.rawPath,
    required this.m4aPath,
    required this.hasRaw,
    required this.hasM4a,
    required this.duration,
  });

  final String lectureId;
  final String rawPath;
  final String m4aPath;

  /// 生PCM(master_audio.raw)が残っているか。通常はtrue。
  /// falseになるのは、旧コード(RecordingController.upload)がencodeMasterRawToM4a
  /// でm4a化に成功した直後(rawを削除済み)、その後の DB 書き込みより前に
  /// 死んだ場合だけ。
  final bool hasRaw;

  /// m4aが既に存在するか(この復旧処理が始まる前に、何らかの形でエンコード
  /// 済みだったケース)。
  final bool hasM4a;

  /// 録音の長さ。rawが残っていればバイト数から厳密に算出、rawが無ければ
  /// m4aをffprobeして取得(取得できなければDuration.zero)。
  final Duration duration;
}

enum RecoveryEncodeStatus {
  /// まだエンコードを開始していない(検出直後、または前回失敗して再試行待ち)。
  pending,
  encoding,
  ready,
  failed,
}

@immutable
class RecoveryEncodeState {
  const RecoveryEncodeState({
    required this.status,
    this.progress,
    this.errorMessage,
  });

  final RecoveryEncodeStatus status;

  /// 0.0〜1.0。不定/未開始の場合はnull。
  final double? progress;
  final String? errorMessage;

  static const initial = RecoveryEncodeState(status: RecoveryEncodeStatus.pending);

  RecoveryEncodeState copyWith({
    RecoveryEncodeStatus? status,
    double? progress,
    String? errorMessage,
  }) {
    return RecoveryEncodeState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage,
    );
  }
}
