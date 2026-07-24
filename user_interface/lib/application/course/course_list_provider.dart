import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lefture/domain/entities/course.dart';
import 'package:lefture/domain/entities/course_attribute.dart';
import 'package:lefture/infrastructure/supabase/repositories/course_repository_supabase.dart';
import 'package:lefture/infrastructure/supabase/repositories/course_attribute_repository_supabase.dart';

part 'course_list_provider.g.dart';

/// 全コース一覧（attributes 付き）
@riverpod
Future<List<Course>> courseList(Ref ref) async {
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
