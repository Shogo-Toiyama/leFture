// Shared between the painter (drawing cluster blobs) and the gesture
// handler (hit-testing a tap against those same blobs), so both always
// agree on where a cluster's zone actually is.

import 'dart:ui';

import '../force_layout/convex_hull.dart';
import '../force_layout/graph_force_simulation.dart';
import '../topic_map_models.dart';

const double kClusterBlobPadding = 46;

Map<String, ClusterBlobShape> computeClusterBlobs(
  TopicMapData data,
  GraphForceSimulation simulation, {
  double padding = kClusterBlobPadding,
}) {
  final pointsByCluster = <String, List<Offset>>{};

  void addPoint(String? clusterId, String nodeId) {
    if (clusterId == null) return;
    final position = simulation.nodes[nodeId]?.position;
    if (position == null) return;
    pointsByCluster.putIfAbsent(clusterId, () => []).add(position);
  }

  for (final node in data.nodes) {
    addPoint(node.clusterId, node.id);
  }
  for (final ghost in data.ghostNodes) {
    addPoint(ghost.clusterId, ghost.id);
  }

  return {
    for (final entry in pointsByCluster.entries) entry.key: buildClusterBlob(entry.value, padding: padding),
  };
}

Map<String, String?> buildClusterIdByNodeId(TopicMapData data) {
  return {
    for (final node in data.nodes) node.id: node.clusterId,
    for (final ghost in data.ghostNodes) ghost.id: ghost.clusterId,
  };
}

/// Ghost nodes have no lecture_num, so they're deliberately absent here --
/// Lecture View highlighting only ever concerns real topic nodes.
Map<String, int> buildLectureNumByNodeId(TopicMapData data) {
  return {for (final node in data.nodes) node.id: node.lectureNum ?? 0};
}

/// Where a cluster's name sits front-and-center in Cluster View.
Offset clusterBlobCenter(ClusterBlobShape blob) {
  if (blob.center != null) return blob.center!;
  if (blob.capsuleStart != null && blob.capsuleEnd != null) {
    return Offset.lerp(blob.capsuleStart!, blob.capsuleEnd!, 0.5)!;
  }
  if (blob.path != null) return blob.path!.getBounds().center;
  return Offset.zero;
}

/// Where a cluster's name sits just outside its blob (Lecture/Topic View),
/// anchored above the topmost point so it never collides with the nodes
/// packed inside.
Offset clusterBlobOutsideTopAnchor(ClusterBlobShape blob) {
  if (blob.center != null) return blob.center! - Offset(0, blob.radius);
  if (blob.capsuleStart != null && blob.capsuleEnd != null) {
    final top = blob.capsuleStart!.dy < blob.capsuleEnd!.dy ? blob.capsuleStart! : blob.capsuleEnd!;
    final midX = (blob.capsuleStart!.dx + blob.capsuleEnd!.dx) / 2;
    return Offset(midX, top.dy - blob.radius);
  }
  if (blob.path != null) {
    final bounds = blob.path!.getBounds();
    return Offset(bounds.center.dx, bounds.top);
  }
  return Offset.zero;
}

bool clusterBlobContains(ClusterBlobShape shape, Offset point) {
  if (shape.path != null) {
    return shape.path!.contains(point);
  }
  if (shape.center != null) {
    return (point - shape.center!).distance <= shape.radius;
  }
  if (shape.capsuleStart != null && shape.capsuleEnd != null) {
    final a = shape.capsuleStart!;
    final b = shape.capsuleEnd!;
    final ab = b - a;
    final abLenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    final t = abLenSq == 0 ? 0.0 : (((point - a).dx * ab.dx + (point - a).dy * ab.dy) / abLenSq).clamp(0.0, 1.0);
    final proj = a + ab * t;
    return (point - proj).distance <= shape.radius;
  }
  return false;
}

const double kTopicMapContentPadding = 160;
const Size kTopicMapSimulationSeedBounds = Size(1100, 1400);

/// Runs the force layout simulation to full convergence in a pure top-level function.
/// Can be executed inside compute() on a background Isolate to prevent UI jank.
GraphForceSimulation settleTopicMapSimulation(TopicMapData data) {
  final clusterIdByNodeId = buildClusterIdByNodeId(data);
  final nodeIds = [
    for (final n in data.nodes) n.id,
    for (final g in data.ghostNodes) g.id,
  ];
  final edgePairs = [
    for (final e in data.edges) MapEntry(e.sourceId, e.targetId),
    for (final g in data.ghostNodes)
      if (g.derivedFromTopicId != null) MapEntry(g.derivedFromTopicId!, g.id),
  ];

  final simulation = GraphForceSimulation(
    nodeIds: nodeIds,
    clusterIdByNodeId: clusterIdByNodeId,
    edgePairs: edgePairs,
    clusterOrder: [for (final c in data.clusters) c.id],
    bounds: kTopicMapSimulationSeedBounds,
  );

  while (simulation.isRunning) {
    simulation.step();
  }

  final positions = simulation.nodes.values.map((n) => n.position);
  if (positions.isNotEmpty) {
    var minX = double.infinity, minY = double.infinity;
    for (final p in positions) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
    }
    final shift = Offset(-minX + kTopicMapContentPadding, -minY + kTopicMapContentPadding);
    for (final node in simulation.nodes.values) {
      node.position += shift;
    }
  }

  return simulation;
}

