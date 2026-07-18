import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';
import '../app_database_provider.dart';

part 'recording_repository_drift.g.dart';

@Riverpod(keepAlive: true)
RecordingRepositoryDrift recordingRepositoryDrift(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return RecordingRepositoryDrift(db: db);
}

/// Drift（ローカルDB）だけを触る層。
/// Supabase auth / UI 依存を持たない。
class RecordingRepositoryDrift {
  RecordingRepositoryDrift({required this.db});

  final AppDatabase db;

  static const String audioBucket = 'lecture_assets';

  Future<String> createDraftLecture({
    required String userId,
    String? presetLectureId,
    String? presetCourseId,
    String? presetTitle,
    DateTime? lectureDateTime,
    bool autoStartAnalysis = true,
    bool isRealtime = true,
  }) async {
    final lectureId = presetLectureId ?? const Uuid().v4();
    final now = DateTime.now().toUtc();
    final dt = (lectureDateTime ?? now).toUtc();

    await db.into(db.localLectures).insertOnConflictUpdate(
          LocalLecturesCompanion(
            id: Value(lectureId),
            userId: Value(userId),
            courseId: Value(presetCourseId),
            title: Value(presetTitle ?? ''),
            createdAt: Value(now),
            updatedAt: Value(now),
            lectureDatetime: Value(dt),
            sortOrder: const Value(0),
            autoStartAnalysis: Value(autoStartAnalysis),
            isRealtime: Value(isRealtime),
          ),
        );

    return lectureId;
  }

  Future<void> updateLectureTitle({
    required String userId,
    required String lectureId,
    required String title,
  }) async {
    final now = DateTime.now().toUtc();
    await (db.update(db.localLectures)
          ..where((t) => t.id.equals(lectureId))
          ..where((t) => t.userId.equals(userId)))
        .write(LocalLecturesCompanion(
      title: Value(title),
      updatedAt: Value(now),
    ));
  }

  Future<void> updateLectureCourse({
    required String userId,
    required String lectureId,
    required String? courseId,
  }) async {
    final now = DateTime.now().toUtc();
    await (db.update(db.localLectures)
          ..where((t) => t.id.equals(lectureId))
          ..where((t) => t.userId.equals(userId)))
        .write(LocalLecturesCompanion(
      courseId: Value(courseId),
      updatedAt: Value(now),
    ));
  }

  Future<void> updateLectureAutoStartAnalysis({
    required String userId,
    required String lectureId,
    required bool autoStartAnalysis,
  }) async {
    final now = DateTime.now().toUtc();
    await (db.update(db.localLectures)
          ..where((t) => t.id.equals(lectureId))
          ..where((t) => t.userId.equals(userId)))
        .write(LocalLecturesCompanion(
      autoStartAnalysis: Value(autoStartAnalysis),
      updatedAt: Value(now),
    ));
  }

  Future<void> updateLectureIsRealtime({
    required String userId,
    required String lectureId,
    required bool isRealtime,
  }) async {
    final now = DateTime.now().toUtc();
    await (db.update(db.localLectures)
          ..where((t) => t.id.equals(lectureId))
          ..where((t) => t.userId.equals(userId)))
        .write(LocalLecturesCompanion(
      isRealtime: Value(isRealtime),
      updatedAt: Value(now),
    ));
  }

