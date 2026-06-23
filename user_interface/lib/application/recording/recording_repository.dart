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
    String? presetCourseId,
    String? presetTitle,
    DateTime? lectureDateTime,
  }) {
    final uid = _requireUid();
    return drift.createDraftLecture(
      userId: uid,
      presetLectureId: presetLectureId,
      presetCourseId: presetCourseId,
      presetTitle: presetTitle,
      lectureDateTime: lectureDateTime,
    );
  }

  Future<void> updateLectureTitle({
    required String lectureId,
    required String title,
  }) {
    final uid = _requireUid();
    return drift.updateLectureTitle(userId: uid, lectureId: lectureId, title: title);
  }

  Future<void> updateLectureCourse({
    required String lectureId,
    required String? courseId,
  }) {
    final uid = _requireUid();
    return drift.updateLectureCourse(userId: uid, lectureId: lectureId, courseId: courseId);
  }

  Future<String> attachAudioAndEnqueueUpload({
    required String lectureId,
    required String localPath,
    required double startTime,
    int sequenceIndex = 0,
    String? presetAssetId,
  }) {
    final uid = _requireUid();
    return drift.attachAudioAndEnqueueUpload(
      userId: uid,
      lectureId: lectureId,
      localPath: localPath,
      startTime: startTime,
      sequenceIndex: sequenceIndex,
      presetAssetId: presetAssetId,
    );
  }

  Stream<LocalLecture?> watchLecture(String lectureId) => drift.watchLecture(lectureId);

  Stream<List<LocalLectureAsset>> watchLectureAssets(String lectureId) =>
      drift.watchLectureAssets(lectureId);
}
