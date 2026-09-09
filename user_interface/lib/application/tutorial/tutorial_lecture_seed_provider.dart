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
/// 最初のDisplay言語に合わせてSupabaseへ投入する。既存ユーザー(移行前から
/// このアプリを使っている、またはローカルに旧ローカル生成方式のチュートリアル
/// を持つ)には新規作成しない — 判定方法は下記コメント参照。
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

  final courseId = await DefaultCourseService(courseRepo).ensureDefaultCourse(
    defaultCourseTitle: TutorialLectureSeedService.defaultCourseTitle(languageCode),
    defaultCourseSummary: TutorialLectureSeedService.defaultCourseSummary(languageCode),
  );
  if (courseId == null) return;

  // Supabase上で確保/新規作成した既定コースをローカルDB(Drift)へ即座に同期。
  // これにより初回起動直後にRecordingPage等を開いても、ローカルDBの
  // courseListProviderから既定コースが正しく取得・表示される。
  await CourseSyncService(db).pull();

  // 既にローカルにチュートリアル講義があるなら(旧ローカル生成方式の既存
  // ユーザー、または既にCloudから同期済み)何もしない。
  //
  // ★ これだけでは「既存ユーザー判定」として不十分 —— サインアウトは
  // ローカルDBを丸ごとwipeするため(sign_out_flow.dart)、旧ローカル限定の
  // チュートリアルしか持たない既存ユーザーがサインアウト後に再サインインすると
  // ここは必ずnullになり、Cloud新規作成の対象に見えてしまう(実際に発生した
  // 不具合)。そこで下のtutorial_created_atの判定を本当のゲートとして使う。
  final existingTutorial = await db.findTutorialLecture(user.id);
  if (existingTutorial != null) return;

  // tutorial_created_atは移行前からこのメソッドで発行され続けているため、
  // 「今回初めて発行された(wasAlreadySet == false)」場合だけが真に新規
  // ユーザー。既存ユーザーは(ローカルDBがwipe済みでも)ほぼ確実にtrueになり、
  // その場合はCloudにも新規作成しない。
  //
  // ★ nullは「サーバーに確認できなかった(オフライン/タイムアウト)ので、
  // 新規かどうか分からない」という意味。ここで作成に進んでしまうと、旧
  // ローカル限定チュートリアルしか持たない既存ユーザーが接続不良の別端末で
  // 誤ってCloud新規作成の対象になり得るため、フェイルセーフとして今回は
  // 何もせず諦める(次回起動時、接続が戻っていれば再評価される)。
  final tutorialTiming = await userProfileRepo.ensureTutorialCreatedAt();
  if (tutorialTiming == null || tutorialTiming.wasAlreadySet) return;

  try {
    await ref.watch(jobRepositoryProvider).seedTutorial(
          courseId: courseId,
          displayLanguageCode: languageCode,
          lectureDatetime: tutorialTiming.createdAt,
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
