import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/domain/repositories/lecture_folder_repository.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/repositories/lecture_folder_repository_drift.dart';

part 'lecture_folder_providers.g.dart';

@riverpod
LectureFolderRepository folderRepository(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return LectureFolderRepositoryDrift(db);
}
