import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lefture/domain/entities/course.dart';
import 'package:lefture/domain/entities/course_attribute.dart';
import 'package:lefture/infrastructure/supabase/repositories/course_repository_supabase.dart';
import 'package:lefture/infrastructure/supabase/repositories/course_attribute_repository_supabase.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

part 'course_list_provider.g.dart';

/// 全コース一覧（attributes 付き）
// keepAlive: true — Welcome画面で先読み(ref.read(...future))した直後に
// Welcomeが破棄されると、autoDisposeのままではこのProviderも一緒に破棄されて
// しまい、Home表示時にもう一度ゼロから読み込み直し(ローディング表示)になって
// いた。セッション中は保持することで、Welcomeでの先読みがHomeまで活きる。
//
// 以前はここでcurrentUserProviderをwatchして、アカウント切り替え時に自動で
// 再取得されるようにしていたが、Supabaseの認証イベント(サインイン直後など)を
// きっかけにHomeのビルド中にこのProviderが再取得されてしまい、Riverpodの
// 「ビルド中にProviderを変更できない」エラーが発生した。
// 常時Reactiveに監視するのではなく、サインアウト処理側(my_account_page.dart)で
// 明示的にref.invalidate(courseListProvider)する方式に変更した。
@Riverpod(keepAlive: true)
Future<List<Course>> courseList(Ref ref) async {
  if (supabase.auth.currentUser == null) return [];
  final repo = ref.watch(courseRepositoryProvider);
  return repo.listCourses();
}

/// Year アトリビュート一覧（コース作成フォームの候補）
@riverpod
Future<List<CourseAttribute>> yearAttributes(Ref ref) async {
  final repo = ref.watch(courseAttributeRepositoryProvider);
  return repo.listByType('year');
}

/// Term アトリビュート一覧（コース作成フォームの候補）
@riverpod
Future<List<CourseAttribute>> termAttributes(Ref ref) async {
  final repo = ref.watch(courseAttributeRepositoryProvider);
  return repo.listByType('term');
}

/// Professor アトリビュート一覧（コース作成フォームの候補）
@riverpod
Future<List<CourseAttribute>> professorAttributes(Ref ref) async {
  final repo = ref.watch(courseAttributeRepositoryProvider);
  return repo.listByType('professor');
}

/// School アトリビュート一覧（コース作成フォームの候補）
@riverpod
Future<List<CourseAttribute>> schoolAttributes(Ref ref) async {
  final repo = ref.watch(courseAttributeRepositoryProvider);
  return repo.listByType('school');
}

/// Subject アトリビュート一覧（コース作成フォームの候補）
@riverpod
Future<List<CourseAttribute>> subjectAttributes(Ref ref) async {
  final repo = ref.watch(courseAttributeRepositoryProvider);
  return repo.listByType('subject');
}
