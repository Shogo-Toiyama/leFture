// lib/application/lecture/lecture_list_provider.dart

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/repositories/lecture_repository_drift.dart';

import '../auth/auth_provider.dart';

part 'lecture_list_provider.g.dart';

// RepositoryのProvider
@riverpod
LectureRepositoryDrift lectureRepository(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return LectureRepositoryDrift(db);
}

// コースIDごとの授業リストを返すProvider
@riverpod
Stream<List<Lecture>> lectureListStream(Ref ref, String? courseId) {
  final user = ref.watch(currentUserProvider);
  final uid = user?.id;
  if (uid == null) return const Stream.empty();

  final repo = ref.watch(lectureRepositoryProvider);
  return repo.watchLectures(userId: uid, courseId: courseId);
}