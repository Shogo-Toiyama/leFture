// lib/domain/entities/lecture.dart
class Lecture {
  final String id;
  final String userId;

  final String? courseId;

  /// タイトル未入力でも開始できるなら nullable or '' でOK
  final String? title;
  final String? titleGenerated;
  final String? summary;
  final String? audioPath;

  /// DB側で採番するなら nullable か、0 を許容して trigger に任せる
  final int sortOrder;

  /// 汎用メタデータ。例: コース削除時に退避する
  /// {"previous_course_id": "...", "unassigned_at": "..."}
  final Map<String, dynamic>? metadata;

  final DateTime? deletedAt;

  final DateTime lectureDatetime;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 講義詳細を最後に開いた時刻。ローカルDB(LocalLectures.lastAccessedAt)由来で
  /// Supabaseには存在しないため、fromMap/toUpsertMapでは扱わない。
  final DateTime? lastAccessedAt;

  bool get isDeleted => deletedAt != null;

  String get displayTitle {
    if (title != null && title!.trim().isNotEmpty) {
      return title!.trim();
    }
    if (titleGenerated != null && titleGenerated!.trim().isNotEmpty) {
      return titleGenerated!.trim();
    }
    return 'Untitled Lecture';
  }

  Lecture({
    required this.id,
    required this.userId,
    required this.courseId,
    required this.title,
    this.titleGenerated,
    this.summary,
    this.audioPath,
    required this.sortOrder,
    this.metadata,
    this.deletedAt,
    required this.lectureDatetime,
    required this.createdAt,
    required this.updatedAt,
    this.lastAccessedAt,
  });

  factory Lecture.fromMap(Map<String, dynamic> map) {
    return Lecture(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      courseId: map['course_id'] as String?,
      title: map['title'] as String?,
      titleGenerated: map['title_generated'] as String?,
      summary: map['summary'] as String?,
      audioPath: map['audio_path'] as String?,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      metadata: map['metadata'] as Map<String, dynamic>?,
      deletedAt: map['deleted_at'] == null ? null : DateTime.parse(map['deleted_at'] as String),
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
      'lecture_datetime': lectureDatetime.toIso8601String(),
      'title': title,
      'title_generated': titleGenerated,
    };

    if (courseId != null) {
      m['course_id'] = courseId;
    }

    // sort_order はDBで決めるなら送らない
    // m['sort_order'] = sortOrder;

    return m;
  }
}
