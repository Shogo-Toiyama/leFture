class Keyword {
  const Keyword({
    required this.id,
    this.userId,
    this.lectureId,
    required this.topicNumber,
    this.keyword,
    this.definition,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String? userId;
  final String? lectureId;
  final int topicNumber;
  final String? keyword;
  final String? definition;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory Keyword.fromMap(Map<String, dynamic> map) {
    return Keyword(
      id: map['id'] as String,
      userId: map['user_id'] as String?,
      lectureId: map['lecture_id'] as String?,
      topicNumber: (map['topic_number'] as num?)?.toInt() ?? 0,
      keyword: map['keyword'] as String?,
      definition: map['definition'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse((map['updated_at'] ?? map['created_at']) as String),
      deletedAt: map['deleted_at'] == null ? null : DateTime.parse(map['deleted_at'] as String),
    );
  }
}
