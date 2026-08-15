import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lefture/domain/entities/course.dart';
import 'package:lefture/domain/entities/course_attribute.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';
import 'package:lefture/infrastructure/local_db/repositories/course_repository_drift.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

part 'course_list_provider.g.dart';

@riverpod
CourseRepositoryDrift courseRepositoryDrift(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return CourseRepositoryDrift(db);
}

/// 全コース一覧（attributes 付き）
// keepAlive: true — Welcome画面で先読み(ref.read(...future))した直後に
// Welcomeが破棄されると、autoDisposeのままではこのProviderも一緒に破棄されて
// しまい、Home表示時にもう一度ゼロから読み込み直し(ローディング表示)になって
// いた。セッション中は保持することで、Welcomeでの先読みがHomeまで活きる。
//
// 以前はSupabaseへ直接問い合わせるだけで、ローカルDBにキャッシュしていな
// かった(Lecture等は他のエンティティと違いこの1つだけ例外だった)。
// これだと通信が悪い状態でPull-to-Refresh等によりこのProviderが再取得
// された時、正常に取得できていたコース一覧が失われて見えるバグがあった
// (CoursesPage/CoursePageが「コースが1つも無い」状態に見えてしまう)。
// 他のエンティティと同じく、ローカルDB(Drift)のStreamをそのまま表示に
// 使う形に変更した — DriftのStreamは元々のクエリ結果を保持し続けるので、
// 通信状態に関わらず「最後に同期できた状態」を表示し続けられる。
//
// 書き込み(作成/更新/削除/復元)は引き続きオンライン時にSupabaseへ直接
// 行っており、その直後は[LectureController.pullCoursesNow]を呼んで
// ローカルDBへの反映を即座に行う(各呼び出し元を参照)。
//
// 以前はここでcurrentUserProviderをwatchして、アカウント切り替え時に自動で
// 再取得されるようにしていたが、Supabaseの認証イベント(サインイン直後など)を
// きっかけにHomeのビルド中にこのProviderが再取得されてしまい、Riverpodの
// 「ビルド中にProviderを変更できない」エラーが発生した。
// 常時Reactiveに監視するのではなく、サインアウト処理側(my_account_page.dart)で
// 明示的にref.invalidate(courseListProvider)する方式に変更した(踏襲)。
@Riverpod(keepAlive: true)
Stream<List<Course>> courseList(Ref ref) {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return Stream.value(const <Course>[]);

  final repo = ref.watch(courseRepositoryDriftProvider);
  return repo.watchCourses(userId: uid);
}

Stream<List<CourseAttribute>> _watchAttributes(Ref ref, String attributeType) {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return Stream.value(const <CourseAttribute>[]);

  final repo = ref.watch(courseRepositoryDriftProvider);
  return repo.watchAttributesByType(userId: uid, attributeType: attributeType);
}

/// Year アトリビュート一覧（コース作成フォームの候補）
@riverpod
Stream<List<CourseAttribute>> yearAttributes(Ref ref) =>
    _watchAttributes(ref, 'year');

/// Term アトリビュート一覧（コース作成フォームの候補）
@riverpod
Stream<List<CourseAttribute>> termAttributes(Ref ref) =>
    _watchAttributes(ref, 'term');

/// Professor アトリビュート一覧（コース作成フォームの候補）
@riverpod
Stream<List<CourseAttribute>> professorAttributes(Ref ref) =>
    _watchAttributes(ref, 'professor');

/// School アトリビュート一覧（コース作成フォームの候補）
@riverpod
Stream<List<CourseAttribute>> schoolAttributes(Ref ref) =>
    _watchAttributes(ref, 'school');

/// Subject アトリビュート一覧（コース作成フォームの候補）
@riverpod
Stream<List<CourseAttribute>> subjectAttributes(Ref ref) =>
    _watchAttributes(ref, 'subject');
