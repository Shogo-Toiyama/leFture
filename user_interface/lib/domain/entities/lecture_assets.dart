// lib/domain/entities/lecture_assets.dart
class LectureAsset {
  final String id;
  final String lectureId;
  final String ownerId;
  final String type;
  final String storageBucket;
  final String storagePath;
  final DateTime createdAt;

  LectureAsset({
    required this.id,
    required this.lectureId,
    required this.ownerId,
    required this.type,
    required this.storageBucket,
    required this.storagePath,
    required this.createdAt,
  });

  factory LectureAsset.fromMap(Map<String, dynamic> map) {
    return LectureAsset(
      id: map['id'] as String,
      lectureId: map['lecture_id'] as String,
      ownerId: map['owner_id'] as String,
      type: map['type'] as String,
      storageBucket: map['storage_bucket'] as String,
      storagePath: map['storage_path'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'lecture_id': lectureId,
        'owner_id': ownerId,
        'type': type,
        'storage_bucket': storageBucket,
        'storage_path': storagePath,
      };
}
