// lib/application/auth/local_data_wipe_service.dart
//
// サインアウト時にこの端末のローカルデータを消す/サインイン時に前のアカウントの
// 残骸を消すためのサービス。
//
// なぜサインアウトで消すのか:
// - ローカルDBはサインアウトでは消えないため、同じ端末で複数アカウントを使うと
//   userIdの違う行が同居する。主キーが{id, userId}の複合キーなので、idだけで
//   絞り込む書き込みが複数行にヒットして壊れる(チュートリアルのアナウンスは
//   全ユーザー共通の固定id `ann_1` を使うため、実際にこれが起きていた)。
// - Outboxはユーザー単位に分かれていないため、前のアカウントの未送信行を今の
//   セッションでpushしようとしてRLS/FK違反を出し続ける。
// - 前のアカウントの未送信行を残したまま別端末で同じ操作をされると、後で
//   再ログインした時に「古いローカル値でサーバーを上書き」してしまう
//   (last-write-wins)。残すより、サインアウト時に送り切る/破棄する方が安全。
//
// 消す対象と残す対象の線引き:
// - 消す: ユーザーに紐づく全テーブルと、その実ファイル(録音音声・取り込み音声・
//   R2キャッシュ)。
// - 残す: [LocalAsrModels] とモデル実ファイル。オンデバイスASRモデルは数百MBの
//   ダウンロードで、ユーザーデータではなく「端末のリソース」なので、サインアウト
//   のたびに消すと再ログイン時に巨大な再DLが発生する。端末設定
//   (SharedPreferences: 表示言語・録音言語・オンボーディング既読など)も同じ理由で
//   このサービスは一切触らない。
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';

/// まだサーバーへ送れていないローカル変更の件数。サインアウト時に「これが
/// 消えます」と提示するために使う。
class PendingSyncSummary {
  const PendingSyncSummary({
    required this.pendingChangeCount,
    required this.pendingRecordingCount,
  });

  const PendingSyncSummary.empty()
      : pendingChangeCount = 0,
        pendingRecordingCount = 0;

  /// Outboxに残っている未送信の変更(完了トグル・編集・削除など)の件数。
  final int pendingChangeCount;

  /// 音声がまだアップロードし切れていない録音(講義)の件数。
  final int pendingRecordingCount;

  bool get isEmpty => pendingChangeCount == 0 && pendingRecordingCount == 0;
  bool get isNotEmpty => !isEmpty;

  @override
  String toString() =>
      'PendingSyncSummary(changes: $pendingChangeCount, recordings: $pendingRecordingCount)';
}

class LocalDataWipeService {
  LocalDataWipeService(this._db);

  final AppDatabase _db;

  /// ドキュメントディレクトリ直下にあるユーザーデータの実ファイル置き場。
  /// - `lectures/<lectureId>/...` : 録音した音声(チャンク/マスター)
  /// - `imported_audio/...`       : 端末から取り込んだ音声ファイル
  /// - `r2_cache/<uid>/...`       : R2から取得したトピック画像・トランスクリプト
  ///
  /// ASRモデルはApplicationSupportディレクトリの`asr_models/`配下なので、ここに
  /// 含まれない = 消えない。
  static const _userDataDirNames = <String>[
    'lectures',
    'imported_audio',
    'r2_cache',
  ];

  /// サインアウトでも消さないテーブル。
  Set<String> get _preservedTableNames => {_db.localAsrModels.actualTableName};

  /// 未同期データの件数を数える。
  Future<PendingSyncSummary> countPending({required String userId}) async {
    // Outboxはユーザー列を持たないので全件を数える。サインアウト時は結局
    // 全行消すため、これがそのまま「消える変更の件数」になる。
    final outboxRows = await _db.select(_db.localOutbox).get();

    // 「録音」単位で数える。1回の講義は多数のチャンク(=asset)に分かれるので、
    // asset件数をそのまま出すと「未アップロードの録音 47件」のような誤解を
    // 招く表示になってしまう。
    final assets = await (_db.select(_db.localLectureAssets)
          ..where(
            (t) =>
                t.userId.equals(userId) &
                t.uploadStatus.equals('uploaded').not() &
                t.localPath.isNotNull(),
          ))
        .get();

    return PendingSyncSummary(
      pendingChangeCount: outboxRows.length,
      pendingRecordingCount: assets.map((a) => a.lectureId).toSet().length,
    );
  }

