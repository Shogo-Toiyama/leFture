import 'dart:convert';

class Keyword {
  const Keyword({
    required this.id,
    this.userId,
    this.lectureId,
    required this.topicNumber,
    this.keyword,
    this.definition,
    this.metadataJson,
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
  final String? metadataJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isSaved {
    if (metadataJson == null || metadataJson!.trim().isEmpty) return false;
    try {
      final map = jsonDecode(metadataJson!);
      return map is Map && map['saved'] == true;
    } catch (_) {
      return false;
    }
  }

  factory Keyword.fromMap(Map<String, dynamic> map) {
    String? rawMetadataJson;
    if (map['metadata_json'] is String) {
      rawMetadataJson = map['metadata_json'] as String;
    } else if (map['metadata'] != null) {
      rawMetadataJson = jsonEncode(map['metadata']);
    }

    return Keyword(
      id: map['id'] as String,
      userId: map['user_id'] as String?,
      lectureId: map['lecture_id'] as String?,
      topicNumber: (map['topic_number'] as num?)?.toInt() ?? 0,
      keyword: map['keyword'] as String?,
      definition: map['definition'] as String?,
      metadataJson: rawMetadataJson,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse((map['updated_at'] ?? map['created_at']) as String),
      deletedAt: map['deleted_at'] == null ? null : DateTime.parse(map['deleted_at'] as String),
    );
  }
}
