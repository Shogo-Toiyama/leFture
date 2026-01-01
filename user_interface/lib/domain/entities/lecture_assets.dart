class LectureAssets {
  final String id;
  final String lectureId;
  final String type;
  final String storageBucket;
  final String storagePath;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  LectureAssets({
    required this.id,
    required this.lectureId,
    required this.type,
    required this.storageBucket,
    required this.storagePath,
    required this.isDeleted,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LectureAssets.fromMap(Map<String, dynamic> map) {
    return LectureAssets(
      id: map['id'] as String,
      lectureId: map['lecture_id'] as String,
      type: map['type'] as String,
      storageBucket: map['storage_bucket'] as String,
      storagePath: map['storage_path'] as String,
      isDeleted: map['is_deleted'] as bool,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'lecture_id': lectureId,
      'type': type,
      'storage_bucket': storageBucket,
      'storage_path': storagePath,
      'is_deleted': isDeleted,
    };
  }
}