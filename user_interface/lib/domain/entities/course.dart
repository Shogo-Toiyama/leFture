import 'package:lefture/domain/entities/course_attribute.dart';

class Course {
  const Course({
    required this.id,
    required this.userId,
    this.courseTitle,
    this.courseCode,
    this.summary,
    this.schoolId,
    this.yearId,
    this.termId,
    this.subjectId,
    this.professorId,
    this.metadata,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
    this.year,
    this.term,
    this.subject,
    this.school,
    this.professor,
  });

  final String id;
  final String userId;
  final String? courseTitle;
  final String? courseCode;
  final String? summary;
  final String? schoolId;
  final String? yearId;
  final String? termId;
  final String? subjectId;

  /// DBのカラム名は "professor" (course_attributesへのFK)
  final String? professorId;
  final Map<String, dynamic>? metadata;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Resolved attributes (populated when fetched with join)
  final CourseAttribute? year;
  final CourseAttribute? term;
  final CourseAttribute? subject;
  final CourseAttribute? school;
  final CourseAttribute? professor;

  String get displayTitle => courseTitle ?? courseCode ?? 'Untitled Course';

  String? get icon => metadata?['icon'] as String?;
  String? get color => metadata?['color'] as String?;

  factory Course.fromMap(Map<String, dynamic> map) {
    CourseAttribute? parseAttr(dynamic raw) {
      if (raw == null) return null;
      if (raw is Map<String, dynamic>) return CourseAttribute.fromMap(raw);
      return null;
    }

    return Course(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      courseTitle: map['course_title'] as String?,
      courseCode: map['course_code'] as String?,
      summary: map['summary'] as String?,
      schoolId: map['school_id'] as String?,
      yearId: map['year_id'] as String?,
      termId: map['term_id'] as String?,
      subjectId: map['subject_id'] as String?,
      // professorカラム自体はuuid。埋め込みJOINは "professor_attr" 別名で取得する
      professorId: map['professor'] is String
          ? map['professor'] as String
          : null,
      metadata: map['metadata'] as Map<String, dynamic>?,
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.parse(map['deleted_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(
        (map['updated_at'] ?? map['created_at']) as String,
      ),
      year: parseAttr(map['year']),
      term: parseAttr(map['term']),
      subject: parseAttr(map['subject']),
      school: parseAttr(map['school']),
      professor: parseAttr(map['professor_attr']),
    );
  }

  Course copyWith({
    String? courseTitle,
    String? courseCode,
    String? summary,
    String? schoolId,
    String? yearId,
    String? termId,
    String? subjectId,
    String? professorId,
    Map<String, dynamic>? metadata,
  }) {
    return Course(
      id: id,
      userId: userId,
      courseTitle: courseTitle ?? this.courseTitle,
      courseCode: courseCode ?? this.courseCode,
      summary: summary ?? this.summary,
      schoolId: schoolId ?? this.schoolId,
      yearId: yearId ?? this.yearId,
      termId: termId ?? this.termId,
      subjectId: subjectId ?? this.subjectId,
      professorId: professorId ?? this.professorId,
      metadata: metadata ?? this.metadata,
      deletedAt: deletedAt,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
      year: year,
      term: term,
      subject: subject,
      school: school,
      professor: professor,
    );
  }
}
