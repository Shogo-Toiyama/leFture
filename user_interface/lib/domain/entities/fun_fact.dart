class FunFact {
  const FunFact({
    required this.id,
    this.userId,
    this.lectureId,
    this.title,
    this.hook,
    this.body,
    this.metadata,
    required this.createdAt,
  });

  final String id;
  final String? userId;
  final String? lectureId;
  final String? title;
  final String? hook;
  final String? body;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  factory FunFact.fromMap(Map<String, dynamic> map) {
    return FunFact(
      id: map['id'] as String,
      userId: map['user_id'] as String?,
      lectureId: map['lecture_id'] as String?,
      title: map['title'] as String?,
      hook: map['hook'] as String?,
      body: map['body'] as String?,
      metadata: map['metadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
