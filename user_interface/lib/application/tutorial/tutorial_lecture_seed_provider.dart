// lib/application/tutorial/tutorial_lecture_seed_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:lefture/application/auth/auth_provider.dart';
import 'package:lefture/application/course/default_course_service.dart';
import 'package:lefture/application/job/job_providers.dart';
import 'package:lefture/application/profile/display_language_controller.dart';
import 'package:lefture/application/sync/announcement_sync_service.dart';
import 'package:lefture/application/sync/course_sync_service.dart';
import 'package:lefture/application/sync/deep_note_sync_service.dart';
import 'package:lefture/application/sync/fun_fact_sync_service.dart';
import 'package:lefture/application/sync/keyword_sync_service.dart';
import 'package:lefture/application/sync/lecture_sync_service.dart';
import 'package:lefture/application/sync/lecture_topic_sync_service.dart';
import 'package:lefture/application/sync/review_card_sync_service.dart';
import 'package:lefture/application/tutorial/tutorial_lecture_seed_service.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:lefture/infrastructure/supabase/repositories/course_repository_supabase.dart';

import 'package:lefture/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';

part 'tutorial_lecture_seed_provider.g.dart';

/// ログイン中ユーザーに、既定コース(本物のSupabase同期コース)とチュートリアル
/// 講義(Cloud生成、Supabase同期)が揃っているか確認し、無ければ用意する。
/// currentUserProviderをwatchしているため、ログイン/ログアウト/ユーザー
/// 切り替えのたびに再評価され、冪等チェックも都度やり直される。
///
/// チュートリアル講義の実体は`/seed-tutorial`(lefture_backend)がユーザーの
/// 最初のDisplay言語に合わせてSupabaseへ投入する。既にローカルに(旧ローカル
/// 生成方式で)チュートリアル講義を持つ既存ユーザーには何もしない —
/// そのユーザーは従来通りローカル限定のチュートリアルを使い続ける。
///
/// 既定コースの確保・チュートリアル投入・Pull同期はいずれもネットワーク呼び
/// 出しを伴うため、オフライン時は今回の起動では諦める。この場合チュートリアル
/// 講義のシード自体もスキップし、次回起動時(オンラインになったタイミング)に
/// 再試行する。
@riverpod
Future<void> tutorialLectureSeed(Ref ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return;

  final languageCode = ref.watch(displayLanguageControllerProvider);
  final courseRepo = ref.watch(courseRepositoryProvider);
  final userProfileRepo = ref.watch(userProfileRepositoryProvider);
  final db = ref.watch(appDatabaseProvider);

  await TutorialLectureSeedService(db).cleanupOrphanedLocalTutorialCourses(user.id);

  // 既存ユーザー(旧ローカル生成方式で既にチュートリアル講義を持つ)には
  // 何もしない。新規ユーザーのみCloud化する。
  final existingTutorial = await db.findTutorialLecture(user.id);
  if (existingTutorial != null) return;

  final courseId = await DefaultCourseService(courseRepo).ensureDefaultCourse(
    defaultCourseTitle: TutorialLectureSeedService.defaultCourseTitle(languageCode),
    defaultCourseSummary: TutorialLectureSeedService.defaultCourseSummary(languageCode),
  );
  if (courseId == null) return;

  // Supabase上で確保/新規作成した既定コースをローカルDB(Drift)へ即座に同期。
  // これにより初回起動直後にRecordingPage等を開いても、ローカルDBの
  // courseListProviderから既定コースが正しく取得・表示される。
  await CourseSyncService(db).pull();

  final tutorialCreatedAt = await userProfileRepo.ensureTutorialCreatedAt();

  try {
    await ref.watch(jobRepositoryProvider).seedTutorial(
          courseId: courseId,
          displayLanguageCode: languageCode,
          lectureDatetime: tutorialCreatedAt,
        );
  } catch (e, stack) {
    DevLog.add('⚠️ [TutorialSeed] Cloud seed failed: $e\n$stack');
    return;
  }

  // サーバー側で作られたチュートリアル講義一式を、通常講義と同じPull同期で
  // ローカルへ反映する(lecture_controller.dartの一括Pullと同じ経路)。
  await Future.wait([
    LectureSyncService(db).pull(),
    LectureTopicSyncService(db).pull(),
    DeepNoteSyncService(db).pull(),
    ReviewCardSyncService(db).pull(),
    KeywordSyncService(db).pull(),
    FunFactSyncService(db).pull(),
    AnnouncementSyncService(db).pull(),
  ]);
}
