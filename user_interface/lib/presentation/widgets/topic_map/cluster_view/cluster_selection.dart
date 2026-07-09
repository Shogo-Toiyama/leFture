// Tap-to-highlight state. Everything is dim by default (per the "study
// overview first" design); tapping a node or a cluster's blob brings the
// relevant subset to full opacity so relationships stand out on demand.

import '../topic_map_models.dart';

enum ClusterSelectionType { node, cluster, lecture }

/// The 3 explicit reading modes: nothing selected reads as the chapter
/// overview (Cluster View, including a cluster-blob tap -- still "look at
/// the whole map", just with one chapter emphasized), a lecture number
/// selected is Lecture View, and a node selected is Topic View.
enum TopicMapViewMode { cluster, lecture, topic }

TopicMapViewMode viewModeForSelection(ClusterSelection? selection) {
  if (selection == null) return TopicMapViewMode.cluster;
  switch (selection.type) {
    case ClusterSelectionType.lecture:
      return TopicMapViewMode.lecture;
    case ClusterSelectionType.node:
      return TopicMapViewMode.topic;
    case ClusterSelectionType.cluster:
      return TopicMapViewMode.cluster;
  }
}

class ClusterSelection {
  const ClusterSelection.node(this.id) : type = ClusterSelectionType.node;
  const ClusterSelection.cluster(this.id) : type = ClusterSelectionType.cluster;
  ClusterSelection.lecture(int lectureNum)
      : type = ClusterSelectionType.lecture,
        id = lectureNum.toString();

  final ClusterSelectionType type;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is ClusterSelection && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);
}

class HighlightSet {
  const HighlightSet({required this.nodeIds, required this.edgeIndexes});

  final Set<String> nodeIds;
  final Set<int> edgeIndexes;

  bool get isActive => nodeIds.isNotEmpty;
}

const _emptyHighlight = HighlightSet(nodeIds: {}, edgeIndexes: {});

HighlightSet computeHighlight(
  TopicMapData data,
  ClusterSelection? selection,
  Map<String, String?> clusterIdByNodeId,
  Map<String, int> lectureNumByNodeId,
) {
  if (selection == null) return _emptyHighlight;

  if (selection.type == ClusterSelectionType.node) {
    final nodeIds = <String>{selection.id};
    final edgeIndexes = <int>{};
    for (var i = 0; i < data.edges.length; i++) {
      final edge = data.edges[i];
      if (edge.sourceId == selection.id || edge.targetId == selection.id) {
        edgeIndexes.add(i);
        nodeIds..add(edge.sourceId)..add(edge.targetId);
      }
    }
    return HighlightSet(nodeIds: nodeIds, edgeIndexes: edgeIndexes);
  }

  if (selection.type == ClusterSelectionType.lecture) {
    // Lecture View: highlight exactly this lecture's own nodes (never their
    // graph neighbors -- unlike node-tap) plus every edge touching one of
    // them, even out to other lectures/clusters. Ghost nodes have no
    // lecture_num, so they're never part of a lecture's highlight.
    final lectureNum = int.parse(selection.id);
    final nodeIds = <String>{
      for (final entry in lectureNumByNodeId.entries)
        if (entry.value == lectureNum) entry.key,
    };
    final edgeIndexes = <int>{
      for (var i = 0; i < data.edges.length; i++)
        if (lectureNumByNodeId[data.edges[i].sourceId] == lectureNum ||
            lectureNumByNodeId[data.edges[i].targetId] == lectureNum)
          i,
    };
    return HighlightSet(nodeIds: nodeIds, edgeIndexes: edgeIndexes);
  }

  final clusterId = selection.id;
  final nodeIds = <String>{
    for (final entry in clusterIdByNodeId.entries)
      if (entry.value == clusterId) entry.key,
  };
  final edgeIndexes = <int>{
    for (var i = 0; i < data.edges.length; i++)
      if (clusterIdByNodeId[data.edges[i].sourceId] == clusterId ||
          clusterIdByNodeId[data.edges[i].targetId] == clusterId)
        i,
  };
  return HighlightSet(nodeIds: nodeIds, edgeIndexes: edgeIndexes);
}
