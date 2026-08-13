// lib/application/course/default_course_service.dart
//
// 全ユーザーが必ず持つ「既定コース」(削除不可)を確保するサービス。
// チュートリアル講義の置き場所であると同時に、一発もののセミナーや音声ガイド
// など「わざわざコースを作るまでもない」講義の受け皿(メモ用コース)も兼ねる。
//
// チュートリアル講義自体はローカル限定(Supabaseに存在しない)だが、この
// コースは通常のコース作成と全く同じ経路(CourseRepositorySupabase)で
// 本物のSupabase行として作る。理由: 将来ここに本物の録音講義が置かれた時、
// その講義は普通にSupabaseへpushされるため、参照先のコースがSupabase上に
// 実在しないと、コース詳細取得やTopicMap生成などコース単位のサーバー機能が
// 軒並み動かなくなる(courseListProviderもSupabase直参照で、ローカル限定
// コースは絶対に一覧に出てこない)。
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/supabase/repositories/course_repository_supabase.dart';

class DefaultCourseService {
  DefaultCourseService(this._courseRepo);

  final CourseRepositorySupabase _courseRepo;

  /// 既定コースのidを返す。既にあればそれを、無ければ作成して返す。
  /// オフライン等で確認/作成に失敗した場合はnullを返す(呼び出し元は
  /// 今回の起動では諦めて、次回起動時に再試行される)。
  Future<String?> ensureDefaultCourse({
    required String defaultCourseTitle,
    String? defaultCourseSummary,
  }) async {
    try {
      final courses = await _courseRepo.listCourses();
      for (final c in courses) {
        if (c.metadata?['is_default'] == true) return c.id;
      }

      final created = await _courseRepo.createCourse(
        courseTitle: defaultCourseTitle,
        summary: defaultCourseSummary,
        metadata: const {'is_default': true},
      );
      DevLog.add('📁 [DefaultCourse] Created default course: ${created.id}');
      return created.id;
    } catch (e) {
      DevLog.add('⚠️ [DefaultCourse] ensureDefaultCourse failed (offline?): $e');
      return null;
    }
  }
}
