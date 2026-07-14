// Data models for the "Topic Map" subway-diagram prototype.
//
// Mirrors the JSON produced by the topic-mapping pipeline
// (see lefture_backend/app/services/prompts/topic_mapping_prompt.txt):
// a time-ordered DAG of lecture topics, grouped into clusters (chapters),
// plus "ghost nodes" representing predicted-but-not-yet-covered topics.
//
// This JSON is ultimately LLM-authored server-side, so a single malformed
// entry (missing/wrong-typed required id field) is plausible. Each fromJson
// below returns null instead of throwing when its own required id is
// missing, and TopicMapData.fromJson drops just that one entry (logging it)
// rather than letting one bad node/edge take down parsing of the whole map.

import 'package:flutter/foundation.dart';

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

  static TopicMapCluster? tryFromJson(Map<String, dynamic> json) {
    final id = json['cluster_id'];
    if (id is! String) {
      debugPrint('⚠️ TopicMapCluster: skipping entry with missing/invalid cluster_id: $json');
      return null;
    }
    final name = json['name'];
    return TopicMapCluster(id: id, name: name is String ? name : id);
  }
}

class TopicMapNode {
  const TopicMapNode({
    required this.id,
    required this.title,
    required this.topicType,
    required this.clusterId,
    required this.sourceLectureId,
    required this.topicIndexInLecture,
    this.lectureNum,
  });

  final String id;
  final String title;
  final String topicType;
  final String? clusterId;

  /// The lecture this topic came from. This is the stable join key -- unlike
  /// [lectureNum] below, it never changes even if other lectures in the
  /// course are later deleted/reordered.
  final String? sourceLectureId;

  /// This topic's fixed 1-based position within its own lecture (stable,
  /// never recomputed -- see core_extraction.py's per-lecture ACADEMIC idx).
  final int? topicIndexInLecture;

  /// The lecture's current 1-based position within the course. The pipeline
  /// never persists this (see helpers.py: `_annotate_nodes_with_live_lecture_num`
  /// is LLM-input-only and never written to topic_maps.map), because it can
  /// change whenever an earlier lecture is deleted/moved. It is resolved
  /// live from [sourceLectureId] by topic_map_provider.dart, using the same
  /// "current lecture list order" the backend recomputes on every call --
  /// so it's null until that composition step fills it in.
  final int? lectureNum;

  static TopicMapNode? tryFromJson(Map<String, dynamic> json) {
    final topicId = json['topic_id'];
    if (topicId is! String) {
      debugPrint('⚠️ TopicMapNode: skipping entry with missing/invalid topic_id: $json');
      return null;
    }
    final title = json['title'];
    return TopicMapNode(
      id: topicId,
      title: title is String ? title : topicId,
      topicType: json['topic_type'] as String? ?? 'ACADEMIC',
      clusterId: json['cluster_id'] as String?,
      sourceLectureId: json['source_lecture_id'] as String?,
      topicIndexInLecture: (json['topic_index_in_lecture'] as num?)?.toInt(),
      // The real pipeline never writes this into topic_maps.map (see the
      // class-level doc on `lectureNum`); topic_map_provider.dart fills it
      // in afterward via copyWith. Only the standalone test fixture
      // (test_topic_map.json), which bypasses that provider, embeds it here.
      lectureNum: (json['lecture_num'] as num?)?.toInt(),
    );
  }

  TopicMapNode copyWith({int? lectureNum}) {
    return TopicMapNode(
      id: id,
      title: title,
      topicType: topicType,
      clusterId: clusterId,
      sourceLectureId: sourceLectureId,
      topicIndexInLecture: topicIndexInLecture,
      lectureNum: lectureNum ?? this.lectureNum,
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

  static TopicMapEdge? tryFromJson(Map<String, dynamic> json) {
    final sourceId = json['source_id'];
    final targetId = json['target_id'];
    if (sourceId is! String || targetId is! String) {
      debugPrint('⚠️ TopicMapEdge: skipping entry with missing/invalid source_id/target_id: $json');
      return null;
    }
    return TopicMapEdge(
      sourceId: sourceId,
      targetId: targetId,
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

  static TopicMapGhostNode? tryFromJson(Map<String, dynamic> json) {
    final ghostId = json['ghost_id'];
    if (ghostId is! String) {
      debugPrint('⚠️ TopicMapGhostNode: skipping entry with missing/invalid ghost_id: $json');
      return null;
    }
    final name = json['name'];
    return TopicMapGhostNode(
      id: ghostId,
      name: name is String ? name : ghostId,
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
    this.isStale = false,
  });

  final String courseTitle;
  final int totalLecturesCovered;
  final List<TopicMapCluster> clusters;
  final List<TopicMapNode> nodes;
  final List<TopicMapEdge> edges;
  final List<TopicMapGhostNode> ghostNodes;

  /// True when a lecture belonging to this course was deleted/moved and the
  /// map hasn't been repaired yet (see topic_map_repository_supabase.dart's
  /// `is_stale` column -- not part of the `map` jsonb itself, so it's always
  /// supplied by the caller, never parsed out of [fromJson]'s json arg).
  /// The UI should offer "Recreate Topic Map" instead of the normal view
  /// while this is true.
  final bool isStale;

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
    bool isStale = false,
  }) {
    return TopicMapData(
      courseTitle: courseTitle ?? json['course_title'] as String? ?? 'Untitled Course',
      totalLecturesCovered:
          totalLecturesCovered ?? (json['total_lectures_covered'] as num?)?.toInt() ?? 0,
      clusters: (json['clusters'] as List<dynamic>? ?? [])
          .map((e) => e is Map<String, dynamic> ? TopicMapCluster.tryFromJson(e) : null)
          .whereType<TopicMapCluster>()
          .toList(),
      nodes: (json['nodes'] as List<dynamic>? ?? [])
          .map((e) => e is Map<String, dynamic> ? TopicMapNode.tryFromJson(e) : null)
          .whereType<TopicMapNode>()
          .toList(),
      edges: (json['edges'] as List<dynamic>? ?? [])
          .map((e) => e is Map<String, dynamic> ? TopicMapEdge.tryFromJson(e) : null)
          .whereType<TopicMapEdge>()
          .toList(),
      ghostNodes: (json['ghost_nodes'] as List<dynamic>? ?? [])
          .map((e) => e is Map<String, dynamic> ? TopicMapGhostNode.tryFromJson(e) : null)
          .whereType<TopicMapGhostNode>()
          .toList(),
      isStale: isStale,
    );
  }

  TopicMapData copyWith({
    String? courseTitle,
    int? totalLecturesCovered,
    List<TopicMapNode>? nodes,
    bool? isStale,
  }) {
    return TopicMapData(
      courseTitle: courseTitle ?? this.courseTitle,
      totalLecturesCovered: totalLecturesCovered ?? this.totalLecturesCovered,
      clusters: clusters,
      nodes: nodes ?? this.nodes,
      edges: edges,
      ghostNodes: ghostNodes,
      isStale: isStale ?? this.isStale,
    );
  }
}
