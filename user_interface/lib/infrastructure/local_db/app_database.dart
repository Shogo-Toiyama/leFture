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
  TextColumn get titleGenerated => text().nullable()();

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

class LocalCourses extends Table {
  TextColumn get id => text()(); // uuid
  TextColumn get userId => text()();

  TextColumn get courseTitle => text()();
  TextColumn get courseCode => text().nullable()();
  TextColumn get summary => text().nullable()();

  // course_attributes への参照
  TextColumn get schoolId => text().nullable()();
  TextColumn get yearId => text().nullable()();
  TextColumn get termId => text().nullable()();
  TextColumn get subjectId => text().nullable()();
  TextColumn get professorId => text().nullable()();

  // icon/color 等。jsonbはTEXTでシリアライズしてそのまま保存
  TextColumn get metadataJson => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  TextColumn get syncStatus =>
      text().withDefault(const Constant('local_only'))();

  @override
  Set<Column> get primaryKey => {id, userId};
}

class LocalCourseAttributes extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();

  // "school" / "year" / "term" / "subject"
  TextColumn get attributeType => text()();
  TextColumn get attributeName => text()();
  TextColumn get metadataJson => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  TextColumn get syncStatus =>
      text().withDefault(const Constant('local_only'))();

  @override
  Set<Column> get primaryKey => {id, userId};
}

class LocalAnnouncements extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get lectureId => text()();

  // TODO / EVENT / HINT / INFO
  TextColumn get type => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get location => text().nullable()();
  IntColumn get startSid => integer().nullable()();
  IntColumn get endSid => integer().nullable()();
  TextColumn get relatedTopicTitle => text().nullable()();
  TextColumn get datetimeParametersJson => text().nullable()();

  // ユーザーがローカルで「完了」をトグルできるため書き込み系に分類
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get metadataJson => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  TextColumn get syncStatus =>
      text().withDefault(const Constant('local_only'))();

  @override
  Set<Column> get primaryKey => {id, userId};
}

// ===== 読み取り専用キャッシュ(サーバー生成コンテンツ、ローカル編集なし) =====

class LocalFunFacts extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get lectureId => text()();

  TextColumn get title => text().nullable()();
  TextColumn get hook => text()();
  TextColumn get body => text()();
  TextColumn get metadataJson => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  // このローカル行をいつ取得したか(差分Pullの鮮度管理用)
  DateTimeColumn get lastSyncedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id, userId};
}

class LocalReviewCards extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get lectureId => text()();

  IntColumn get topicNumber => integer()();
  // jsonb配列 [{type, text, items[]}, ...] をそのままTEXTで保存
  TextColumn get cardContentJson => text()();
  // hook / core_why / gotcha / next_action
  TextColumn get cardType => text()();
  TextColumn get title => text().nullable()();
  TextColumn get heroEmoji => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get lastSyncedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id, userId};
}

class LocalDeepNotes extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get lectureId => text()();

  IntColumn get topicNumber => integer()();
  TextColumn get noteContents => text()(); // Markdown文字列

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get lastSyncedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id, userId};
}

class LocalKeywords extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get lectureId => text()();

  IntColumn get topicNumber => integer()();
  TextColumn get keyword => text()();
  TextColumn get definition => text()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get lastSyncedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id, userId};
}

class LocalLectureTopics extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get lectureId => text()();

  // Supabase側カラム名は `index`(SQL予約語のためリネーム)
  IntColumn get topicIndex => integer()();
  TextColumn get topicTitle => text()();
  TextColumn get topicType => text()();
  TextColumn get summary => text().nullable()();
  IntColumn get startSid => integer().nullable()();
  IntColumn get endSid => integer().nullable()();
  // R2キャッシュ(r2_cache/)と連携するstorage path。実ファイル本体はここに持たない
  TextColumn get imagePath => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get lastSyncedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id, userId};
}

class LocalTopicMaps extends Table {
  TextColumn get courseId => text()();
  TextColumn get userId => text()();

  TextColumn get mapJson => text()(); // jsonb(ノード/エッジ構造)をそのまま保存
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastSyncedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {courseId, userId};
}

// ===== 同期カーソル管理(全エンティティタイプ共通) =====

class LocalSyncCursors extends Table {
  TextColumn get userId => text()();
  // "lecture" / "fun_fact" / "review_card" / "course" / ...
  TextColumn get entityType => text()();

  // 前回pullで実際に取得した行のうち最大のupdated_at(wall-clockではない)
  DateTimeColumn get lastPulledAt => dateTime().nullable()();
  // 前回「全件Pull」を実行した時刻(セーフティネットの間隔判定用)
  DateTimeColumn get lastFullPulledAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {userId, entityType};
}

@DriftDatabase(
  tables: [
    LocalOutbox,
    LocalLectures,
    LocalLectureAssets,
    LocalUploadJobs,
    LocalCourses,
    LocalCourseAttributes,
    LocalAnnouncements,
    LocalFunFacts,
    LocalReviewCards,
    LocalDeepNotes,
    LocalKeywords,
    LocalLectureTopics,
    LocalTopicMaps,
    LocalSyncCursors,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 7;

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
      if (from < 6) {
        // バージョン6: LocalLectures に titleGenerated カラム追加
        for (final table in allTables) {
          await m.drop(table);
        }
        await m.createAll();
      }
      if (from < 7) {
        // バージョン7: オフライン優先化に向けたスキーマ再設計。
        // Courses/CourseAttributes/Announcements/FunFacts/ReviewCards/
        // DeepNotes/Keywords/LectureTopics/TopicMaps/SyncCursors を追加し、
        // LocalLectures.lastSyncError(未使用カラム)を削除。
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
      ..where((t) => t.userId.equals(userId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.lectureDatetime, mode: OrderingMode.desc)]);
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

  Future<int> getLocalLecturesCount(String userId) async {
    final query = select(localLectures)
      ..where((t) => t.userId.equals(userId) & t.deletedAt.isNull());
    final list = await query.get();
    return list.length;
  }

  // --- Sync Cursors ---

  Future<LocalSyncCursor?> getSyncCursor(String userId, String entityType) {
    return (select(localSyncCursors)
          ..where((t) => t.userId.equals(userId) & t.entityType.equals(entityType)))
        .getSingleOrNull();
  }

  /// 指定エンティティタイプのカーソルを更新する。
  /// [lastPulledAt] / [lastFullPulledAt] を省略した場合は既存値を保持する
  /// (差分Pullのみ実行した回はlastFullPulledAtを書き換えない、といった使い方を想定)。
  Future<void> upsertSyncCursor({
    required String userId,
    required String entityType,
    DateTime? lastPulledAt,
    bool updateLastPulledAt = true,
    DateTime? lastFullPulledAt,
    bool updateLastFullPulledAt = false,
  }) async {
    final current = await getSyncCursor(userId, entityType);
    await into(localSyncCursors).insertOnConflictUpdate(
      LocalSyncCursorsCompanion(
        userId: Value(userId),
        entityType: Value(entityType),
        lastPulledAt: updateLastPulledAt
            ? Value(lastPulledAt)
            : Value(current?.lastPulledAt),
        lastFullPulledAt: updateLastFullPulledAt
            ? Value(lastFullPulledAt)
            : Value(current?.lastFullPulledAt),
      ),
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'lefture_local.sqlite'));
    return NativeDatabase(file);
  });
}
