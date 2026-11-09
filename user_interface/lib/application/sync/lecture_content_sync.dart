import 'package:drift/drift.dart';
import 'package:lefture/application/sync/announcement_sync_service.dart';
import 'package:lefture/application/sync/deep_note_sync_service.dart';
import 'package:lefture/application/sync/fun_fact_sync_service.dart';
import 'package:lefture/application/sync/keyword_sync_service.dart';
import 'package:lefture/application/sync/lecture_topic_sync_service.dart';
import 'package:lefture/application/sync/review_card_sync_service.dart';
import 'package:lefture/core/utils/connectivity_utils.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/repositories/lecture_artifact_repository.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

/// 講義単位で子データ(トピック/Deep Note/復習カード/キーワード/Fun Fact/
/// お知らせ)を取り直すサービス。
///
/// 起動時の全件Pullは直近講義([RecentLectureScope])だけなので、それより
/// 古い講義の中身は、その講義を開いた時にここで取る。ローカルに残っている
/// データは捨てない — 最後に取り直してから[freshness]以内ならそのまま使い、
/// 古ければ取り直して入れ替える(サーバー側で消えた行はこの時に消える)。
///
/// 取り直した時刻は講義ごとにSyncCursors(`lecture_content:<id>`)へ記録する
/// ([AppDatabase.markLectureContentFetched])。
class LectureContentSync {
  LectureContentSync(this._db);

  final AppDatabase _db;

  static const Duration freshness = Duration(hours: 24);

  /// 子データのエンティティ。起動時の全件Pullでこれらが全て直近講義の範囲で
  /// 成功した時だけ、直近講義を「取得済み」と記録する。
  static const List<String> contentEntityTypes = [
    LectureTopicSyncService.entityType,
    DeepNoteSyncService.entityType,
    ReviewCardSyncService.entityType,
    KeywordSyncService.entityType,
    FunFactSyncService.entityType,
    AnnouncementSyncService.entityType,
  ];

  /// 同じ講義の取り直しが同時に何度も走らないよう、講義IDごとの進行中の
  /// 取得を共有する(左右スワイプで同じ講義が何度もビルドされるため)。
  static final Map<String, Future<void>> _inFlight = {};

  /// [lectureIds]のうち、取り直してから[freshness]を過ぎた(または一度も
  /// 取っていない)講義だけを取り直す。講義を開いた時用。
  Future<void> ensureFresh(List<String> lectureIds) => _run(lectureIds, force: false);

  /// [lectureIds]を必ず取り直す。明示的なリロード・解析完了時用。
  Future<void> refresh(List<String> lectureIds) => _run(lectureIds, force: true);

