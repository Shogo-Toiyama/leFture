class DeepNote {
  const DeepNote({
    required this.id,
    this.userId,
    this.lectureId,
    required this.topicNumber,
    this.noteContents,
    required this.createdAt,
  });

  final String id;
  final String? userId;
  final String? lectureId;
  final int topicNumber;
  final String? noteContents;
  final DateTime createdAt;

  factory DeepNote.fromMap(Map<String, dynamic> map) {
    return DeepNote(
      id: map['id'] as String,
      userId: map['user_id'] as String?,
      lectureId: map['lecture_id'] as String?,
      topicNumber: (map['topic_number'] as num?)?.toInt() ?? 0,
      noteContents: map['note_contents'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
