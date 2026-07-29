// lib/application/lecture/lecture_list_provider.dart

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lefture/domain/entities/lecture.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:lefture/infrastructure/local_db/repositories/lecture_repository_drift.dart';

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
  // Stream.empty() は二度とイベントを発行しないため、AsyncLoadingのまま
  // 永久に止まってしまう(currentUserProviderが後で非nullになっても復帰しない)。
  // 空リストを1回だけ発行する形にして、必ずAsyncDataへ解決させる。
  if (uid == null) return Stream.value(const <Lecture>[]);

  final repo = ref.watch(lectureRepositoryProvider);
  return repo.watchLectures(userId: uid, courseId: courseId);
}

// コースの有無に関わらず、ユーザーが1件でもレクチャーを持っているかを判定するためのProvider
// keepAlive: true — Welcome画面で先読み(ref.read(...future))した直後にWelcomeが
// 破棄されると、autoDisposeのままではこのProviderも一緒に破棄されてしまい、
// Home表示時にもう一度ゼロから購読し直し(ローディング表示)になっていた。
// セッション中は保持することで、Welcomeでの先読みがHomeまで活きる。
@Riverpod(keepAlive: true)
Stream<List<Lecture>> allLecturesStream(Ref ref) {
  final user = ref.watch(currentUserProvider);
  final uid = user?.id;
  if (uid == null) return Stream.value(const <Lecture>[]);

  final repo = ref.watch(lectureRepositoryProvider);
  return repo.watchAllLectures(userId: uid);
}