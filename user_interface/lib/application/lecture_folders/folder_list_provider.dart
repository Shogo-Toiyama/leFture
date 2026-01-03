import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_folder.dart';

part 'folder_list_provider.g.dart';

@riverpod
Stream<List<LectureFolder>> folderListStream(Ref ref, String? parentId) {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return const Stream.empty();

  final db = ref.watch(appDatabaseProvider);

  final stream = parentId == null
      ? db.watchRootFolders(uid)
      : db.watchChildren(uid, parentId);

  return stream.map((rows) {
    return rows.map((r) => LectureFolder(
      id: r.id,
      ownerId: r.ownerId,
      name: r.name,
      parentId: r.parentId,
      type: r.type,
      icon: r.icon,
      color: r.color,
      isFavorite: r.isFavorite,
      deletedAt: r.deletedAt,
      sortOrder: r.sortOrder,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    )).toList();
  });
}
