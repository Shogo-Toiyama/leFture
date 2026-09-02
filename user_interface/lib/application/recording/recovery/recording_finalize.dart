// lib/application/recording/recovery/recording_finalize.dart
//
// 録音を「確定」する(=ローカルの音声をOutboxへ乗せて、UploadManagerに
// 引き継ぐ)ための共通処理。以前はRecordingController.upload()の中にだけ
// 存在していたが、Recording Recovery(キル/クラッシュ後に見つかった録音を
// ユーザーが「分析を開始」で確定する経路)からも全く同じ手順が必要になった
// ため、ここへ切り出した。
//
// 呼び出し順序(expectedChunks確定 → 最終チャンクのジョブ登録 → マスター
// 音声のジョブ登録 → 自動分析の予約)を変えてはいけない — 特に
// expectedChunksを最終チャンクのジョブ登録より先に確定させる理由は
// RecordingRepositoryDrift.finishLectureRecordingの呼び出し元コメントを参照。

import 'package:lefture/application/recording/upload_manager.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/repositories/recording_repository_drift.dart';

/// 録音を確定する。[lecture]は確定対象の講義(ローカルDB行)、
/// [masterM4aPath]は既にエンコード済みのマスター音声のローカルパス。
///
/// [finalChunkPath]が非nullの場合、[finalChunkStartTime]/[nextChunkSequenceIndex]
/// も必須(最終チャンクをアセット+アップロードジョブとして登録する)。
/// [finalChunkEndTime]はテール回収の可否判定に使うので、分かる範囲で渡す
/// (通常のRecordingController.upload()経路では常に分かるが、Recovery側は
/// 元のAudioChunkerが失われているため別の方法で算出する)。
///
/// [totalChunks]はexpectedChunksとしてそのまま書き込まれる — 「最終チャンクを
/// 含めた総チャンク数」であることを呼び出し側が保証すること。
Future<void> finalizeRecordingUpload({
  required RecordingRepositoryDrift repo,
  required UploadManager uploadManager,
  required LocalLecture lecture,
  required String masterM4aPath,
  required int totalChunks,
  String? finalChunkPath,
  double? finalChunkStartTime,
  double? finalChunkEndTime,
  int? nextChunkSequenceIndex,
}) async {
  assert(
    finalChunkPath == null || (finalChunkStartTime != null && nextChunkSequenceIndex != null),
    'finalChunkPathを渡す場合はfinalChunkStartTime/nextChunkSequenceIndexも必須。',
  );

  // 1. expectedChunksを、最終チャンクのアップロードジョブを登録するより先に確定させる。
  await repo.finishLectureRecording(
    lectureId: lecture.id,
    expectedChunks: totalChunks,
  );

  // 2. 最後のチャンクのアップロードジョブを登録(あれば)
  if (finalChunkPath != null) {
    await repo.attachAudioAndEnqueueUpload(
      userId: lecture.userId,
      lectureId: lecture.id,
      localPath: finalChunkPath,
      sequenceIndex: nextChunkSequenceIndex!,
      startTime: finalChunkStartTime!,
      endTime: finalChunkEndTime,
    );
  }

  // 3. マスターオーディオのアップロードジョブを登録
  await repo.enqueueMasterAudioUpload(
    userId: lecture.userId,
    lectureId: lecture.id,
    localPath: masterM4aPath,
  );

  // 4. リアルタイム収録の自動分析を、確定したこの瞬間に予約する
  // (プレレコーデッドはマスター音声のアップロード完了時にUploadManagerが発火する)。
  await repo.maybeEnqueueStartAnalysisForRealtimeLecture(lecture.id);

  uploadManager.tryProcessQueue();
}
