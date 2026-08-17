// lib/application/tutorial/tutorial_lecture_seed_service.dart
//
// 全ユーザーが常に最低1件、削除できない「チュートリアル講義」を持てるように、
// ローカルDBのみに完結する形でシードするサービス。
//
// - 講義自体はSupabaseには一切書き込まない(リポジトリの更新メソッド/
//   enqueueOutboxを経由せず、Driftへ直接insertする)。これにより、この
//   講義データが誤ってサーバーへpushされることも、他デバイスと同期される
//   こともない。
// - 所属先のコース(courseId)だけは本物のSupabase同期コース(既定コース、
//   DefaultCourseServiceが確保する)を指す。理由はdefault_course_service.dart
//   参照。ローカル限定コースだとcourseListProviderがSupabase直参照のため、
//   一生 course == null のスピナーになってしまう不具合があった。
// - 非削除対象であることは新しいカラムではなく、既存のmetadataJsonに
//   {"is_tutorial": true, "tutorial_version": 2} を仕込むことで表現する(スキーマ変更不要)。
// - 冪等: 既に is_tutorial な行が存在すれば、courseIdが最新かどうか、および
//   displayLanguageやtutorial_versionが最新か確認し、更新があれば自動的に最新コンテンツで再シードする。
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/l10n/tutorial/tutorial_content.dart';

class TutorialLectureSeedService {
  TutorialLectureSeedService(this._db);

  final AppDatabase _db;

  static const _uuid = Uuid();
  static const int kTutorialVersion = 5;

  /// 既定コース(DefaultCourseServiceが確保する、チュートリアル講義兼メモ用の
  /// 常設コース)のタイトル。チュートリアル文言と同じ言語マップから引くことで
  /// 文言の置き場所を1箇所に保つ。
  static String defaultCourseTitle(String languageCode) {
    return getTutorialContent(languageCode).courseTitle;
  }

  static String defaultCourseSummary(String languageCode) {
    return getTutorialContent(languageCode).courseSummary;
  }

  Future<LocalLecture?> _findTutorialLecture(String userId) async {
    final rows = await (_db.select(
      _db.localLectures,
    )..where((t) => t.userId.equals(userId))).get();

    for (final row in rows) {
      if (row.metadataJson == null) continue;
      final decoded = jsonDecode(row.metadataJson!);
      if (decoded is Map && decoded['is_tutorial'] == true) return row;
    }
    return null;
  }

  /// 実装初期の一時期、コースもローカル限定で作っていた名残(CoursePageが
  /// 一生ロード中になる不具合の原因)。既定コースへの移行時に掃除する。
  Future<void> _cleanupOrphanedLocalTutorialCourses(String userId) async {
    final rows = await (_db.select(
      _db.localCourses,
    )..where((t) => t.userId.equals(userId))).get();

    for (final row in rows) {
      if (row.metadataJson == null) continue;
      final decoded = jsonDecode(row.metadataJson!);
      if (decoded is Map && decoded['is_tutorial'] == true) {
        await (_db.delete(
          _db.localCourses,
        )..where((t) => t.id.equals(row.id) & t.userId.equals(userId))).go();
        DevLog.add('🧹 [TutorialSeed] Removed orphaned local-only tutorial course: ${row.id}');
      }
    }
  }

