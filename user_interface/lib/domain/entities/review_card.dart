/// review_cards.card_content (jsonb) の1ブロック分。
/// 例: {"type": "paragraph", "text": "..."} / {"type": "list", "items": ["...", "..."]}
class ReviewCardBlock {
  const ReviewCardBlock({required this.type, this.text, this.items});

  final String type; // "paragraph" | "quote" | "list"
  final String? text;
  final List<String>? items;

  factory ReviewCardBlock.fromMap(Map<String, dynamic> map) {
    return ReviewCardBlock(
      type: map['type'] as String? ?? 'paragraph',
      text: map['text'] as String?,
      items: (map['items'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
    );
  }
}

class ReviewCard {
  const ReviewCard({
    required this.id,
    this.userId,
    this.lectureId,
    required this.topicNumber,
    required this.cardContent,
    this.cardType,
    this.title,
    this.heroEmoji,
    required this.createdAt,
  });

  final String id;
  final String? userId;
  final String? lectureId;
  final int topicNumber;
  final List<ReviewCardBlock> cardContent;
  final String? cardType;
  final String? title;
  final String? heroEmoji;
  final DateTime createdAt;

  factory ReviewCard.fromMap(Map<String, dynamic> map) {
    final rawContent = map['card_content'];
    final blocks = <ReviewCardBlock>[];
    if (rawContent is List) {
      for (final block in rawContent) {
        if (block is Map<String, dynamic>) {
          blocks.add(ReviewCardBlock.fromMap(block));
        } else if (block is Map) {
          blocks.add(ReviewCardBlock.fromMap(Map<String, dynamic>.from(block)));
        }
      }
    }

    return ReviewCard(
      id: map['id'] as String,
      userId: map['user_id'] as String?,
      lectureId: map['lecture_id'] as String?,
      topicNumber: (map['topic_number'] as num?)?.toInt() ?? 0,
      cardContent: blocks,
      cardType: map['card_type'] as String?,
      title: map['title'] as String?,
      heroEmoji: map['hero_emoji'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
