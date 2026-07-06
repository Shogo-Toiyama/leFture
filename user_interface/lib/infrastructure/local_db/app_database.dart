import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

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

class LocalLectures extends Table {
  TextColumn get id => text()(); // uuid
  TextColumn get userId => text()();

  TextColumn get courseId => text().nullable()(); // null = コース未設定
  TextColumn get title => text().nullable()();

  IntColumn get expectedChunks => integer().nullable()();

  DateTimeColumn get lectureDatetime => dateTime().nullable()();

  IntColumn get sortOrder => integer().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  // Groq Whisper に渡すコンテキスト文字列（コースタイトル＋過去キーワード）
  TextColumn get whisperContext => text().nullable()();

  // local_only / synced / needs_sync
  TextColumn get syncStatus =>
      text().withDefault(const Constant('local_only'))();

  TextColumn get lastSyncError => text().nullable()();

  @override
  Set<Column> get primaryKey => {id, userId};
}

class LocalLectureAssets extends Table {
  TextColumn get id => text()(); // uuid
  TextColumn get userId => text()();
  TextColumn get lectureId => text()(); // uuid

  TextColumn get type => text()(); // "audio"

  RealColumn get startTime => real().withDefault(const Constant(0.0))();

  IntColumn get sequenceIndex => integer().withDefault(const Constant(0))();

  TextColumn get localPath => text().nullable()();

  TextColumn get storageBucket => text().nullable()();
  TextColumn get storagePath => text().nullable()();

  // queued / uploading / uploaded / failed
  TextColumn get uploadStatus =>
      text().withDefault(const Constant('queued'))();

  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id, userId};
}

class LocalUploadJobs extends Table {
  TextColumn get id => text()(); // uuid
  TextColumn get userId => text()();

  TextColumn get kind => text().withDefault(const Constant('audio_upload'))();

  TextColumn get lectureId => text()();
  TextColumn get assetId => text()();

  // queued / uploading / done / failed
  TextColumn get status => text().withDefault(const Constant('queued'))();

  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id, userId};
}

@DriftDatabase(
  tables: [
    LocalOutbox,
    LocalLectures,
    LocalLectureAssets,
    LocalUploadJobs,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(localLectures);
        await m.createTable(localLectureAssets);
        await m.createTable(localUploadJobs);
      }
      if (from < 3) {
        // バージョン3: owner_id → user_id カラム変更（開発中のため全削除）
        for (final table in allTables) {
          await m.drop(table);
        }
        await m.createAll();
      }
      if (from < 4) {
        // バージョン4: folder_id → course_id 変更、LocalLectureFolders 削除
        for (final table in allTables) {
          await m.drop(table);
        }
        await m.createAll();
      }
      if (from < 5) {
        // バージョン5: LocalLectures に whisperContext カラム追加
        for (final table in allTables) {
          await m.drop(table);
        }
        await m.createAll();
      }
    },
  );

  // --- Lectures ---

  Stream<List<LocalLecture>> watchLectures(String userId, String? courseId) {
    final query = select(localLectures)
      ..where((t) => t.userId.equals(userId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.lectureDatetime, mode: OrderingMode.desc)]);

    if (courseId == null) {
      query.where((t) => t.courseId.isNull());
    } else {
      query.where((t) => t.courseId.equals(courseId));
    }

    return query.watch();
  }

  /// コースの有無に関わらず、ユーザーの全レクチャーを横断して監視する。
  /// （オンボーディング完了判定など「1件でも録音済みか」を見たい場合に使う）
  Stream<List<LocalLecture>> watchAllLectures(String userId) {
    final query = select(localLectures)
      ..where((t) => t.userId.equals(userId) & t.deletedAt.isNull());
    return query.watch();
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

  Future<void> deleteAllOutbox() async {
    await delete(localOutbox).go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'lefture_local.sqlite'));
    return NativeDatabase(file);
  });
}
