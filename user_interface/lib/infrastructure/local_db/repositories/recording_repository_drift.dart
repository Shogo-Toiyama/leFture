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
    required String ownerId,
    String? presetLectureId,
    String? presetFolderId,
    String? presetTitle,
    DateTime? lectureDateTime,
  }) async {
    final lectureId = presetLectureId ?? const Uuid().v4();
    final now = DateTime.now().toUtc();
    final dt = (lectureDateTime ?? now).toUtc();

    await db.into(db.localLectures).insertOnConflictUpdate(
          LocalLecturesCompanion(
            id: Value(lectureId),
            ownerId: Value(ownerId),
            folderId: Value(presetFolderId),
            title: Value(presetTitle ?? ''),
            createdAt: Value(now),
            updatedAt: Value(now),
            lectureDatetime: Value(dt),
            sortOrder: const Value(0),
          ),
        );

    return lectureId;
  }

  Future<void> updateLectureTitle({
    required String ownerId,
    required String lectureId,
    required String title,
  }) async {
    final now = DateTime.now().toUtc();
    await (db.update(db.localLectures)
          ..where((t) => t.id.equals(lectureId))
          ..where((t) => t.ownerId.equals(ownerId)))
        .write(LocalLecturesCompanion(
      title: Value(title),
      updatedAt: Value(now),
    ));
  }

  Future<void> updateLectureFolder({
    required String ownerId,
    required String lectureId,
    required String? folderId,
  }) async {
    final now = DateTime.now().toUtc();
    await (db.update(db.localLectures)
          ..where((t) => t.id.equals(lectureId))
          ..where((t) => t.ownerId.equals(ownerId)))
        .write(LocalLecturesCompanion(
      folderId: Value(folderId),
      updatedAt: Value(now),
    ));
  }

  /// 録音停止後に、asset + upload job を「同一トランザクション」で作る。
  /// ここが壊れないことが最重要なので transaction で囲む。
  Future<String> attachAudioAndEnqueueUpload({
    required String ownerId,
    required String lectureId,
    required String localPath,
    String? presetAssetId,
  }) async {
    final now = DateTime.now().toUtc();

    final assetId = presetAssetId ?? const Uuid().v4();
    final fileName = p.basename(localPath);
    final storagePath = '$ownerId/$lectureId/$fileName';
    final jobId = const Uuid().v4();

    await db.transaction(() async {
      // lecture updatedAt 更新（lecture row が存在しない可能性もあるので upsert にしたいならここを調整）
      await (db.update(db.localLectures)
            ..where((t) => t.id.equals(lectureId))
            ..where((t) => t.ownerId.equals(ownerId)))
          .write(LocalLecturesCompanion(updatedAt: Value(now)));

      // asset upsert
      await db.into(db.localLectureAssets).insertOnConflictUpdate(
            LocalLectureAssetsCompanion(
              id: Value(assetId),
              ownerId: Value(ownerId),
              lectureId: Value(lectureId),
              type: const Value('audio'),
              localPath: Value(localPath),
              storageBucket: const Value(audioBucket),
              storagePath: Value(storagePath),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      // upload job upsert
      await db.into(db.localUploadJobs).insertOnConflictUpdate(
            LocalUploadJobsCompanion(
              id: Value(jobId),
              ownerId: Value(ownerId),
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
  }) async {
    await (db.update(db.localUploadJobs)..where((t) => t.id.equals(jobId)))
        .write(LocalUploadJobsCompanion(
      status: Value(status),
      lastError: Value(lastError),
      nextRetryAt: Value(nextRetryAt),
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
}