  /// バックオフ待ち/ギブアップ済みのOutbox行を、次のpushで再試行されるように
  /// 戻す。戻した行数を返す。サインアウト直前の「最後の送信機会」で使う。
  Future<int> reviveOutboxRetries() => _db.resetOutboxRetryState();

  /// この端末のユーザーデータを全部消す(サインアウト時)。
  ///
  /// [_preservedTableNames]以外の全テーブルをまとめて空にする。テーブルを個別に
  /// 列挙しないのは、新しいテーブルを足した人がここへの追記を忘れても消し漏れが
  /// 起きないようにするため。逆に「端末レベルで残すべきテーブル」を新設した時は
  /// [_preservedTableNames]に足す必要がある。
  Future<void> wipeAll() async {
    final preserved = {
      ..._preservedTableNames,
      // プロフィールは行ごと消さず、下で個人情報だけを消す(理由は_scrubUserProfiles)。
      _db.localUserProfiles.actualTableName,
    };

    await _db.transaction(() async {
      for (final table in _db.allTables) {
        if (preserved.contains(table.actualTableName)) continue;
        await _db.delete(table).go();
      }
      await _scrubUserProfiles();
    });

    await _deleteUserDataDirectories();

    DevLog.add(
      '🧹 [LocalDataWipe] Wiped all local user data (ASR models, device '
      'preferences and onboarding/tutorial flags kept)',
    );
  }

  /// [LocalUserProfiles]は行を消さず、個人情報のカラムだけをNULLにする。
  ///
  /// この行のmetadataには`onboarding_completed_at` / `tutorial_completed_at`が
  /// 入っており、router.dartのオンボーディング判定がこれを見ている。行ごと消すと
  /// 判定が「6秒以内にサーバーから取得できるか」の一発勝負になり、通信が遅い
  /// 端末では**オンボーディング済みのアカウントが再びオンボーディングに送られる**
  /// (実際に発生した)。フラグはサーバー側の事実のキャッシュなので残し、
  /// username/bio/interests/future_goals/avatar_urlといった実体のある個人情報だけを
  /// 消す。
  ///
  /// なお、この「PIIがすべてNULLの行」は
  /// [UserProfileOutboxPushHandler]がサーバーへ書き戻さないよう検知に使っている。
  Future<void> _scrubUserProfiles() async {
    await _db.update(_db.localUserProfiles).write(
      const LocalUserProfilesCompanion(
        username: Value(null),
        avatarUrl: Value(null),
        bio: Value(null),
        interests: Value(null),
        futureGoals: Value(null),
      ),
    );
  }

