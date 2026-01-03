import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

class LocalLectureFolders extends Table {
  TextColumn get id => text()();

  // Supabaseのowner_id（将来の検索/フィルタ用）
  TextColumn get ownerId => text()();

  TextColumn get name => text()();

  // rootならnull
  TextColumn get parentId => text().nullable()();

  TextColumn get type => text().withDefault(const Constant('binder'))();

  TextColumn get icon => text().nullable()();
  TextColumn get color => text().nullable()();

  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();

  // deleted_at (nullなら生きてる)
  DateTimeColumn get deletedAt => dateTime().nullable()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  // ローカル側で「クラウドへ未送信の変更があるか」管理する
  BoolColumn get needsSync => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();

  // folders / lectures / assets とか
  TextColumn get entityType => text()();

  // LectureFolderなら folderId
  TextColumn get entityId => text()();

  // rename / favorite / delete / move / create 等
  TextColumn get op => text()();

  // JSON文字列でpayload（DriftはTextでOK）
  TextColumn get payloadJson => text()();

  // サーバ時刻ではなくローカルキュー順序用
  DateTimeColumn get enqueuedAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [LocalLectureFolders, LocalOutbox])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // --- Folders: read ---
  Future<List<LocalLectureFolder>> listRootFolders(String ownerId) {
    return (select(localLectureFolders)
          ..where((t) => t.ownerId.equals(ownerId) & t.parentId.isNull() & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder), (t) => OrderingTerm(expression: t.createdAt)]))
        .get();
  }

  Future<List<LocalLectureFolder>> listChildren(String ownerId, String parentId) {
    return (select(localLectureFolders)
          ..where((t) => t.ownerId.equals(ownerId) & t.parentId.equals(parentId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder), (t) => OrderingTerm(expression: t.createdAt)]))
        .get();
  }

  Stream<List<LocalLectureFolder>> watchRootFolders(String ownerId) {
    return (select(localLectureFolders)
          ..where((t) => t.ownerId.equals(ownerId) & t.parentId.isNull() & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder), (t) => OrderingTerm(expression: t.createdAt)]))
        .watch();
  }

  Stream<List<LocalLectureFolder>> watchChildren(String ownerId, String parentId) {
    return (select(localLectureFolders)
          ..where((t) => t.ownerId.equals(ownerId) & t.parentId.equals(parentId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder), (t) => OrderingTerm(expression: t.createdAt)]))
        .watch();
  }

  // --- Folders: upsert from cloud ---
  Future<void> upsertFoldersFromCloud(List<LocalLectureFoldersCompanion> rows) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(localLectureFolders, rows);
    });
  }

  // --- Outbox ---
  Future<void> enqueueOutbox({
    required String entityType,
    required String entityId,
    required String op,
    required String payloadJson,
  }) async {
    await into(localOutbox).insert(LocalOutboxCompanion.insert(
      entityType: entityType,
      entityId: entityId,
      op: op,
      payloadJson: payloadJson,
    ));
  }

  Future<List<LocalOutboxData>> dequeueBatch({int limit = 50}) async {
    return (select(localOutbox)
          ..orderBy([(t) => OrderingTerm(expression: t.id, mode: OrderingMode.asc)])
          ..limit(limit))
        .get();
  }

  Future<void> deleteOutboxIds(List<int> ids) async {
    await (delete(localOutbox)..where((t) => t.id.isIn(ids))).go();
  }

  Future<void> resetFoldersFromCloud({required String ownerId}) async {
    await transaction(() async {
      // 1) outbox全削除（安全：Supabaseには触れない）
      await delete(localOutbox).go();

      // 2) ローカルのフォルダも全削除（自分のowner分だけ）
      await (delete(localLectureFolders)..where((t) => t.ownerId.equals(ownerId))).go();
    });
  }

  Future<void> deleteAllOutbox() async {
    await delete(localOutbox).go();
  }

  Future<void> deleteAllLocalFolders({required String ownerId}) async {
    await (delete(localLectureFolders)..where((t) => t.ownerId.equals(ownerId))).go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'lefture_local.sqlite'));
    return NativeDatabase(file);
  });
}
