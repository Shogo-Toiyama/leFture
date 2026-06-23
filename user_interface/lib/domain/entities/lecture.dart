// lib/domain/entities/lecture.dart
class Lecture {
  final String id;
  final String userId;

  final String? courseId;

  /// タイトル未入力でも開始できるなら nullable or '' でOK
  final String? title;

  final bool isDeleted;

  /// DB側で採番するなら nullable か、0 を許容して trigger に任せる
  final int sortOrder;

  final DateTime lectureDatetime;
  final DateTime createdAt;
  final DateTime updatedAt;

  Lecture({
    required this.id,
    required this.userId,
    required this.courseId,
    required this.title,
    required this.isDeleted,
    required this.sortOrder,
    required this.lectureDatetime,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Lecture.fromMap(Map<String, dynamic> map) {
    return Lecture(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      courseId: map['course_id'] as String?,
      title: map['title'] as String?,
      isDeleted: (map['is_deleted'] as bool?) ?? false,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      lectureDatetime: DateTime.parse(map['lecture_datetime'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  /// insert, upsert 用
  /// DBに任せたいものは “送らない” のが一番安全
  Map<String, dynamic> toUpsertMap() {
    final m = <String, dynamic>{
      'id': id,
      'user_id': userId,
      'is_deleted': isDeleted,
      'lecture_datetime': lectureDatetime.toIso8601String(),
      'title': title,
    };

    if (courseId != null) {
      m['course_id'] = courseId;
    }

    // sort_order はDBで決めるなら送らない
    // m['sort_order'] = sortOrder;

    return m;
  }
}
