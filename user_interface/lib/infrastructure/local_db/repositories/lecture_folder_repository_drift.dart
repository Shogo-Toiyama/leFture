import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_folder.dart';
import 'package:lecture_companion_ui/domain/repositories/lecture_folder_repository.dart';
import '../app_database.dart';
import '../../supabase/supabase_client.dart';
import 'package:uuid/uuid.dart';

String _requireUid() {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) throw StateError('Not authenticated');
  return uid;
}

final _uuid = Uuid();
String _newId() => _uuid.v4();

class LectureFolderRepositoryDrift implements LectureFolderRepository {
  final AppDatabase db;
  LectureFolderRepositoryDrift(this.db);

  LectureFolder _toDomain(LocalLectureFolder row) {
    return LectureFolder(
      id: row.id,
      ownerId: row.ownerId,
      name: row.name,
      parentId: row.parentId,
      type: row.type,
      icon: row.icon,
      color: row.color,
      isFavorite: row.isFavorite,
      deletedAt: row.deletedAt,
      sortOrder: row.sortOrder,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  @override
  Future<List<LectureFolder>> listRootFolders() async {
    final uid = _requireUid();
    final rows = await db.listRootFolders(uid);
    return rows.map(_toDomain).toList();
  }

  @override
  Future<List<LectureFolder>> listChildren({required String parentId}) async {
    final uid = _requireUid();
    final rows = await db.listChildren(uid, parentId);
    return rows.map(_toDomain).toList();
  }

  // create/rename/delete/favorite は “ローカル即反映＋outbox” に変更
  @override
  Future<LectureFolder> createFolder({required String name, String? parentId, required String type}) async {
    final uid = _requireUid();
    final now = DateTime.now().toUtc();

    // ローカルIDをUUIDにしたいなら uuid package を入れて生成してOK
    // 今は簡易: supabase側で作るのではなく、まずローカル生成に寄せるのがおすすめ
    final localId = _newId();

    final row = LocalLectureFoldersCompanion.insert(
      id: localId,
      ownerId: uid,
      name: name,
      parentId: Value(parentId),
      type: Value(type),
      icon: const Value(null),
      color: const Value(null),
      isFavorite: const Value(false),
      deletedAt: const Value(null),
      sortOrder: const Value(0),
      createdAt: now,
      updatedAt: now,
      needsSync: const Value(true),
    );

    await db.upsertFoldersFromCloud([row]);

    await db.enqueueOutbox(
      entityType: 'lecture_folders',
      entityId: localId,
      op: 'create',
      payloadJson: jsonEncode({
        'id': localId,
        'name': name,
        'parent_id': parentId,
        'type': type,
      }),
    );

    // domainへ
    return LectureFolder(
      id: localId,
      ownerId: uid,
      name: name,
      parentId: parentId,
      type: type,
      icon: null,
      color: null,
      isFavorite: false,
      deletedAt: null,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<void> renameFolder({required String folderId, required String newName}) async {
    final uid = _requireUid();
    final now = DateTime.now().toUtc();

    await (db.update(db.localLectureFolders)
          ..where((t) => t.id.equals(folderId) & t.ownerId.equals(uid)))
        .write(LocalLectureFoldersCompanion(
      name: Value(newName),
      updatedAt: Value(now),
      needsSync: const Value(true),
    ));

    await db.enqueueOutbox(
      entityType: 'lecture_folders',
      entityId: folderId,
      op: 'rename',
      payloadJson: jsonEncode({'name': newName}),
    );
  }

  @override
  Future<void> softDeleteFolder({required String folderId}) async {
    final uid = _requireUid();
    final now = DateTime.now().toUtc();

    await (db.update(db.localLectureFolders)
          ..where((t) => t.id.equals(folderId) & t.ownerId.equals(uid)))
        .write(LocalLectureFoldersCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      needsSync: const Value(true),
    ));

    await db.enqueueOutbox(
      entityType: 'lecture_folders',
      entityId: folderId,
      op: 'delete',
      payloadJson: jsonEncode({'deleted_at': now.toIso8601String()}),
    );
  }

  @override
  Future<void> setFavorite({required String folderId, required bool isFavorite}) async {
    final uid = _requireUid();
    final now = DateTime.now().toUtc();

    await (db.update(db.localLectureFolders)
          ..where((t) => t.id.equals(folderId) & t.ownerId.equals(uid)))
        .write(LocalLectureFoldersCompanion(
      isFavorite: Value(isFavorite),
      updatedAt: Value(now),
      needsSync: const Value(true),
    ));

    await db.enqueueOutbox(
      entityType: 'lecture_folders',
      entityId: folderId,
      op: 'favorite',
      payloadJson: jsonEncode({'is_favorite': isFavorite}),
    );
  }
}