  /// 録音停止後に、asset + upload job を「同一トランザクション」で作る。
  /// ここが壊れないことが最重要なので transaction で囲む。
  Future<String> attachAudioAndEnqueueUpload({
    required String userId,
    required String lectureId,
    required String localPath,
    required double startTime,
    String? presetAssetId,
    int sequenceIndex = 0,
  }) async {
    final now = DateTime.now().toUtc();

    final assetId = presetAssetId ?? const Uuid().v4();
    final fileName = p.basename(localPath);
    final storagePath = '$userId/$lectureId/$fileName';
    final jobId = const Uuid().v4();

    await db.transaction(() async {
      // lecture updatedAt 更新（lecture row が存在しない可能性もあるので upsert にしたいならここを調整）
      await (db.update(db.localLectures)
            ..where((t) => t.id.equals(lectureId))
            ..where((t) => t.userId.equals(userId)))
          .write(LocalLecturesCompanion(updatedAt: Value(now)));

      // asset upsert
      await db.into(db.localLectureAssets).insertOnConflictUpdate(
            LocalLectureAssetsCompanion(
              id: Value(assetId),
              userId: Value(userId),
              lectureId: Value(lectureId),
              type: const Value('audio'),
              sequenceIndex: Value(sequenceIndex),
              localPath: Value(localPath),
              storageBucket: const Value(audioBucket),
              storagePath: Value(storagePath),
              startTime: Value(startTime),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      // upload job upsert
      await db.into(db.localUploadJobs).insertOnConflictUpdate(
            LocalUploadJobsCompanion(
              id: Value(jobId),
              userId: Value(userId),
              lectureId: Value(lectureId),
              assetId: Value(assetId),

              status: const Value('queued'),
              attemptCount: const Value(0),
              lastError: const Value(null),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    });

    return jobId;
  }

  Stream<LocalLecture?> watchLecture(String lectureId) {
    return (db.select(db.localLectures)..where((t) => t.id.equals(lectureId)))
        .watchSingleOrNull();
  }

  Stream<List<LocalLectureAsset>> watchLectureAssets(String lectureId) {
    return (db.select(db.localLectureAssets)
          ..where((t) => t.lectureId.equals(lectureId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  /// Discard時にローカルの下書きと紐づくデータを完全に消す
  Future<void> deleteLectureAndAssets(String lectureId) async {
    await db.transaction(() async {
      // 1. Jobがあれば消す
      await (db.delete(db.localUploadJobs)
            ..where((t) => t.lectureId.equals(lectureId)))
          .go();

      // 2. Assetがあれば消す
      await (db.delete(db.localLectureAssets)
            ..where((t) => t.lectureId.equals(lectureId)))
          .go();

      // 3. Lecture本体を消す
      await (db.delete(db.localLectures)
            ..where((t) => t.id.equals(lectureId)))
          .go();
    });
  }

  // ついでに UploadManager が使う「ジョブ取得」機能もここに定義しておくと綺麗です
  Stream<List<LocalUploadJob>> watchPendingJobs() {
    return (db.select(db.localUploadJobs)
          ..where((t) => t.status.isIn(['queued', 'retry_wait']))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  // Jobの状態更新用
  Future<void> updateJobStatus({
    required String jobId,
    required String status,
    String? lastError,
    DateTime? nextRetryAt,
    int? attemptCount,
  }) async {
    await (db.update(db.localUploadJobs)..where((t) => t.id.equals(jobId)))
        .write(LocalUploadJobsCompanion(
      status: Value(status),
      lastError: Value(lastError),
      nextRetryAt: Value(nextRetryAt),
      attemptCount: attemptCount != null ? Value(attemptCount) : const Value.absent(),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }
  
  // Assetの状態更新用 (Upload完了時に storagePath を入れるため)
  Future<void> updateAssetUploaded({
    required String assetId,
    required String remotePath,
  }) async {
    await (db.update(db.localLectureAssets)..where((t) => t.id.equals(assetId)))
        .write(LocalLectureAssetsCompanion(
       uploadStatus: const Value('uploaded'), // 定義済みなら
       storagePath: Value(remotePath),
       updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  Future<List<LocalUploadJob>> getPendingJobs() {
    return (db.select(db.localUploadJobs)
          ..where((t) => t.status.isIn(['queued', 'retry_wait']))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }
  
  // Lecture本体のデータ取得（Upload時にSupabaseへ送るため）
  Future<LocalLecture?> getLecture(String lectureId) {
     return (db.select(db.localLectures)..where((t) => t.id.equals(lectureId))).getSingleOrNull();
  }
  
  // Assetのデータ取得（ファイルパスを知るため）
  Future<LocalLectureAsset?> getAsset(String assetId) {
     return (db.select(db.localLectureAssets)..where((t) => t.id.equals(assetId))).getSingleOrNull();
  }

  Future<void> saveWhisperContext({
    required String lectureId,
    required String whisperContext,
  }) async {
    await (db.update(db.localLectures)..where((t) => t.id.equals(lectureId)))
        .write(LocalLecturesCompanion(
      whisperContext: Value(whisperContext),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  // 録音終了時(Done)に、総チャンク数をローカルDBに保存する
  Future<void> finishLectureRecording({
    required String lectureId,
    required int expectedChunks,
  }) async {
    await (db.update(db.localLectures)..where((t) => t.id.equals(lectureId)))
        .write(LocalLecturesCompanion(
      expectedChunks: Value(expectedChunks),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }
  
  // UploadManager用：特定の授業の「未送信ジョブ」をすべて取得する
  Future<List<LocalUploadJob>> getPendingJobsForLecture(String lectureId) {
    return (db.select(db.localUploadJobs)
          ..where((t) => t.lectureId.equals(lectureId))
          ..where((t) => t.status.isIn(['queued', 'retry_wait'])))
        .get();
  }

  // UploadManager用：start-analysisのトリガー判定に使う。
  // マスター音声(kind: 'master_audio_upload')は分析パイプラインの入力ではなく
  // 再生用途でしかないため、これが失敗・保留中でも分析開始をブロックしない。
  // ここでは音声チャンク(kind: 'audio_upload')のみを対象にする。
  Future<List<LocalUploadJob>> getPendingChunkJobsForLecture(String lectureId) {
    return (db.select(db.localUploadJobs)
          ..where((t) => t.lectureId.equals(lectureId))
          ..where((t) => t.kind.equals('audio_upload'))
          ..where((t) => t.status.isIn(['queued', 'retry_wait'])))
        .get();
  }

  // マスターオーディオ用のアップロードジョブをエンキューする
  Future<String> enqueueMasterAudioUpload({
    required String userId,
    required String lectureId,
    required String localPath,
  }) async {
    final now = DateTime.now().toUtc();
    final assetId = const Uuid().v4();
    final jobId = const Uuid().v4();
    final fileName = p.basename(localPath);
    final storagePath = '$userId/$lectureId/$fileName';

    await db.transaction(() async {
      // 1. lecture updatedAt 更新
      await (db.update(db.localLectures)
            ..where((t) => t.id.equals(lectureId))
            ..where((t) => t.userId.equals(userId)))
          .write(LocalLecturesCompanion(updatedAt: Value(now)));

      // 2. asset 登録 (type: 'master_audio', sequenceIndex: -1)
      await db.into(db.localLectureAssets).insertOnConflictUpdate(
            LocalLectureAssetsCompanion(
              id: Value(assetId),
              userId: Value(userId),
              lectureId: Value(lectureId),
              type: const Value('master_audio'),
              sequenceIndex: const Value(-1),
              localPath: Value(localPath),
              storageBucket: const Value(audioBucket),
              storagePath: Value(storagePath),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      // 3. upload job 登録 (kind: 'master_audio_upload')
      await db.into(db.localUploadJobs).insertOnConflictUpdate(
            LocalUploadJobsCompanion(
              id: Value(jobId),
              userId: Value(userId),
              lectureId: Value(lectureId),
              assetId: Value(assetId),
              kind: const Value('master_audio_upload'),
              status: const Value('queued'),
              attemptCount: const Value(0),
              lastError: const Value(null),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    });

    return jobId;
  }
}