  /// 現在サインインしているユーザー以外の行を消す(サインイン時の保険)。
  ///
  /// 通常はサインアウト時の[wipeAll]で空になっているが、wipeが中断された端末や、
  /// この仕組みより前のバージョンで複数アカウントを使った端末には残骸がある。
  /// Outboxはユーザー列を持たないためここでは触らないが、参照先の実体行が
  /// 消えると各PushハンドラがOutbox行を「送るものが無い」として畳むので、
  /// 放置しても自然に解消する。
  Future<void> wipeOtherUsers({required String currentUserId}) async {
    // 実ファイルのパスは行を消す前に集めておく。
    final foreignLectureIds = await (_db.select(_db.localLectures)
          ..where((t) => t.userId.equals(currentUserId).not()))
        .get()
        .then((rows) => rows.map((r) => r.id).toSet());
    final foreignFilePaths = <String>{};
    for (final asset in await (_db.select(_db.localLectureAssets)
          ..where((t) => t.userId.equals(currentUserId).not()))
        .get()) {
      final path = asset.localPath;
      if (path != null && path.isNotEmpty) foreignFilePaths.add(path);
    }
    for (final entry in await (_db.select(_db.localCacheEntries)
          ..where((t) => t.userId.equals(currentUserId).not()))
        .get()) {
      foreignFilePaths.add(entry.localFilePath);
    }

    // userId列を持つテーブル。新しいユーザー紐付きテーブルを足した時はここにも
    // 追記が必要(消し漏れは前アカウントのデータが残り続けることを意味する)。
    var deleted = 0;
    Future<void> deleteForeign<T extends Table, D>(
      TableInfo<T, D> table,
      Expression<bool> Function(T) filter,
    ) async {
      deleted += await (_db.delete(table)..where(filter)).go();
    }

    await _db.transaction(() async {
      await deleteForeign(_db.localLectures, (t) => t.userId.equals(currentUserId).not());
      await deleteForeign(_db.localLectureAssets, (t) => t.userId.equals(currentUserId).not());
      await deleteForeign(_db.localUploadJobs, (t) => t.userId.equals(currentUserId).not());
      await deleteForeign(_db.localCourses, (t) => t.userId.equals(currentUserId).not());
      await deleteForeign(_db.localCourseAttributes, (t) => t.userId.equals(currentUserId).not());
      await deleteForeign(_db.localAnnouncements, (t) => t.userId.equals(currentUserId).not());
      await deleteForeign(_db.localLectureMoments, (t) => t.userId.equals(currentUserId).not());
      await deleteForeign(_db.localFunFacts, (t) => t.userId.equals(currentUserId).not());
      await deleteForeign(_db.localReviewCards, (t) => t.userId.equals(currentUserId).not());
      await deleteForeign(_db.localDeepNotes, (t) => t.userId.equals(currentUserId).not());
      await deleteForeign(_db.localKeywords, (t) => t.userId.equals(currentUserId).not());
      await deleteForeign(_db.localLectureTopics, (t) => t.userId.equals(currentUserId).not());
      await deleteForeign(_db.localTopicMaps, (t) => t.userId.equals(currentUserId).not());
      await deleteForeign(_db.localSyncCursors, (t) => t.userId.equals(currentUserId).not());
      await deleteForeign(_db.localCacheEntries, (t) => t.userId.equals(currentUserId).not());
      // LocalUserProfilesはPKがユーザーID自身(id)。
      await deleteForeign(_db.localUserProfiles, (t) => t.id.equals(currentUserId).not());
    });

    if (deleted == 0 && foreignFilePaths.isEmpty && foreignLectureIds.isEmpty) {
      return; // 残骸なし(通常はこちら)。ログも出さない。
    }

    await _deleteFiles(foreignFilePaths);
    await _deleteLectureDirectories(foreignLectureIds);

    DevLog.add(
      '🧹 [LocalDataWipe] Removed $deleted row(s) belonging to other accounts '
      '(${foreignLectureIds.length} lecture dir(s), ${foreignFilePaths.length} file(s))',
    );
  }

  Future<void> _deleteUserDataDirectories() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      for (final name in _userDataDirNames) {
        final dir = Directory(p.join(docsDir.path, name));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    } catch (e) {
      // 消せなくても致命的ではない(DBの行は消えているので参照されない。
      // 単にディスク容量が残るだけ)。
      DevLog.add('⚠️ [LocalDataWipe] Failed to delete user data directories: $e');
    }
  }

  Future<void> _deleteLectureDirectories(Set<String> lectureIds) async {
    if (lectureIds.isEmpty) return;
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      for (final lectureId in lectureIds) {
        final dir = Directory(p.join(docsDir.path, 'lectures', lectureId));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    } catch (e) {
      DevLog.add('⚠️ [LocalDataWipe] Failed to delete lecture directories: $e');
    }
  }

  Future<void> _deleteFiles(Set<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // 個別ファイルの削除失敗は無視(容量が残るだけ)。
      }
    }
  }
}
