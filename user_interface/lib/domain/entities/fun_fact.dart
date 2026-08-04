class FunFact {
  const FunFact({
    required this.id,
    this.userId,
    this.lectureId,
    this.title,
    this.hook,
    this.body,
    this.metadata,
    this.reaction,
    required this.createdAt,
  });

  final String id;
  final String? userId;
  final String? lectureId;
  final String? title;
  final String? hook;
  final String? body;
  final Map<String, dynamic>? metadata;
  // "like" / "dislike" / null。ローカルファースト化以降はこちらが正
  // (metadata['reaction']はサーバーの最終同期時点のキャッシュ)。
  final String? reaction;
  final DateTime createdAt;

  // 参照したWeb検索結果のURL一覧(あれば)。metadataの一部として同期される。
  List<String> get sources {
    final raw = metadata?['sources'];
    if (raw is List) {
      return raw.whereType<String>().toList();
    }
    return const [];
  }

  factory FunFact.fromMap(Map<String, dynamic> map) {
    final metadata = map['metadata'] as Map<String, dynamic>?;
    return FunFact(
      id: map['id'] as String,
      userId: map['user_id'] as String?,
      lectureId: map['lecture_id'] as String?,
      title: map['title'] as String?,
      hook: map['hook'] as String?,
      body: map['body'] as String?,
      metadata: metadata,
      reaction: metadata?['reaction'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