  Future<void> seedIfNeeded({
    required String userId,
    required String displayLanguageCode,
    required String courseId,
    bool hasCompletedTutorial = false,
  }) async {
    try {
      await _cleanupOrphanedLocalTutorialCourses(userId);

      final existing = await _findTutorialLecture(userId);
      final content = getTutorialContent(displayLanguageCode);
      final now = DateTime.now().toUtc();

      if (existing != null) {
        int existingVersion = 0;
        if (existing.metadataJson != null) {
          try {
            final decoded = jsonDecode(existing.metadataJson!);
            if (decoded is Map && decoded['tutorial_version'] is int) {
              existingVersion = decoded['tutorial_version'] as int;
            }
          } catch (_) {}
        }

        final needsCourseBackfill = existing.courseId != courseId;
        final needsLanguageUpdate = existing.displayLanguage != displayLanguageCode;
        final needsVersionUpdate = existingVersion < kTutorialVersion;
        final needsAccessedBackfill = hasCompletedTutorial && existing.lastAccessedAt == null;

        if (needsLanguageUpdate || needsVersionUpdate) {
          DevLog.add(
            '🎓 [TutorialSeed] Refreshing tutorial lecture: '
            'lang(${existing.displayLanguage} -> $displayLanguageCode), '
            'ver($existingVersion -> $kTutorialVersion)',
          );

          await _db.transaction(() async {
            // 講義自体のタイトル・サマリー・言語・コースID・メタデータを更新
            await (_db.update(_db.localLectures)
                  ..where((t) => t.id.equals(existing.id) & t.userId.equals(userId)))
                .write(
              LocalLecturesCompanion(
                title: Value(content.lectureTitle),
                summary: Value(content.lectureSummary),
                displayLanguage: Value(displayLanguageCode),
                courseId: Value(courseId),
                lastAccessedAt: needsAccessedBackfill ? Value(now) : const Value.absent(),
                metadataJson: Value(
                  jsonEncode({
                    'is_tutorial': true,
                    'tutorial_version': kTutorialVersion,
                  }),
                ),
                updatedAt: Value(now),
              ),
            );

            // 以前のサブ要素を削除
            await (_db.delete(_db.localLectureTopics)..where((t) => t.lectureId.equals(existing.id))).go();
            await (_db.delete(_db.localDeepNotes)..where((t) => t.lectureId.equals(existing.id))).go();
            await (_db.delete(_db.localKeywords)..where((t) => t.lectureId.equals(existing.id))).go();
            await (_db.delete(_db.localReviewCards)..where((t) => t.lectureId.equals(existing.id))).go();
            await (_db.delete(_db.localFunFacts)..where((t) => t.lectureId.equals(existing.id))).go();
            await (_db.delete(_db.localAnnouncements)..where((t) => t.lectureId.equals(existing.id))).go();

            // 新しいコンテンツのサブ要素を生成・挿入
            await _insertSubContent(
              userId: userId,
              lectureId: existing.id,
              content: content,
              now: now,
              // 再シードでもアナウンスメントの「作成日時」は講義の作成日時
              // (=初回シード時刻)に固定する。nowを入れてしまうと講義自体は
              // 最古のままなのにアナウンスだけ最新扱いになり、一覧の先頭に
              // 浮上してしまう(_insertSubContentのコメント参照)。
              announcementBaseAt: existing.createdAt,
            );
          });
          return;
        }

        if (needsCourseBackfill || needsAccessedBackfill) {
          await (_db.update(_db.localLectures)
                ..where((t) => t.id.equals(existing.id) & t.userId.equals(userId)))
              .write(LocalLecturesCompanion(
            courseId: needsCourseBackfill ? Value(courseId) : const Value.absent(),
            lastAccessedAt: needsAccessedBackfill ? Value(now) : const Value.absent(),
          ));
          DevLog.add('🎓 [TutorialSeed] Backfilled tutorial lecture (courseId: $courseId, accessed: $needsAccessedBackfill)');
        }

        await _backfillAnnouncementTimestamps(userId: userId, lecture: existing);
        return;
      }

      final lectureId = _uuid.v4();
      final tutorialMetadata = jsonEncode({
        'is_tutorial': true,
        'tutorial_version': kTutorialVersion,
      });

      final lectureCompanion = LocalLecturesCompanion.insert(
        id: lectureId,
        userId: userId,
        courseId: Value(courseId),
        title: Value(content.lectureTitle),
        summary: Value(content.lectureSummary),
        metadataJson: Value(tutorialMetadata),
        lectureDatetime: Value(now),
        lastAccessedAt: hasCompletedTutorial ? Value(now) : const Value.absent(),
        createdAt: Value(now),
        updatedAt: Value(now),
        autoStartAnalysis: const Value(false),
        isRealtime: const Value(false),
        displayLanguage: Value(displayLanguageCode),
      );

      await _db.transaction(() async {
        await _db.into(_db.localLectures).insert(lectureCompanion);
        await _insertSubContent(
          userId: userId,
          lectureId: lectureId,
          content: content,
          now: now,
          announcementBaseAt: now, // 講義のcreatedAtと同じ
        );
      });

      DevLog.add('🎓 [TutorialSeed] Seeded tutorial lecture for user $userId ($displayLanguageCode)');
    } catch (e, stack) {
      DevLog.add('⚠️ [TutorialSeed] Seed failed: $e\n$stack');
    }
  }

  /// 過去バージョンのシードは、アナウンスメントの`createdAt`に「(再)シードを
  /// 実行した時刻」を入れていた。講義行のcreatedAtは再シードでも書き換えない
  /// ため、tutorial_versionを上げたり表示言語を切り替えた既存ユーザーでは
  /// 「講義は一番古いのに、そのアナウンスだけ最新」という状態になり、
  /// createdAt降順のアナウンス一覧で実際の講義のものより上に居座っていた。
  ///
  /// 完了状態(completedAt)を消したくないので再シードはせず、日時だけを講義の
  /// createdAt基準へ振り直す。
  Future<void> _backfillAnnouncementTimestamps({
    required String userId,
    required LocalLecture lecture,
  }) async {
    final rows = await (_db.select(_db.localAnnouncements)
          ..where((t) => t.lectureId.equals(lecture.id) & t.userId.equals(userId)))
        .get();
    if (rows.isEmpty) return;

    // 初回シード時は講義と同時刻(+定義順の数秒)になるため、1分の余裕を見て
    // 「明らかに講義より後」の場合だけ振り直す(毎起動の無駄な書き込み防止)。
    final threshold = lecture.createdAt.add(const Duration(minutes: 1));
    if (!rows.any((r) => r.createdAt.isAfter(threshold))) return;

    // tutorial_content上の定義順(`ann_1`, `ann_2`, ...)を保って振り直す。
    final ordered = [...rows]..sort((a, b) => a.id.compareTo(b.id));
    for (var i = 0; i < ordered.length; i++) {
      await (_db.update(_db.localAnnouncements)
            ..where((t) => t.id.equals(ordered[i].id) & t.userId.equals(userId)))
          .write(
        LocalAnnouncementsCompanion(
          createdAt: Value(lecture.createdAt.add(Duration(seconds: i))),
        ),
      );
    }

    DevLog.add(
      '🎓 [TutorialSeed] Backfilled ${ordered.length} announcement timestamp(s) '
      'to lecture createdAt (${lecture.createdAt.toIso8601String()})',
    );
  }

