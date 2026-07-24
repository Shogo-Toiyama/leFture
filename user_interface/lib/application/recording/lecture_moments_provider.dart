import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:lefture/domain/entities/lecture_moment.dart';
import 'package:lefture/infrastructure/local_db/repositories/lecture_moment_repository_drift.dart';

part 'lecture_moments_provider.g.dart';

@riverpod
Stream<List<LectureMoment>> lectureMoments(Ref ref, String lectureId) {
  return ref.watch(lectureMomentRepositoryDriftProvider).watchMomentsForLecture(lectureId);
}
