import 'dart:io';
import 'dart:math';
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

  // 書き込み時点のスナップショットは持たない設計に変更(OutboxPushHandlerが
  // push実行時に対応するLocal*テーブルの最新行から都度payloadを組み立てるため)。
  // 過去互換のため列自体は残すが、新しい書き込み経路では使わない。
  TextColumn get payloadJson => text().nullable()();

  // サーバ時刻ではなくローカルキュー順序用
  DateTimeColumn get enqueuedAt => dateTime().withDefault(currentDateAndTime)();

  // リトライ管理(LocalUploadJobsと同じパターン)
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();

  // 最大リトライ回数を超えた行。削除はせず、自動リトライの対象から外すだけ
  // (診断・手動リカバリのためデータは残す)。
  BoolColumn get givenUp => boolean().withDefault(const Constant(false))();
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

  // AI生成サマリー、マスター音声のR2 storage path、汎用メタデータ(jsonb)。
  // 講義詳細ページのオフライン化のため追加(いずれもクライアントからは
  // 編集しないので、Outbox送信側では扱わずPullでのみ更新する)。
  TextColumn get summary => text().nullable()();
  TextColumn get audioPath => text().nullable()();
  TextColumn get metadataJson => text().nullable()();

  // local_only / synced / needs_sync
  TextColumn get syncStatus =>
      text().withDefault(const Constant('local_only'))();

  // 講義詳細を最後に開いた時刻(ローカルキャッシュのLRU判定用)
  DateTimeColumn get lastAccessedAt => dateTime().nullable()();

  // trueの間は容量制限のLRU剥がし対象から除外する(明示的ダウンロード用)
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();

  // trueの間、LectureOutboxPushHandlerが「移動元のTopic Mapをstale化(remove)」+
  // 「移動先(=現在のcourseId)のTopic Mapをstale化(add)」をpush時に送信し、
  // 両方成功したらfalseに戻す。移動元が「コース未設定(null)」だった場合も
  // 区別できるよう、courseIdとは別にこのフラグを持つ。
  // 削除の場合はcourseId自体がdeletedAt付きで残るので、このフラグは使わない
  // (courseIdとdeletedAtを見てremoveすればよい)。
  BoolColumn get topicMapMovePending => boolean().withDefault(const Constant(false))();
  // 移動直前(上書きされる前)のcourseId。移動元が「コース未設定」だった場合はnull。
  TextColumn get pendingTopicMapStaleCourseId => text().nullable()();

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
  // SID(例: "S042")は文字列参照であり数値ではない。Supabase側も文字列。
  TextColumn get startSid => text().nullable()();
  TextColumn get endSid => text().nullable()();
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

// ===== 読み取り専用キャッシュ(サーバー生成コンテンツ)、一部ローカル編集可 =====

class LocalFunFacts extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get lectureId => text()();

  TextColumn get title => text().nullable()();
  TextColumn get hook => text()();
  TextColumn get body => text()();
  // サーバーの`metadata`(jsonb)のキャッシュ。reactionは別カラムで管理するため
  // ここには含まれない可能性がある(push時にreaction列の値をマージする)。
  TextColumn get metadataJson => text().nullable()();

  // ユーザーがローカルで即時更新できる唯一のフィールド(Like/Dislike)。
  // "like" / "dislike" / null
  TextColumn get reaction => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  // Supabase側に自動更新トリガーが設定されたため、差分Pullの基準を
  // created_atからこちらに統一した。
  DateTimeColumn get updatedAt => dateTime()();
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
  // サーバーの`metadata`(jsonb)。reaction("like"/"dislike")やsaved(bool)を
  // ここに格納する。ユーザーがローカルで即時更新できる唯一のフィールド群。
  TextColumn get metadataJson => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
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
  // サーバーの`metadata`(jsonb)。reaction("like"/"dislike")やsaved(bool)を
  // ここに格納する。ユーザーがローカルで即時更新できる唯一のフィールド群。
  TextColumn get metadataJson => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
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
  // SID(例: "S042")は文字列参照であり数値ではない。Supabase側も文字列。
  TextColumn get startSid => text().nullable()();
  TextColumn get endSid => text().nullable()();
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
  // Lectureの削除/移動でstaleになり、まだ修復されていないことを示す。
  // trueの間はUIが「Recreate Topic Map」を案内する。
  BoolColumn get isStale => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastSyncedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {courseId, userId};
}

