class Lecture {
  final String id;
  final String ownerId;
  final String folderId;
  final String title;
  final bool isDeleted;
  final int sortOrder;
  final DateTime lectureDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  Lecture({
    required this.id,
    required this.ownerId,
    required this.folderId,
    required this.title,
    required this.isDeleted,
    required this.sortOrder,
    required this.lectureDate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Lecture.fromMap(Map<String, dynamic> map) {
    return Lecture(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      folderId: map['folder_id'] as String,
      title: map['title'] as String,
      isDeleted: map['is_deleted'] as bool,
      sortOrder: map['sort_order'] as int,
      lectureDate: DateTime.parse(map['date'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'folder_id': folderId,
      'title': title,
      'is_deleted': isDeleted,
      'sort_order': sortOrder,
      'lecture_date': lectureDate,
    };
  }
}