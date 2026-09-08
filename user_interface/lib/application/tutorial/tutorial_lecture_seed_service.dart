// lib/application/tutorial/tutorial_lecture_seed_service.dart
//
// チュートリアル講義自体はバックエンドの`/seed-tutorial`がCloud側(Supabase)へ
// 投入し、クライアントは通常講義と同じPull同期で受け取るだけになった
// (tutorial_lecture_seed_provider.dart参照)。このクラスには、その移行後も
// 引き続き必要な小さなヘルパーだけを残す。
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';

/// 既定コース(DefaultCourseServiceが確保する、チュートリアル講義兼メモ用の
/// 常設コース)のタイトル・サマリー。チュートリアル講義自体の文言は
/// バックエンド(lefture_backend/app/services/tutorial_content.py)へ移管済み
/// だが、既定コースはクライアントが直接Supabaseへ作成するため、この2文だけは
/// クライアント側にも残す。
const Map<String, ({String title, String summary})> _kDefaultCourseText = {
  'ja': (
    title: '使い方・メモ',
    summary: 'leFtureの使い方や、コースを作るまでもない一発ものの録音をまとめておく場所です。',
  ),
  'en': (
    title: 'Guide & Notes',
    summary:
        "Where the app tour lives, plus a home for one-off recordings that don't need their own course.",
  ),
};

class TutorialLectureSeedService {
  TutorialLectureSeedService(this._db);

  final AppDatabase _db;

  static String defaultCourseTitle(String languageCode) {
    return (_kDefaultCourseText[languageCode] ?? _kDefaultCourseText['en']!).title;
  }

  static String defaultCourseSummary(String languageCode) {
    return (_kDefaultCourseText[languageCode] ?? _kDefaultCourseText['en']!).summary;
  }

  /// 実装初期の一時期、コースもローカル限定で作っていた名残(CoursePageが
  /// 一生ロード中になる不具合の原因)。既定コースへの移行時に掃除する。
  /// 既存ユーザーに影響し得るため、Cloud移行後も引き続き実行する。
  Future<void> cleanupOrphanedLocalTutorialCourses(String userId) async {
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
}
