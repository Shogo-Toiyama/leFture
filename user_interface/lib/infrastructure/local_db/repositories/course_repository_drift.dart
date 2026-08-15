import 'dart:convert';

import 'package:lefture/domain/entities/course.dart';
import 'package:lefture/domain/entities/course_attribute.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';

class CourseRepositoryDrift {
  final AppDatabase _db;

  CourseRepositoryDrift(this._db);

  /// コース一覧を監視する。年度/学期/科目/学校/担当教員は、コースの変更が
  /// 起きるたびに(呼び出し頻度が低いテーブルなので)アトリビュート一覧を
  /// 読み直して都度解決する — SupabaseのJOINクエリと同じ結果を、
  /// ローカルDB上でアプリ側のjoinとして再現する形。
  Stream<List<Course>> watchCourses({required String userId}) {
    return _db.watchCourses(userId).asyncMap((rows) async {
      final attributes = await _db.getAllCourseAttributes(userId);
      final attrById = {for (final a in attributes) a.id: _attrToDomain(a)};
      return rows.map((row) => _toDomain(row, attrById)).toList();
    });
  }

  /// 指定タイプのアトリビュート一覧を監視する(コース作成フォームの候補用)。
  Stream<List<CourseAttribute>> watchAttributesByType({
    required String userId,
    required String attributeType,
  }) {
    return _db
        .watchCourseAttributesByType(userId, attributeType)
        .map((rows) => rows.map(_attrToDomain).toList());
  }

  Course _toDomain(LocalCourse row, Map<String, CourseAttribute> attrById) {
    return Course(
      id: row.id,
      userId: row.userId,
      courseTitle: row.courseTitle,
      courseCode: row.courseCode,
      summary: row.summary,
      schoolId: row.schoolId,
      yearId: row.yearId,
      termId: row.termId,
      subjectId: row.subjectId,
      professorId: row.professorId,
      metadata: row.metadataJson != null
          ? Map<String, dynamic>.from(jsonDecode(row.metadataJson!) as Map)
          : null,
      deletedAt: row.deletedAt,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      year: row.yearId != null ? attrById[row.yearId] : null,
      term: row.termId != null ? attrById[row.termId] : null,
      subject: row.subjectId != null ? attrById[row.subjectId] : null,
      school: row.schoolId != null ? attrById[row.schoolId] : null,
      professor: row.professorId != null ? attrById[row.professorId] : null,
    );
  }

  CourseAttribute _attrToDomain(LocalCourseAttribute row) {
    return CourseAttribute(
      id: row.id,
      attributeType: row.attributeType,
      attributeName: row.attributeName,
      metadata: row.metadataJson != null
          ? Map<String, dynamic>.from(jsonDecode(row.metadataJson!) as Map)
          : null,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}
