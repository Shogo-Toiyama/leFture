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

  // Supabase join query: course_attributes を year/term/subject/school/professor 別に結合。
  // professorはカラム名自体が "professor" (uuid) なので、埋め込みは別名 "professor_attr" で
  // 取得する (同名にするとレスポンス上でuuidカラムが埋め込みオブジェクトに置き換わるため)。
  static const _selectWithAttributes = '''
    *,
    year:course_attributes!year_id(*),
    term:course_attributes!term_id(*),
    subject:course_attributes!subject_id(*),
    school:course_attributes!school_id(*),
    professor_attr:course_attributes!professor(*)
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
    String? professorId,
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
          if (professorId != null) 'professor': professorId,
          if (metadata != null) 'metadata': metadata,
        })
        .select(_selectWithAttributes)
        .single();

    return Course.fromMap(inserted);
  }

  /// コース更新。
  /// 編集フォームからの保存を想定しており、コード/概要/各アトリビュートは
  /// nullを渡すと「クリア(未設定に戻す)」の意味になる。
  Future<Course> updateCourse({
    required String courseId,
    String? courseTitle,
    String? courseCode,
    String? summary,
    String? yearId,
    String? termId,
    String? subjectId,
    String? schoolId,
    String? professorId,
    Map<String, dynamic>? metadata,
  }) async {
    _requireUid();

    final updated = await supabase
        .from(_table)
        .update({
          if (courseTitle != null) 'course_title': courseTitle,
          'course_code': courseCode,
          'summary': summary,
          'year_id': yearId,
          'term_id': termId,
          'subject_id': subjectId,
          'school_id': schoolId,
          'professor': professorId,
          if (metadata != null) 'metadata': metadata,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', courseId)
        .select(_selectWithAttributes)
        .single();

    return Course.fromMap(updated);
  }

  /// ソフトデリート。配下のLecture（とその関連データ）もまとめてソフトデリートする
  /// （「フォルダを消したら中身も消える」という一般的な感覚に合わせる）。
  /// course_idは書き換えず残しておく — ゴミ箱機能を作る際、コースを復元すれば
  /// このカスケードで消えたLectureも一緒に復元できるようにするため。
  /// deleted_via_course_cascadeだけmetadataに記録し、「個別に削除されていた
  /// Lecture」と区別できるようにする（削除日時はdeleted_at列自体を見ればよい
  /// ので重複させない）。
  Future<void> deleteCourse(String courseId) async {
    final uid = _requireUid();
    final now = DateTime.now().toUtc().toIso8601String();

    final lectures = await supabase
        .from('lectures')
        .select('id, metadata')
        .eq('user_id', uid)
        .eq('course_id', courseId)
        .isFilter('deleted_at', null);

    final lectureIds = <String>[];

    for (final row in lectures) {
      final lectureId = row['id'] as String;
      lectureIds.add(lectureId);

      final existingMetadata = (row['metadata'] as Map<String, dynamic>?) ?? {};
      final mergedMetadata = {
        ...existingMetadata,
        'deleted_via_course_cascade': true,
      };

      await supabase
          .from('lectures')
          .update({
            'deleted_at': now,
            'metadata': mergedMetadata,
            'updated_at': now,
          })
          .eq('id', lectureId);
    }

    // 関連データ（Announcement/ReviewCard/FunFact/LectureTopic/DeepNote/Keyword）も
    // まとめてソフトデリート
    if (lectureIds.isNotEmpty) {
      for (final table in const [
        'announcements',
        'review_cards',
        'fun_facts',
        'lecture_topics',
        'deep_notes',
        'keywords',
      ]) {
        await supabase
            .from(table)
            .update({'deleted_at': now})
            .inFilter('lecture_id', lectureIds);
      }
    }

    await supabase
        .from(_table)
        .update({'deleted_at': now})
        .eq('id', courseId);
  }
}
