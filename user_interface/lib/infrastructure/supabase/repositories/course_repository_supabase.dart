import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'course_repository_supabase.g.dart';

@Riverpod(keepAlive: true)
CourseRepositorySupabase courseRepository(Ref ref) {
  return CourseRepositorySupabase();
}

class CourseRepositorySupabase {
  static const _table = 'courses';

  // Supabase join query: course_attributes を year/term/subject/school 別に結合
  static const _selectWithAttributes = '''
    *,
    year:course_attributes!year_id(*),
    term:course_attributes!term_id(*),
    subject:course_attributes!subject_id(*),
    school:course_attributes!school_id(*)
  ''';

  String _requireUid() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw StateError('Not authenticated');
    return uid;
  }

  /// 全コース一覧（attributes 付き、削除済み除外）
  Future<List<Course>> listCourses() async {
    final uid = _requireUid();

    final rows = await supabase
        .from(_table)
        .select(_selectWithAttributes)
        .eq('user_id', uid)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    return rows.map((e) => Course.fromMap(e)).toList();
  }

  /// 単一コース取得
  Future<Course?> getCourse(String courseId) async {
    final uid = _requireUid();

    final row = await supabase
        .from(_table)
        .select(_selectWithAttributes)
        .eq('id', courseId)
        .eq('user_id', uid)
        .isFilter('deleted_at', null)
        .maybeSingle();

    if (row == null) return null;
    return Course.fromMap(row);
  }

  /// コース作成
  Future<Course> createCourse({
    required String courseTitle,
    String? courseCode,
    String? summary,
    String? yearId,
    String? termId,
    String? subjectId,
    String? schoolId,
    Map<String, dynamic>? metadata,
  }) async {
    _requireUid();

    final inserted = await supabase
        .from(_table)
        .insert({
          'user_id': _requireUid(),
          'course_title': courseTitle,
          if (courseCode != null) 'course_code': courseCode,
          if (summary != null) 'summary': summary,
          if (yearId != null) 'year_id': yearId,
          if (termId != null) 'term_id': termId,
          if (subjectId != null) 'subject_id': subjectId,
          if (schoolId != null) 'school_id': schoolId,
          if (metadata != null) 'metadata': metadata,
        })
        .select(_selectWithAttributes)
        .single();

    return Course.fromMap(inserted);
  }

  /// コース更新
  Future<Course> updateCourse({
    required String courseId,
    String? courseTitle,
    String? courseCode,
    String? summary,
    String? yearId,
    String? termId,
    String? subjectId,
    String? schoolId,
    Map<String, dynamic>? metadata,
  }) async {
    _requireUid();

    final updated = await supabase
        .from(_table)
        .update({
          if (courseTitle != null) 'course_title': courseTitle,
          if (courseCode != null) 'course_code': courseCode,
          if (summary != null) 'summary': summary,
          if (yearId != null) 'year_id': yearId,
          if (termId != null) 'term_id': termId,
          if (subjectId != null) 'subject_id': subjectId,
          if (schoolId != null) 'school_id': schoolId,
          if (metadata != null) 'metadata': metadata,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', courseId)
        .select(_selectWithAttributes)
        .single();

    return Course.fromMap(updated);
  }

  /// ソフトデリート
  Future<void> deleteCourse(String courseId) async {
    _requireUid();

    await supabase
        .from(_table)
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', courseId);
  }
}
