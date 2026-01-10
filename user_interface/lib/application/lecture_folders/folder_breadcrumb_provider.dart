// lib/application/lecture_folders/folder_breadcrumb_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

part 'folder_breadcrumb_provider.g.dart';

class FolderCrumb {
  final String? id; // null = Home
  final String name;
  const FolderCrumb({required this.id, required this.name});
}

@riverpod
Future<List<FolderCrumb>> folderBreadcrumb(
  Ref ref,
  String? folderId,
) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return const [];

  final db = ref.watch(appDatabaseProvider);

  if (folderId == null) {
    return const [];
  }

  final chain = <FolderCrumb>[];
  String? current = folderId;
  final visited = <String>{};

  while (current != null && !visited.contains(current) && visited.length < 50) {
    visited.add(current);

    final row = await db.getFolderById(ownerId: uid, folderId: current);
    if (row == null) break;

    chain.add(FolderCrumb(
      // ignore: avoid_dynamic_calls
      id: row.id,
      // ignore: avoid_dynamic_calls
      name: row.name,
    ));

    // ignore: avoid_dynamic_calls
    current = row.parentId;
  }

  return chain.reversed.toList();
}
