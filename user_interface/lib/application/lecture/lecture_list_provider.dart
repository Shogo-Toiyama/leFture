// lib/application/lecture/lecture_list_provider.dart

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/repositories/lecture_repository_drift.dart';

part 'lecture_list_provider.g.dart';

// RepositoryのProvider
@riverpod
LectureRepositoryDrift lectureRepository(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return LectureRepositoryDrift(db);
}

// フォルダIDごとの授業リストを返すProvider
@riverpod
Stream<List<Lecture>> lectureListStream(Ref ref, String? folderId,) {
  final repo = ref.watch(lectureRepositoryProvider);
  return repo.watchLectures(folderId: folderId);
}