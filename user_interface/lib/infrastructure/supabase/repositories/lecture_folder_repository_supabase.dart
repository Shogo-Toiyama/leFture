import 'package:lecture_companion_ui/domain/entities/lecture_folder.dart';
import 'package:lecture_companion_ui/domain/repositories/lecture_folder_repository.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

String _requireUid() {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) {
    throw StateError('Not authenticated');
  }
  return uid;
}

class LectureFolderRepositorySupabase implements LectureFolderRepository{
  static const _table = 'lecture_folders';

  @override
  Future<List<LectureFolder>> listRootFolders() async {
    final uid = _requireUid();

    final rows = await supabase
      .from(_table)
      .select()
      .eq('owner_id', uid)
      .isFilter('parent_id', null)
      .eq('is_deleted', false)
      .order('sort_order', ascending: true)
      .order('created_at', ascending: true);

    return (rows as List).map((e) => LectureFolder.fromMap(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<LectureFolder>> listChildren({required String parentId}) async {
    final uid = _requireUid();

    final rows = await supabase
        .from(_table)
        .select()
        .eq('owner_id', uid)
        .eq('parent_id', parentId)
        .eq('is_deleted', false)
        .order('sort_order', ascending: true)
        .order('created_at', ascending: true);

    return (rows as List).map((e) => LectureFolder.fromMap(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<LectureFolder> createFolder({required String name, String? parentId, required String type}) async {

    final inserted = await supabase
        .from(_table)
        .insert({
          'name': name,
          'parent_id': parentId,
          'type': type,
          'is_deleted': false,
        })
        .select()
        .single();

    return LectureFolder.fromMap(inserted);
  }

  @override
  Future<void> renameFolder({required String folderId, required String newName}) async {
    final uid = _requireUid();
    await supabase
        .from(_table)
        .update({
          'name': newName,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', folderId)
        .eq('owner_id', uid);
  }

  @override
  Future<void> softDeleteFolder({required String folderId}) async {
    final uid = _requireUid();

    await supabase
        .from(_table)
        .update({
          'is_deleted': true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', folderId)
        .eq('owner_id', uid);
  }

  @override
  Future<void> setFavorite({required String folderId, required bool isFavorite}) async {
    _requireUid();
    await supabase
        .from('lecture_folders')
        .update({'is_favorite': isFavorite})
        .eq('id', folderId);
  }

}