import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/domain/repositories/lecture_folder_repository.dart';
import '../../infrastructure/supabase/repositories/lecture_folder_repository_supabase.dart';

part 'lecture_folder_providers.g.dart';

@riverpod
LectureFolderRepository folderRepository(Ref ref) {
  return LectureFolderRepositorySupabase();
}
