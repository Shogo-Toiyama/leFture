import 'package:lefture/domain/entities/annotation.dart';

class DeepNote {
  const DeepNote({
    required this.id,
    this.userId,
    this.lectureId,
    required this.topicNumber,
    this.noteContents,
    this.metadata,
    required this.createdAt,
  });

  final String id;
  final String? userId;
  final String? lectureId;
  final int topicNumber;
  final String? noteContents;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  // "like" / "dislike" / null
  String? get reaction => metadata?['reaction'] as String?;
  bool get saved => metadata?['saved'] == true;

  List<Annotation> get annotations {
    final raw = metadata?['annotations'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => Annotation.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  factory DeepNote.fromMap(Map<String, dynamic> map) {
    return DeepNote(
      id: map['id'] as String,
      userId: map['user_id'] as String?,
      lectureId: map['lecture_id'] as String?,
      topicNumber: (map['topic_number'] as num?)?.toInt() ?? 0,
      noteContents: map['note_contents'] as String?,
      metadata: map['metadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