// ===== ローカルキャッシュファイルの容量管理 =====

/// R2からダウンロードしてローカルにキャッシュしたファイル(トランスクリプト/
/// トピック画像等)を、講義単位で容量管理できるように記録するテーブル。
/// ファイルシステムを毎回走査せずに済むよう、書き込み時にサイズを保存しておく。
class LocalCacheEntries extends Table {
  // 実体はstoragePath(例: "{uid}/{lectureId}/images/topic_1.jpg")をそのまま使う
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get lectureId => text()();

  TextColumn get localFilePath => text()();
  IntColumn get sizeBytes => integer()();

  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id, userId};
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
    LocalCacheEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 15;

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
      if (from < 8) {
        // バージョン8: ローカルキャッシュの容量管理に向けて
        // LocalLectures に lastAccessedAt/isPinned を追加し、
        // LocalCacheEntries(R2キャッシュファイルのサイズ追跡)を新設。
        for (final table in allTables) {
          await m.drop(table);
        }
        await m.createAll();
      }
      if (from < 9) {
        // バージョン9: Outboxの汎用化。attemptCount/lastError/nextRetryAt/
        // givenUpを追加し、payloadJsonをnullableに変更(push時に最新のローカル
        // 行から再構築する自己修復設計に変更したため)。
        for (final table in allTables) {
          await m.drop(table);
        }
        await m.createAll();
      }
      if (from < 10) {
        // バージョン10: FunFactのLike/Dislikeをローカルファースト化するため
        // LocalFunFacts.reaction を追加。
        for (final table in allTables) {
          await m.drop(table);
        }
        await m.createAll();
      }
      if (from < 11) {
        // バージョン11: LocalAnnouncements/LocalLectureTopicsのstartSid/endSidが
        // 誤ってIntColumnになっていたのをTextColumnに修正(SIDは"S042"のような
        // 文字列参照でSupabase側もtext型)。
        for (final table in allTables) {
          await m.drop(table);
        }
        await m.createAll();
      }
      if (from < 12) {
        // バージョン12: 講義詳細ページのオフライン化に向けてLocalLecturesに
        // summary/audioPath/metadataJsonを追加。Supabase側にupdated_at自動更新
        // トリガーが整備されたため、LocalFunFacts/LocalReviewCards/LocalDeepNotes
        // にもupdatedAtを追加し、差分Pullをupdated_at基準に統一。
        for (final table in allTables) {
          await m.drop(table);
        }
        await m.createAll();
      }
      if (from < 13) {
        // バージョン13: TopicMapをオフライン優先化するため、LocalTopicMapsに
        // isStale(「Recreate Topic Map」表示の判定用)を追加。
        for (final table in allTables) {
          await m.drop(table);
        }
        await m.createAll();
      }
      if (from < 14) {
        // バージョン14: Lecture削除/Course間移動時のTopic Map stale化(mark-stale)を
        // Outbox経由の確実な配送に変更するため、LocalLecturesに
        // topicMapMovePending/pendingTopicMapStaleCourseIdを追加。
        for (final table in allTables) {
          await m.drop(table);
        }
        await m.createAll();
      }
      if (from < 15) {
        // バージョン15: ReviewCards/DeepNotesにLike/Dislike/Saveをローカル
        // ファースト化するため、LocalReviewCards/LocalDeepNotesにmetadataJson
        // (reaction/savedを格納するjsonb相当)を追加。
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

  /// 講義詳細ページ用。単一講義をIDで監視する(以前はSupabase Realtimeで
  /// 直接ストリーミングしていたが、Realtimeが有効化されていなかったため
  /// 実質更新を受け取れていなかった。ローカルDB経由でオフライン優先に統一する)。
  Stream<LocalLecture?> watchLectureById(String lectureId) {
    return (select(localLectures)..where((t) => t.id.equals(lectureId)))
        .watchSingleOrNull();
  }

  // --- Outbox ---

  /// [payloadJson]は基本的に不要(OutboxPushHandlerがpush実行時に対応する
  /// Local*テーブルの最新行から都度payloadを組み立てる)。指定しなくてよい。
  Future<void> enqueueOutbox({
    required String entityType,
    required String entityId,
    required String op,
    String? payloadJson,
  }) async {
    await into(localOutbox).insert(LocalOutboxCompanion.insert(
      entityType: entityType,
      entityId: entityId,
      op: op,
      payloadJson: Value(payloadJson),
    ));
  }

  Future<List<LocalOutboxData>> dequeueBatch({int limit = 50}) async {
    return (select(localOutbox)
          ..orderBy([(t) => OrderingTerm(expression: t.id, mode: OrderingMode.asc)])
          ..limit(limit))
        .get();
  }

  /// 自動リトライ対象の行(ギブアップしておらず、バックオフ待ち時間を過ぎた)
  /// を古い順に取得する。
  Future<List<LocalOutboxData>> dequeuePendingOutbox({int limit = 50}) async {
    final now = DateTime.now().toUtc();
    return (select(localOutbox)
          ..where((t) =>
              t.givenUp.equals(false) &
              (t.nextRetryAt.isNull() | t.nextRetryAt.isSmallerThanValue(now)))
          ..orderBy([(t) => OrderingTerm(expression: t.id, mode: OrderingMode.asc)])
          ..limit(limit))
        .get();
  }

  /// Outbox行のPush失敗を記録する。指数バックオフ(30秒→上限5分)で
  /// [nextRetryAt]を設定し、[maxAttempts]を超えたら削除せず`givenUp`にする
  /// (診断・手動リカバリのためデータは残す)。
  Future<void> recordOutboxFailure(
    int id,
    String error, {
    int maxAttempts = 10,
  }) async {
    final row = await (select(localOutbox)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;

    final nextAttempt = row.attemptCount + 1;

    if (nextAttempt >= maxAttempts) {
      await (update(localOutbox)..where((t) => t.id.equals(id))).write(
        LocalOutboxCompanion(
          attemptCount: Value(nextAttempt),
          lastError: Value(error),
          givenUp: const Value(true),
        ),
      );
      return;
    }

    const maxBackoffSeconds = 5 * 60;
    final delaySeconds = min(30 * pow(2, nextAttempt - 1).toInt(), maxBackoffSeconds);
    final nextRetryAt = DateTime.now().toUtc().add(Duration(seconds: delaySeconds));

    await (update(localOutbox)..where((t) => t.id.equals(id))).write(
      LocalOutboxCompanion(
        attemptCount: Value(nextAttempt),
        lastError: Value(error),
        nextRetryAt: Value(nextRetryAt),
      ),
    );
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

  Future<int> getLocalFunFactsCount(String userId) async {
    final query = select(localFunFacts)
      ..where((t) => t.userId.equals(userId) & t.deletedAt.isNull());
    final list = await query.get();
    return list.length;
  }

  /// 指定entityTypeでギブアップしていないOutbox行のentityIdの集合を返す。
  /// Pull処理が、まだPushできていないローカルの変更をサーバーの古い値で
  /// 上書きしてしまわないようにするためのガード用。
  Future<Set<String>> getPendingOutboxEntityIds(String entityType) async {
    final rows = await (select(localOutbox)
          ..where((t) => t.entityType.equals(entityType) & t.givenUp.equals(false)))
        .get();
    return rows.map((r) => r.entityId).toSet();
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

  // --- Lecture access / pin (キャッシュ容量管理用) ---

  /// 講義詳細を開いたタイミングで呼ぶ。LRU判定の基準時刻を更新する。
  Future<void> touchLectureAccessed(String lectureId) async {
    await (update(localLectures)..where((t) => t.id.equals(lectureId))).write(
      LocalLecturesCompanion(lastAccessedAt: Value(DateTime.now().toUtc())),
    );
  }

  Future<void> setLecturePinned(String lectureId, bool pinned) async {
    await (update(localLectures)..where((t) => t.id.equals(lectureId)))
        .write(LocalLecturesCompanion(isPinned: Value(pinned)));
  }

  Future<List<String>> getPinnedLectureIds(String userId) async {
    final rows = await (select(localLectures)
          ..where((t) => t.userId.equals(userId) & t.isPinned.equals(true)))
        .get();
    return rows.map((r) => r.id).toList();
  }

  Future<List<LocalLecture>> getLecturesByIds(String userId, List<String> ids) {
    if (ids.isEmpty) return Future.value(const []);
    return (select(localLectures)
          ..where((t) => t.userId.equals(userId) & t.id.isIn(ids)))
        .get();
  }

  Future<List<LocalLectureAsset>> getAssetsForLecture(String lectureId) {
    return (select(localLectureAssets)..where((t) => t.lectureId.equals(lectureId))).get();
  }

  // --- 30日ハードデリート ---

  Future<List<LocalLecture>> getExpiredSoftDeletedLectures({
    required String userId,
    required DateTime olderThan,
  }) {
    return (select(localLectures)
          ..where((t) =>
              t.userId.equals(userId) &
              t.deletedAt.isNotNull() &
              t.deletedAt.isSmallerThanValue(olderThan) &
              t.syncStatus.equals('synced')))
        .get();
  }

  /// 講義本体とその関連データ(音声アセット/アップロードジョブ/キャッシュ/
  /// コンテンツキャッシュ各種)をまとめて物理削除する。ファイル実体はこの
  /// メソッドの呼び出し側(LocalRetentionService)で事前に削除しておくこと。
  Future<void> hardDeleteLectureCascade(String lectureId) async {
    await transaction(() async {
      await (delete(localLectureAssets)..where((t) => t.lectureId.equals(lectureId))).go();
      await (delete(localUploadJobs)..where((t) => t.lectureId.equals(lectureId))).go();
      await (delete(localCacheEntries)..where((t) => t.lectureId.equals(lectureId))).go();
      await (delete(localFunFacts)..where((t) => t.lectureId.equals(lectureId))).go();
      await (delete(localReviewCards)..where((t) => t.lectureId.equals(lectureId))).go();
      await (delete(localDeepNotes)..where((t) => t.lectureId.equals(lectureId))).go();
      await (delete(localKeywords)..where((t) => t.lectureId.equals(lectureId))).go();
      await (delete(localLectureTopics)..where((t) => t.lectureId.equals(lectureId))).go();
      await (delete(localAnnouncements)..where((t) => t.lectureId.equals(lectureId))).go();
      await (delete(localLectures)..where((t) => t.id.equals(lectureId))).go();
    });
  }

  // --- ローカルキャッシュファイルの容量管理 ---

  Future<void> upsertCacheEntry({
    required String id,
    required String userId,
    required String lectureId,
    required String localFilePath,
    required int sizeBytes,
  }) async {
    await into(localCacheEntries).insertOnConflictUpdate(
      LocalCacheEntriesCompanion.insert(
        id: id,
        userId: userId,
        lectureId: lectureId,
        localFilePath: localFilePath,
        sizeBytes: sizeBytes,
      ),
    );
  }

  Future<void> deleteCacheEntry({required String id, required String userId}) async {
    await (delete(localCacheEntries)
          ..where((t) => t.id.equals(id) & t.userId.equals(userId)))
        .go();
  }

  Future<List<LocalCacheEntry>> getAllCacheEntries(String userId) {
    return (select(localCacheEntries)..where((t) => t.userId.equals(userId))).get();
  }

  Future<List<LocalCacheEntry>> getCacheEntriesForLecture(String userId, String lectureId) {
    return (select(localCacheEntries)
          ..where((t) => t.userId.equals(userId) & t.lectureId.equals(lectureId)))
        .get();
  }

  /// 講義のキャッシュ(R2キャッシュファイルの記録)と、キャッシュ済みコンテンツ
  /// (FunFacts等、将来pull実装が入った時のため先取りで対応)を削除する。
  /// 講義本体(LocalLectures行)は消さない — 一覧に軽量メタデータとして残す。
  Future<void> deleteCacheEntriesForLecture({
    required String userId,
    required String lectureId,
  }) async {
    await transaction(() async {
      await (delete(localCacheEntries)
            ..where((t) => t.userId.equals(userId) & t.lectureId.equals(lectureId)))
          .go();
      await (delete(localFunFacts)
            ..where((t) => t.userId.equals(userId) & t.lectureId.equals(lectureId)))
          .go();
      await (delete(localReviewCards)
            ..where((t) => t.userId.equals(userId) & t.lectureId.equals(lectureId)))
          .go();
      await (delete(localDeepNotes)
            ..where((t) => t.userId.equals(userId) & t.lectureId.equals(lectureId)))
          .go();
      await (delete(localKeywords)
            ..where((t) => t.userId.equals(userId) & t.lectureId.equals(lectureId)))
          .go();
      await (delete(localLectureTopics)
            ..where((t) => t.userId.equals(userId) & t.lectureId.equals(lectureId)))
          .go();
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'lefture_local.sqlite'));
    return NativeDatabase(file);
  });
}
