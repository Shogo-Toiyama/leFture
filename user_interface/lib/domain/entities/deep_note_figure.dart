class DeepNoteFigure {
  const DeepNoteFigure({
    required this.id,
    required this.lectureId,
    required this.topicNumber,
    required this.figureIndex,
    required this.figureType,
    required this.title,
    required this.description,
    required this.htmlContent,
    required this.createdAt,
  });

  final String id;
  final String lectureId;
  final int topicNumber;
  final int figureIndex;
  final String figureType;
  final String title;
  final String description;
  final String htmlContent;
  final DateTime createdAt;

  factory DeepNoteFigure.fromMap(Map<String, dynamic> map) {
    return DeepNoteFigure(
      id: map['id'] as String,
      lectureId: map['lecture_id'] as String,
      topicNumber: (map['topic_number'] as num?)?.toInt() ?? 0,
      figureIndex: (map['figure_index'] as num?)?.toInt() ?? 0,
      figureType: map['figure_type'] as String? ?? 'html_diagram',
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      htmlContent: map['html_content'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
