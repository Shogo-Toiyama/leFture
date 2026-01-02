import 'package:lecture_companion_ui/domain/entities/lecture_folder.dart';

abstract class LectureFolderRepository {
  Future<List<LectureFolder>> listRootFolders();

  Future<List<LectureFolder>> listChildren({required String parentId}); 

  Future<LectureFolder> createFolder({required String name, String? parentId, required String type});

  Future<void> renameFolder({required String folderId, required String newName});

  Future<void> softDeleteFolder({required String folderId});

  Future<void> setFavorite({required String folderId, required bool isFavorite});
}