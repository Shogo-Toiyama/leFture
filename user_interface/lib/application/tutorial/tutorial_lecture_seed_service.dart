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
//   {"is_tutorial": true} を仕込むことで表現する(スキーマ変更不要)。
// - 冪等: 既に is_tutorial な行が存在すれば、courseIdが最新かどうかだけ
//   確認して(必要ならbackfillして)終了する。
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';

class TutorialLectureSeedService {
  TutorialLectureSeedService(this._db);

  final AppDatabase _db;

  static const _uuid = Uuid();

  /// 既定コース(DefaultCourseServiceが確保する、チュートリアル講義兼メモ用の
  /// 常設コース)のタイトル。チュートリアル文言と同じ言語マップから引くことで
  /// 文言の置き場所を1箇所に保つ。
  static String defaultCourseTitle(String languageCode) {
    return (languageCode == 'ja' ? _tutorialContentJa : _tutorialContentEn).courseTitle;
  }

  static String defaultCourseSummary(String languageCode) {
    return (languageCode == 'ja' ? _tutorialContentJa : _tutorialContentEn).courseSummary;
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
  }) async {
    try {
      await _cleanupOrphanedLocalTutorialCourses(userId);

      final existing = await _findTutorialLecture(userId);
      if (existing != null) {
        if (existing.courseId != courseId) {
          await (_db.update(_db.localLectures)
                ..where((t) => t.id.equals(existing.id) & t.userId.equals(userId)))
              .write(LocalLecturesCompanion(courseId: Value(courseId)));
          DevLog.add('🎓 [TutorialSeed] Backfilled tutorial lecture courseId -> $courseId');
        }
        return;
      }

      final content = _content(displayLanguageCode);
      final now = DateTime.now().toUtc();

      final lectureId = _uuid.v4();
      final tutorialMetadata = jsonEncode({'is_tutorial': true});

      final lectureCompanion = LocalLecturesCompanion.insert(
        id: lectureId,
        userId: userId,
        courseId: Value(courseId),
        title: Value(content.lectureTitle),
        summary: Value(content.lectureSummary),
        metadataJson: Value(tutorialMetadata),
        lectureDatetime: Value(now),
        createdAt: Value(now),
        updatedAt: Value(now),
        // 音声もジョブも存在しないので、自動解析は起動させない。
        autoStartAnalysis: const Value(false),
        isRealtime: const Value(false),
        displayLanguage: Value(displayLanguageCode),
        // lastAccessedAtはnullのままにする(HomePageの誘導コールアウトが
        // 「まだ一度も開かれていない」判定に使うため)。
      );

      final topicId = _uuid.v4();
      final topicCompanion = LocalLectureTopicsCompanion.insert(
        id: topicId,
        userId: userId,
        lectureId: lectureId,
        topicIndex: 1,
        topicTitle: content.topicTitle,
        topicType: 'concept',
        summary: Value(content.topicSummary),
        createdAt: now,
        updatedAt: now,
      );

      final deepNoteCompanion = LocalDeepNotesCompanion.insert(
        id: _uuid.v4(),
        userId: userId,
        lectureId: lectureId,
        topicNumber: 1,
        noteContents: content.deepNoteMarkdown,
        createdAt: now,
        updatedAt: now,
      );

      final keywordCompanions = content.keywords
          .map(
            (k) => LocalKeywordsCompanion.insert(
              id: _uuid.v4(),
              userId: userId,
              lectureId: lectureId,
              topicNumber: 1,
              keyword: k.keyword,
              definition: k.definition,
              createdAt: now,
              updatedAt: now,
            ),
          )
          .toList();

      final reviewCardCompanions = content.reviewCards
          .map(
            (c) => LocalReviewCardsCompanion.insert(
              id: _uuid.v4(),
              userId: userId,
              lectureId: lectureId,
              topicNumber: 1,
              cardContentJson: jsonEncode(c.cardContent),
              cardType: c.cardType,
              title: Value(c.title),
              heroEmoji: Value(c.heroEmoji),
              createdAt: now,
              updatedAt: now,
            ),
          )
          .toList();

      final funFactCompanions = content.funFacts
          .map(
            (f) => LocalFunFactsCompanion.insert(
              id: _uuid.v4(),
              userId: userId,
              lectureId: lectureId,
              hook: f.hook,
              body: f.body,
              createdAt: now,
              updatedAt: now,
            ),
          )
          .toList();

      await _db.transaction(() async {
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(_db.localLectures, [lectureCompanion]);
          batch.insertAllOnConflictUpdate(_db.localLectureTopics, [topicCompanion]);
          batch.insertAllOnConflictUpdate(_db.localDeepNotes, [deepNoteCompanion]);
          batch.insertAllOnConflictUpdate(_db.localKeywords, keywordCompanions);
          batch.insertAllOnConflictUpdate(_db.localReviewCards, reviewCardCompanions);
          batch.insertAllOnConflictUpdate(_db.localFunFacts, funFactCompanions);
        });
      });

      DevLog.add('🎓 [TutorialSeed] Seeded tutorial lecture for user $userId');
    } catch (e) {
      DevLog.add('⚠️ [TutorialSeed] Seed failed: $e');
    }
  }

  _TutorialContent _content(String languageCode) {
    return languageCode == 'ja' ? _tutorialContentJa : _tutorialContentEn;
  }
}

