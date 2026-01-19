import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../infrastructure/supabase/supabase_client.dart';
import '../../infrastructure/local_db/repositories/recording_repository_drift.dart';
import '../../infrastructure/local_db/app_database.dart';

part 'recording_repository.g.dart';

@Riverpod(keepAlive: true)
RecordingRepository recordingRepository(Ref ref) {
  final driftRepo = ref.watch(recordingRepositoryDriftProvider);
  return RecordingRepository(drift: driftRepo);
}

/// RecordingController が呼ぶ “ユースケース入口”
/// - 今ログインしている userId を確定して
/// - Drift repository に渡す
class RecordingRepository {
  RecordingRepository({required this.drift});

  final RecordingRepositoryDrift drift;

  String _requireUid() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw StateError('User is not signed in.');
    return uid;
  }

  Future<String> createDraftLecture({
    String? presetLectureId,
    String? presetFolderId,
    String? presetTitle,
    DateTime? lectureDateTime,
  }) {
    final uid = _requireUid();
    return drift.createDraftLecture(
      ownerId: uid,
      presetLectureId: presetLectureId,
      presetFolderId: presetFolderId,
      presetTitle: presetTitle,
      lectureDateTime: lectureDateTime,
    );
  }

  Future<void> updateLectureTitle({
    required String lectureId,
    required String title,
  }) {
    final uid = _requireUid();
    return drift.updateLectureTitle(ownerId: uid, lectureId: lectureId, title: title);
  }

  Future<void> updateLectureFolder({
    required String lectureId,
    required String? folderId,
  }) {
    final uid = _requireUid();
    return drift.updateLectureFolder(ownerId: uid, lectureId: lectureId, folderId: folderId);
  }

  Future<String> attachAudioAndEnqueueUpload({
    required String lectureId,
    required String localPath,
    String? presetAssetId,
  }) {
    final uid = _requireUid();
    return drift.attachAudioAndEnqueueUpload(
      ownerId: uid,
      lectureId: lectureId,
      localPath: localPath,
      presetAssetId: presetAssetId,
    );
  }

  Stream<LocalLecture?> watchLecture(String lectureId) => drift.watchLecture(lectureId);

  Stream<List<LocalLectureAsset>> watchLectureAssets(String lectureId) =>
      drift.watchLectureAssets(lectureId);
}