  /// 起動時の全件Pullで直近講義の子データを取り直した時に、それらを
  /// 「取得済み」と記録する。
  Future<void> markFetched(List<String> lectureIds, DateTime fetchedAt) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    await _db.markLectureContentFetched(uid, lectureIds, fetchedAt);
  }

  Future<void> _run(List<String> lectureIds, {required bool force}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final candidates = await _excludeLocalOnly(lectureIds.toSet().toList());
    if (candidates.isEmpty) return;

    final List<String> targets;
    if (force) {
      targets = candidates;
    } else {
      final fetchedAt = await _db.getLectureContentFetchedAt(uid, candidates);
      final now = DateTime.now().toUtc();
      targets = [
        for (final id in candidates)
          if (fetchedAt[id] == null || now.difference(fetchedAt[id]!) >= freshness) id,
      ];
    }
    if (targets.isEmpty) return;
    // オフラインならローカルにある分をそのまま使う(取りに行くとタイムアウト
    // まで裏で待ち続けるだけになる)。次に開いた時にもう一度判定する。
    if (!await isDeviceOnline()) return;

    final waits = <Future<void>>[];
    final toPull = <String>[];
    for (final id in targets) {
      final running = _inFlight[id];
      if (running != null) {
        waits.add(running);
      } else {
        toPull.add(id);
      }
    }

    if (toPull.isNotEmpty) {
      final future = _pull(uid, toPull);
      for (final id in toPull) {
        _inFlight[id] = future;
      }
      waits.add(future.whenComplete(() {
        for (final id in toPull) {
          if (identical(_inFlight[id], future)) _inFlight.remove(id);
        }
      }));
    }
    await Future.wait(waits);
  }

  /// サーバーに実体が無い講義(旧方式のチュートリアル講義・まだ送信していない
  /// 録音など、syncStatus=='local_only')は除く。サーバーには行が無いので、
  /// 取り直すと「サーバーに無い行は消す」処理でローカルの中身を消してしまう。
  Future<List<String>> _excludeLocalOnly(List<String> lectureIds) async {
    if (lectureIds.isEmpty) return const [];
    final localOnly = await (_db.select(_db.localLectures)
          ..where((t) => t.id.isIn(lectureIds) & t.syncStatus.equals('local_only')))
        .map((r) => r.id)
        .get();
    if (localOnly.isEmpty) return lectureIds;
    final skip = localOnly.toSet();
    return lectureIds.where((id) => !skip.contains(id)).toList();
  }

  /// 失敗は呼び出し元へ投げずにログだけ残す(講義を開いた時は裏で走るため)。
  /// 全エンティティが成功した時だけ「取得済み」と記録する — 一部でも失敗
  /// したら、次に開いた時にもう一度取りに行く。
  Future<void> _pull(String uid, List<String> lectureIds) async {
    final startedAt = DateTime.now().toUtc();
    final pulls = <String, Future<void> Function()>{
      LectureTopicSyncService.entityType: () =>
          LectureTopicSyncService(_db).pullForLectures(lectureIds),
      DeepNoteSyncService.entityType: () =>
          DeepNoteSyncService(_db).pullForLectures(lectureIds),
      ReviewCardSyncService.entityType: () =>
          ReviewCardSyncService(_db).pullForLectures(lectureIds),
      KeywordSyncService.entityType: () =>
          KeywordSyncService(_db).pullForLectures(lectureIds),
      FunFactSyncService.entityType: () =>
          FunFactSyncService(_db).pullForLectures(lectureIds),
      AnnouncementSyncService.entityType: () =>
          AnnouncementSyncService(_db).pullForLectures(lectureIds),
    };

    var allOk = true;
    await Future.wait(pulls.entries.map((entry) async {
      try {
        await entry.value();
      } catch (e, st) {
        allOk = false;
        DevLog.add('⚠️ [LectureContentSync] ${entry.key} pull failed for $lectureIds: $e\n$st');
      }
    }));

    if (allOk) {
      await _db.markLectureContentFetched(uid, lectureIds, startedAt);
      DevLog.add('✅ [LectureContentSync] Refreshed content for ${lectureIds.length} lecture(s).');
    }
  }

  /// 講義ページを開いた時用。その講義と、左右にスワイプした先の講義
  /// (同じコースで授業日が隣の講義)の中身を、古ければ取り直す。
  /// 開いている講義を先に取り、隣はその後に取る。隣の講義はコラージュの
  /// 画像(元の画像)も先に落としておき、スワイプした瞬間に出るようにする
  /// (開いている講義の画像はコラージュ自身が取りに行く)。
  Future<void> ensureFreshWithNeighbors(String lectureId) async {
    await ensureFresh([lectureId]);
    try {
      final neighbors = await _neighborLectureIds(lectureId);
      if (neighbors.isEmpty) return;
      await ensureFresh(neighbors);
      await _prefetchCollageImages(neighbors);
    } catch (e, st) {
      DevLog.add('⚠️ [LectureContentSync] Neighbor prefetch skipped for $lectureId: $e\n$st');
    }
  }

  /// コラージュに出る画像(トピック番号順に最大[_collageImageCount]枚)を
  /// 端末のキャッシュへ落としておく。既にキャッシュにあれば通信しない。
  /// 失敗(未生成・オフライン等)は無視する — 表示時にもう一度取りに行くため。
  static const int _collageImageCount = 6;

  Future<void> _prefetchCollageImages(List<String> lectureIds) async {
    final rows = await (_db.select(_db.localLectureTopics)
          ..where((t) =>
              t.lectureId.isIn(lectureIds) &
              t.deletedAt.isNull() &
              t.imagePath.isNotNull())
          ..orderBy([(t) => OrderingTerm(expression: t.topicIndex)]))
        .get();
    final byLecture = <String, List<String>>{};
    for (final r in rows) {
      final path = r.imagePath!;
      if (path.trim().isEmpty || path.startsWith('assets/')) continue;
      final list = byLecture.putIfAbsent(r.lectureId, () => []);
      if (list.length < _collageImageCount) list.add(path);
    }
    final repo = LectureArtifactRepository(supabase, _db);
    for (final paths in byLecture.values) {
      await Future.wait(paths.map((p) async {
        try {
          await repo.getArtifactFile(p);
        } catch (_) {}
      }));
    }
  }

  /// LectureViewerPageのスワイプ順(同じコースの講義を授業日の昇順)で、
  /// [lectureId]の前後の講義ID。
  Future<List<String>> _neighborLectureIds(String lectureId) async {
    final lecture = await (_db.select(_db.localLectures)
          ..where((t) => t.id.equals(lectureId)))
        .getSingleOrNull();
    final courseId = lecture?.courseId;
    if (lecture == null || courseId == null) return const [];

    final siblings = await (_db.select(_db.localLectures)
          ..where((t) =>
              t.userId.equals(lecture.userId) &
              t.courseId.equals(courseId) &
              t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.lectureDatetime)]))
        .map((r) => r.id)
        .get();
    final index = siblings.indexOf(lectureId);
    if (index == -1) return const [];
    return [
      if (index > 0) siblings[index - 1],
      if (index < siblings.length - 1) siblings[index + 1],
    ];
  }
}
