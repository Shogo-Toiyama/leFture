// Data models for the "Topic Map" subway-diagram prototype.
//
// Mirrors the JSON produced by the topic-mapping pipeline
// (see lefture_backend/app/services/prompts/topic_mapping_prompt.txt):
// a time-ordered DAG of lecture topics, grouped into clusters (chapters),
// plus "ghost nodes" representing predicted-but-not-yet-covered topics.

enum GhostStatus {
  active,
  faded;

  static GhostStatus fromJson(String? raw) {
    return raw == 'faded' ? GhostStatus.faded : GhostStatus.active;
  }
}

class TopicMapCluster {
  const TopicMapCluster({required this.id, required this.name});

  final String id;
  final String name;

  factory TopicMapCluster.fromJson(Map<String, dynamic> json) {
    return TopicMapCluster(
      id: json['cluster_id'] as String,
      name: json['name'] as String? ?? json['cluster_id'] as String,
    );
  }
}

class TopicMapNode {
  const TopicMapNode({
    required this.id,
    required this.title,
    required this.topicType,
    required this.clusterId,
    required this.lectureNum,
  });

  final String id;
  final String title;
  final String topicType;
  final String? clusterId;
  final int lectureNum;

  /// The pipeline never stamps a separate lecture_num field -- topic_id
  /// itself always encodes it (see task_runners.py: `f"node_lc{lecture_num}_{i}"`),
  /// so that's the only source of truth for it.
  static final RegExp _lectureNumPattern = RegExp(r'^node_lc(\d+)_');

  static int _lectureNumFromTopicId(String topicId) {
    return int.tryParse(_lectureNumPattern.firstMatch(topicId)?.group(1) ?? '') ?? 0;
  }

  factory TopicMapNode.fromJson(Map<String, dynamic> json) {
    final topicId = json['topic_id'] as String;
    return TopicMapNode(
      id: topicId,
      title: json['title'] as String? ?? topicId,
      topicType: json['topic_type'] as String? ?? 'ACADEMIC',
      clusterId: json['cluster_id'] as String?,
      lectureNum: _lectureNumFromTopicId(topicId),
    );
  }
}

class TopicMapEdge {
  const TopicMapEdge({
    required this.sourceId,
    required this.targetId,
    required this.relationType,
  });

  final String sourceId;
  final String targetId;

  /// Raw snake_case value from the pipeline (e.g. "builds_on"). Kept as-is
  /// rather than parsed into an enum since its only remaining use is a
  /// human-readable label on zoom -- see [humanizedRelationType].
  final String relationType;

  factory TopicMapEdge.fromJson(Map<String, dynamic> json) {
    return TopicMapEdge(
      sourceId: json['source_id'] as String,
      targetId: json['target_id'] as String,
      relationType: json['relation_type'] as String? ?? 'builds_on',
    );
  }

  String get humanizedRelationType => relationType.replaceAll('_', ' ');
}

class TopicMapGhostNode {
  const TopicMapGhostNode({
    required this.id,
    required this.name,
    required this.clusterId,
    required this.status,
    required this.derivedFromTopicId,
  });

  final String id;
  final String name;
  final String? clusterId;
  final GhostStatus status;
  final String? derivedFromTopicId;

  factory TopicMapGhostNode.fromJson(Map<String, dynamic> json) {
    return TopicMapGhostNode(
      id: json['ghost_id'] as String,
      name: json['name'] as String? ?? json['ghost_id'] as String,
      clusterId: json['cluster_id'] as String?,
      status: GhostStatus.fromJson(json['status'] as String?),
      derivedFromTopicId: json['derived_from_topic_id'] as String?,
    );
  }
}

class TopicMapData {
  const TopicMapData({
    required this.courseTitle,
    required this.totalLecturesCovered,
    required this.clusters,
    required this.nodes,
    required this.edges,
    required this.ghostNodes,
  });

  final String courseTitle;
  final int totalLecturesCovered;
  final List<TopicMapCluster> clusters;
  final List<TopicMapNode> nodes;
  final List<TopicMapEdge> edges;
  final List<TopicMapGhostNode> ghostNodes;

  /// The real pipeline never writes course_title/total_lectures_covered into
  /// the map jsonb at all -- those belong to the courses/lectures tables,
  /// not this course-scoped map. [courseTitle]/[totalLecturesCovered] let a
  /// caller that has that data (see topic_map_provider.dart) supply the
  /// real values; when omitted, falls back to reading the json (only
  /// relevant for the standalone test fixture, which does inline them).
  factory TopicMapData.fromJson(
    Map<String, dynamic> json, {
    String? courseTitle,
    int? totalLecturesCovered,
  }) {
    return TopicMapData(
      courseTitle: courseTitle ?? json['course_title'] as String? ?? 'Untitled Course',
      totalLecturesCovered:
          totalLecturesCovered ?? (json['total_lectures_covered'] as num?)?.toInt() ?? 0,
      clusters: (json['clusters'] as List<dynamic>? ?? [])
          .map((e) => TopicMapCluster.fromJson(e as Map<String, dynamic>))
          .toList(),
      nodes: (json['nodes'] as List<dynamic>? ?? [])
          .map((e) => TopicMapNode.fromJson(e as Map<String, dynamic>))
          .toList(),
      edges: (json['edges'] as List<dynamic>? ?? [])
          .map((e) => TopicMapEdge.fromJson(e as Map<String, dynamic>))
          .toList(),
      ghostNodes: (json['ghost_nodes'] as List<dynamic>? ?? [])
          .map((e) => TopicMapGhostNode.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  TopicMapData copyWith({String? courseTitle, int? totalLecturesCovered}) {
    return TopicMapData(
      courseTitle: courseTitle ?? this.courseTitle,
      totalLecturesCovered: totalLecturesCovered ?? this.totalLecturesCovered,
      clusters: clusters,
      nodes: nodes,
      edges: edges,
      ghostNodes: ghostNodes,
    );
  }
}
