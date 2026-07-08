enum AnnouncementType { todo, event, hint, info, unknown }

AnnouncementType announcementTypeFromString(String? raw) {
  switch (raw?.toUpperCase()) {
    case 'TODO':
      return AnnouncementType.todo;
    case 'EVENT':
      return AnnouncementType.event;
    case 'HINT':
      return AnnouncementType.hint;
    case 'INFO':
      return AnnouncementType.info;
    default:
      return AnnouncementType.unknown;
  }
}

class Announcement {
  const Announcement({
    required this.id,
    this.userId,
    this.lectureId,
    required this.type,
    this.title,
    this.description,
    this.location,
    this.startSid,
    this.endSid,
    this.relatedTopicTitle,
    this.datetimeParameters,
    this.completedAt,
    this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? userId;
  final String? lectureId;
  final AnnouncementType type;
  final String? title;
  final String? description;
  final String? location;
  final String? startSid;
  final String? endSid;
  final String? relatedTopicTitle;
  final Map<String, dynamic>? datetimeParameters;
  final DateTime? completedAt;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Announcement.fromMap(Map<String, dynamic> map) {
    return Announcement(
      id: map['id'] as String,
      userId: map['user_id'] as String?,
      lectureId: map['lecture_id'] as String?,
      type: announcementTypeFromString(map['type'] as String?),
      title: map['title'] as String?,
      description: map['description'] as String?,
      location: map['location'] as String?,
      startSid: map['start_sid'] as String?,
      endSid: map['end_sid'] as String?,
      relatedTopicTitle: map['related_topic_title'] as String?,
      datetimeParameters: map['datetime_parameters'] as Map<String, dynamic>?,
      completedAt: map['completed_at'] == null ? null : DateTime.parse(map['completed_at'] as String),
      metadata: map['metadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse((map['updated_at'] ?? map['created_at']) as String),
    );
  }

  bool get isCompleted => completedAt != null;

  Announcement copyWith({
    DateTime? Function()? completedAt,
  }) {
    return Announcement(
      id: id,
      userId: userId,
      lectureId: lectureId,
      type: type,
      title: title,
      description: description,
      location: location,
      startSid: startSid,
      endSid: endSid,
      relatedTopicTitle: relatedTopicTitle,
      datetimeParameters: datetimeParameters,
      completedAt: completedAt != null ? completedAt() : this.completedAt,
      metadata: metadata,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
