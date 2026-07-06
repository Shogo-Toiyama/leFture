class LectureTopic {
  const LectureTopic({
    required this.id,
    this.userId,
    this.lectureId,
    required this.index,
    this.topicTitle,
    this.topicType,
    this.summary,
    this.startSid,
    this.endSid,
    this.imagePath,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? userId;
  final String? lectureId;
  final int index;
  final String? topicTitle;
  final String? topicType;
  final String? summary;
  final String? startSid;
  final String? endSid;
  final String? imagePath;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayTitle => topicTitle?.trim().isNotEmpty == true ? topicTitle! : 'Topic $index';

  factory LectureTopic.fromMap(Map<String, dynamic> map) {
    return LectureTopic(
      id: map['id'] as String,
      userId: map['user_id'] as String?,
      lectureId: map['lecture_id'] as String?,
      index: (map['index'] as num?)?.toInt() ?? 0,
      topicTitle: map['topic_title'] as String?,
      topicType: map['topic_type'] as String?,
      summary: map['summary'] as String?,
      startSid: map['start_sid'] as String?,
      endSid: map['end_sid'] as String?,
      imagePath: map['image_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse((map['updated_at'] ?? map['created_at']) as String),
    );
  }
}
