// lib/application/lecture_folders/folder_list_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_folder.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

part 'folder_list_provider.g.dart';

LectureFolder _toDomain(dynamic row) {
  // row は Drift の LocalLectureFolder だけど、型を公開しない
  // ignore: avoid_dynamic_calls
  return LectureFolder(
    // ignore: avoid_dynamic_calls
    id: row.id as String,
    // ignore: avoid_dynamic_calls
    ownerId: row.ownerId as String,
    // ignore: avoid_dynamic_calls
    name: row.name as String,
    // ignore: avoid_dynamic_calls
    parentId: row.parentId as String?,
    // ignore: avoid_dynamic_calls
    type: row.type as String,
    // ignore: avoid_dynamic_calls
    icon: row.icon as String?,
    // ignore: avoid_dynamic_calls
    color: row.color as String?,
    // ignore: avoid_dynamic_calls
    isFavorite: row.isFavorite as bool,
    // ignore: avoid_dynamic_calls
    deletedAt: row.deletedAt as DateTime?,
    // ignore: avoid_dynamic_calls
    sortOrder: row.sortOrder as int,
    // ignore: avoid_dynamic_calls
    createdAt: row.createdAt as DateTime,
    // ignore: avoid_dynamic_calls
    updatedAt: row.updatedAt as DateTime,
  );
}

@riverpod
Stream<List<LectureFolder>> folderListStream(
  Ref ref,
  String? parentId,
) {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return const Stream.empty();

  final db = ref.watch(appDatabaseProvider);

  final stream = parentId == null
      ? db.watchRootFolders(uid)
      : db.watchChildren(uid, parentId);

  return stream.map((rows) => rows.map(_toDomain).toList());
}