class _TutorialContent {
  const _TutorialContent({
    required this.courseTitle,
    required this.courseSummary,
    required this.lectureTitle,
    required this.lectureSummary,
    required this.topicTitle,
    required this.topicSummary,
    required this.deepNoteMarkdown,
    required this.keywords,
    required this.reviewCards,
    required this.funFacts,
  });

  final String courseTitle;
  final String courseSummary;
  final String lectureTitle;
  final String lectureSummary;
  final String topicTitle;
  final String topicSummary;
  final String deepNoteMarkdown;
  final List<_TutorialKeyword> keywords;
  final List<_TutorialReviewCard> reviewCards;
  final List<_TutorialFunFact> funFacts;
}

class _TutorialKeyword {
  const _TutorialKeyword(this.keyword, this.definition);
  final String keyword;
  final String definition;
}

class _TutorialReviewCard {
  const _TutorialReviewCard({
    required this.cardType,
    required this.title,
    required this.heroEmoji,
    required this.cardContent,
  });
  final String cardType;
  final String title;
  final String heroEmoji;
  final List<Map<String, dynamic>> cardContent;
}

class _TutorialFunFact {
  const _TutorialFunFact(this.hook, this.body);
  final String hook;
  final String body;
}

// 実際の文言は後日差し替え予定。ここでは構造(必須フィールド/枚数)が
// 正しいプレースホルダーのみを用意する。
const _tutorialContentJa = _TutorialContent(
  courseTitle: '使い方・メモ',
  courseSummary: 'leFtureの使い方や、コースを作るまでもない一発ものの録音をまとめておく場所です。',
  lectureTitle: 'leFtureへようこそ',
  lectureSummary:
      'この講義は録音済みの実例として、サマリー・トピック・レビューカード・ディープノート・'
      'FunFactなど、講義ページで見られる要素を一通り紹介するために用意されています。',
  topicTitle: 'アプリでできること',
  topicSummary: '録音した講義がどのように整理され、復習しやすい形になるかを見てみましょう。',
  deepNoteMarkdown:
      '# アプリでできること\n\n'
      'leFtureは録音した講義を自動で整理し、要約・キーワード・復習カードなどに変換します。\n\n'
      '- この画面のようにトピックごとに内容がまとまります\n'
      '- わからない用語はキーワード一覧で確認できます\n'
      '- 復習カードで要点を素早く振り返れます',
  keywords: [
    _TutorialKeyword('レビューカード', '講義の要点を1枚ずつ振り返れる復習用のカードです。'),
    _TutorialKeyword('ディープノート', 'トピックごとの内容を詳しくまとめたノートです。'),
  ],
  reviewCards: [
    _TutorialReviewCard(
      cardType: 'hook',
      title: 'このアプリでできること',
      heroEmoji: '🎓',
      cardContent: [
        {
          'type': 'text',
          'text': '講義を録音するだけで、要約やキーワード、復習カードが自動で作られます。',
        },
      ],
    ),
    _TutorialReviewCard(
      cardType: 'next_action',
      title: '次にやってみること',
      heroEmoji: '🚀',
      cardContent: [
        {
          'type': 'text',
          'text': 'まずは1つ、実際の講義を録音してみましょう。',
        },
      ],
    ),
  ],
  funFacts: [
    _TutorialFunFact(
      '知ってた?',
      'この講義はサンプルデータなので、削除できません。実際の講義を録音すると、'
          'すぐ隣に新しい講義カードが並びます。',
    ),
  ],
);

const _tutorialContentEn = _TutorialContent(
  courseTitle: 'Guide & Notes',
  courseSummary: 'Where the app tour lives, plus a home for one-off recordings that don\'t need their own course.',
  lectureTitle: 'Welcome to leFture',
  lectureSummary:
      'This lecture is a pre-made example that walks through everything you\'ll see on a '
      'real lecture page: summary, topics, review cards, deep notes, and fun facts.',
  topicTitle: 'What this app can do',
  topicSummary: 'See how a recorded lecture gets organized into something easy to review.',
  deepNoteMarkdown:
      '# What this app can do\n\n'
      'leFture automatically organizes your recorded lectures into summaries, keywords, '
      'and review cards.\n\n'
      '- Content is grouped by topic, just like this screen\n'
      '- Unfamiliar terms show up in the keyword list\n'
      '- Review cards let you go over the key points quickly',
  keywords: [
    _TutorialKeyword('Review Card', 'A quick-reference card that recaps one key point from a lecture.'),
    _TutorialKeyword('Deep Note', 'A detailed, per-topic write-up of the lecture content.'),
  ],
  reviewCards: [
    _TutorialReviewCard(
      cardType: 'hook',
      title: 'What this app can do',
      heroEmoji: '🎓',
      cardContent: [
        {
          'type': 'text',
          'text': 'Just record a lecture, and a summary, keywords, and review cards are generated automatically.',
        },
      ],
    ),
    _TutorialReviewCard(
      cardType: 'next_action',
      title: 'Try it yourself',
      heroEmoji: '🚀',
      cardContent: [
        {
          'type': 'text',
          'text': 'Record your first real lecture to see it in action.',
        },
      ],
    ),
  ],
  funFacts: [
    _TutorialFunFact(
      'Did you know?',
      'This lecture is sample data, so it can\'t be deleted. Once you record a real '
          'lecture, it\'ll show up right alongside it.',
    ),
  ],
);
