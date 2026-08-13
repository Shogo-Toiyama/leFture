// lib/application/tutorial/tutorial_lecture_seed_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:lefture/application/auth/auth_provider.dart';
import 'package:lefture/application/course/default_course_service.dart';
import 'package:lefture/application/profile/display_language_controller.dart';
import 'package:lefture/application/tutorial/tutorial_lecture_seed_service.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:lefture/infrastructure/supabase/repositories/course_repository_supabase.dart';

part 'tutorial_lecture_seed_provider.g.dart';

/// ログイン中ユーザーに、既定コース(本物のSupabase同期コース)とチュートリアル
/// 講義(ローカル限定)が揃っているか確認し、無ければ用意する。
/// currentUserProviderをwatchしているため、ログイン/ログアウト/ユーザー
/// 切り替えのたびに再評価され、冪等チェックも都度やり直される。
///
/// 既定コースの確保はSupabaseへのネットワーク呼び出しを伴うため、オフライン時は
/// 今回の起動では諦める(DefaultCourseServiceがnullを返す)。この場合チュートリアル
/// 講義のシード自体もスキップし、次回起動時(オンラインになったタイミング)に
/// 再試行する。
@riverpod
Future<void> tutorialLectureSeed(Ref ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return;

  final languageCode = ref.watch(displayLanguageControllerProvider);
  final courseRepo = ref.watch(courseRepositoryProvider);

  final courseId = await DefaultCourseService(courseRepo).ensureDefaultCourse(
    defaultCourseTitle: TutorialLectureSeedService.defaultCourseTitle(languageCode),
    defaultCourseSummary: TutorialLectureSeedService.defaultCourseSummary(languageCode),
  );
  if (courseId == null) return;

  final db = ref.watch(appDatabaseProvider);
  await TutorialLectureSeedService(db).seedIfNeeded(
    userId: user.id,
    displayLanguageCode: languageCode,
    courseId: courseId,
  );
}