  Future<void> _insertSubContent({
    required String userId,
    required String lectureId,
    required TutorialContent content,
    required DateTime now,

    /// アナウンスメントの`createdAt`の基準時刻。
    ///
    /// アナウンスメント一覧はcreatedAtの降順で並ぶ
    /// (announcement_repository_drift.dart参照)。ここにnowを入れると、
    /// tutorial_versionの更新や表示言語の切り替えで再シードが走るたびに
    /// 「講義自体は最古のまま、アナウンスだけ今日作られた」状態になり、
    /// チュートリアルのアナウンスが実際の講義のものより上に居座ってしまう。
    /// そのため講義のcreatedAtを渡してもらう。
    required DateTime announcementBaseAt,
  }) async {
    final topicCompanions = <LocalLectureTopicsCompanion>[];
    final deepNoteCompanions = <LocalDeepNotesCompanion>[];
    final reviewCardCompanions = <LocalReviewCardsCompanion>[];

    for (final topic in content.topics) {
      final topicId = _uuid.v4();
      topicCompanions.add(
        LocalLectureTopicsCompanion.insert(
          id: topicId,
          userId: userId,
          lectureId: lectureId,
          topicIndex: topic.topicIndex,
          topicTitle: topic.title,
          topicType: 'concept',
          imagePath: Value('assets/images/tutorial/topic_${topic.topicIndex}.jpg'),
          summary: Value(topic.summary),
          createdAt: now,
          updatedAt: now,
        ),
      );

      deepNoteCompanions.add(
        LocalDeepNotesCompanion.insert(
          id: _uuid.v4(),
          userId: userId,
          lectureId: lectureId,
          topicNumber: topic.topicIndex,
          noteContents: topic.deepNoteMarkdown,
          createdAt: now,
          updatedAt: now,
        ),
      );

      for (final card in topic.reviewCards) {
        reviewCardCompanions.add(
          LocalReviewCardsCompanion.insert(
            id: _uuid.v4(),
            userId: userId,
            lectureId: lectureId,
            topicNumber: topic.topicIndex,
            cardContentJson: jsonEncode(card.contentBlocks),
            cardType: card.cardType,
            title: Value(card.title),
            heroEmoji: Value(card.heroEmoji),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    }

    final keywordCompanions = content.keywords
        .map(
          (k) => LocalKeywordsCompanion.insert(
            id: _uuid.v4(),
            userId: userId,
            lectureId: lectureId,
            topicNumber: k.topicNumber,
            keyword: k.keyword,
            definition: k.definition ?? '',
            createdAt: now,
            updatedAt: now,
          ),
        )
        .toList();

    final funFactCompanion = LocalFunFactsCompanion.insert(
      id: _uuid.v4(),
      userId: userId,
      lectureId: lectureId,
      title: Value(content.funFact.title),
      hook: content.funFact.hook,
      body: content.funFact.body,
      metadataJson: Value(jsonEncode({'sources': content.funFact.sources})),
      createdAt: now,
      updatedAt: now,
    );

    // 3件が同一時刻だとチュートリアル内での並び順まで不定になるため、
    // 定義順に1秒ずつずらして固定する(講義内一覧は昇順=ann_1が先頭)。
    final announcementCompanions = <LocalAnnouncementsCompanion>[];
    for (var i = 0; i < content.announcements.length; i++) {
      final a = content.announcements[i];
      announcementCompanions.add(
        LocalAnnouncementsCompanion.insert(
          id: a.id,
          userId: userId,
          lectureId: lectureId,
          type: a.type,
          title: a.content,
          createdAt: Value(announcementBaseAt.add(Duration(seconds: i))),
          updatedAt: Value(now),
        ),
      );
    }

    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(_db.localLectureTopics, topicCompanions);
      batch.insertAllOnConflictUpdate(_db.localDeepNotes, deepNoteCompanions);
      batch.insertAllOnConflictUpdate(_db.localReviewCards, reviewCardCompanions);
      batch.insertAllOnConflictUpdate(_db.localKeywords, keywordCompanions);
      batch.insertAllOnConflictUpdate(_db.localFunFacts, [funFactCompanion]);
      batch.insertAllOnConflictUpdate(_db.localAnnouncements, announcementCompanions);
    });
  }
}
