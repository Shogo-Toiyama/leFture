class CourseAttribute {
  const CourseAttribute({
    required this.id,
    required this.attributeType,
    required this.attributeName,
    this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String attributeType; // "year", "term", "subject", "school"
  final String attributeName;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CourseAttribute.fromMap(Map<String, dynamic> map) {
    return CourseAttribute(
      id: map['id'] as String,
      attributeType: map['attribute_type'] as String? ?? '',
      attributeName: map['attribute_name'] as String? ?? '',
      metadata: map['metadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse((map['updated_at'] ?? map['created_at']) as String),
    );
  }

  Map<String, dynamic> toInsertMap({required String userId}) {
    return {
      'user_id': userId,
      'attribute_type': attributeType,
      'attribute_name': attributeName,
      if (metadata != null) 'metadata': metadata,
    };
  }

  CourseAttribute copyWith({
    String? attributeType,
    String? attributeName,
    Map<String, dynamic>? metadata,
  }) {
    return CourseAttribute(
      id: id,
      attributeType: attributeType ?? this.attributeType,
      attributeName: attributeName ?? this.attributeName,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }
}
