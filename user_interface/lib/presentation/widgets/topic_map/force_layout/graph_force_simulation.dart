// A small force-directed graph layout engine (Fruchterman/d3-force style):
// every pair of nodes repels, edges pull their endpoints toward an ideal
// length, same-cluster pairs get an extra (stronger, shorter) attraction so
// clusters clump together without any hand-written placement rules, and a
// weak centering force keeps the whole graph from drifting off-canvas.
//
// Plain pairwise attract/repel has no notion of "this chain could be drawn
// straight" or "this edge shouldn't cut across an unrelated node" -- those
// are emergent at best. Two extra terms nudge it in that direction without
// changing the overall architecture:
//   - straightening: a degree-2 node (exactly one neighbor on each "side")
//     is pulled toward the midpoint of its two neighbors, so a chain that
//     *could* be a straight line actually tends to become one.
//   - node-edge repulsion: any node that drifts close to an edge it isn't
//     an endpoint of gets pushed off that edge's line, so edges are
//     discouraged from cutting across unrelated nodes.
//
// (A same-cluster pair that's also directly edge-connected gets *both* the
// edge spring and the cluster-affinity spring stacked on it, deliberately --
// tried de-duplicating that once, but cluster cohesion suffered more than
// the extra constraint was worth.)
//
// None of the above has any notion of "cluster" as a group, only of
// individual node pairs -- so nothing stops enough cross-cluster edges from
// pulling two whole clusters into each other as the graph grows. A third,
// cluster-level pass (_separateClusters) runs after every step's node
// forces: it treats each cluster as the circle that bounds its rendered
// blob and, if two clusters' circles overlap, rigidly translates every node
// in each cluster apart until they don't. It's a hard positional
// correction, not a force, so it holds even on the very last step --
// cluster blobs never overlap in what's actually shown.
//
// Uses d3-force's "alpha decay" idea for termination: alpha starts at 1 and
// decays every step; all forces are scaled by it, so the simulation settles
// into a stable layout and then stops on its own instead of running forever
// or having to reason about a noisy kinetic-energy threshold.

import 'dart:collection';
import 'dart:math';
import 'dart:ui';

class ForceNode {
  ForceNode({required this.id, required this.clusterId, required this.position});

  final String id;
  final String? clusterId;
  Offset position;
  Offset velocity = Offset.zero;
}

class GraphForceSimulation {
  GraphForceSimulation({
    required List<String> nodeIds,
    required Map<String, String?> clusterIdByNodeId,
    required List<MapEntry<String, String>> edgePairs,
    required List<String> clusterOrder,
    required Size bounds,
    int seed = 42,
  }) : _bounds = bounds {
    final rand = Random(seed);
    _seedInitialPositions(
      nodeIds: nodeIds,
      clusterIdByNodeId: clusterIdByNodeId,
      edgePairs: edgePairs,
      clusterOrder: clusterOrder,
      bounds: bounds,
      rand: rand,
    );

    _edgePairs = edgePairs.where((e) => nodes.containsKey(e.key) && nodes.containsKey(e.value)).toList();

    final byCluster = <String, List<String>>{};
    for (final id in nodeIds) {
      final clusterId = clusterIdByNodeId[id];
      if (clusterId == null) continue;
      byCluster.putIfAbsent(clusterId, () => []).add(id);
    }
    for (final ids in byCluster.values) {
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          _clusterPairs.add(MapEntry(ids[i], ids[j]));
        }
      }
    }

    final neighbors = <String, List<String>>{};
    for (final e in _edgePairs) {
      neighbors.putIfAbsent(e.key, () => []).add(e.value);
      neighbors.putIfAbsent(e.value, () => []).add(e.key);
    }
    _straightenTriples = [
      for (final entry in neighbors.entries)
        if (entry.value.length == 2) (entry.key, entry.value[0], entry.value[1]),
    ];
  }

  /// Instead of scattering every node uniformly at random, give the
  /// simulation a head start that's already roughly right, using a
  /// "pie slice" (sunburst-style) polar layout around the canvas center:
  ///   - each cluster (in cluster-array order) owns a fixed angular wedge
  ///     of the full circle around the canvas center -- every node in that
  ///     cluster is placed at an angle inside its own wedge only, no matter
  ///     how many BFS layers deep it is. That's what makes it safe to bring
  ///     clusters' home radius in closer together: a long chain of nodes
  ///     can never drift sideways into a neighboring cluster's wedge,
  ///     because its angle is capped by the wedge width, not by how far
  ///     the chain has grown outward.
  ///   - within a cluster's wedge, roots are nodes with no intra-cluster
  ///     parent, plus nodes that are themselves a "parent" for some other
  ///     cluster's node (so cross-cluster edges anchor near the apex, where
  ///     every cluster is closest together, instead of deep inside a
  ///     wedge). A BFS out from the roots (over intra-cluster edges only)
  ///     assigns each remaining node a layer, and layers become concentric
  ///     rings centered on the canvas (radius grows with layer) spread
  ///     evenly across the wedge -- so edge-connected nodes start out near
  ///     each other instead of on opposite sides of the canvas.
  ///   - nodes the BFS never reaches (isolated topics, ghost nodes with no
  ///     edges at all) go in an outer layer beyond the last real one.
  /// The simulation still fully re-settles from here; this only shrinks how
  /// far it has to travel, which is what was producing the big first-second
  /// "wobble" and made it easier for edges to start out tangled.
  void _seedInitialPositions({
    required List<String> nodeIds,
    required Map<String, String?> clusterIdByNodeId,
    required List<MapEntry<String, String>> edgePairs,
    required List<String> clusterOrder,
    required Size bounds,
    required Random rand,
  }) {
    final byCluster = <String, List<String>>{};
    final unclustered = <String>[];
    for (final id in nodeIds) {
      final clusterId = clusterIdByNodeId[id];
      if (clusterId == null) {
        unclustered.add(id);
      } else {
        byCluster.putIfAbsent(clusterId, () => []).add(id);
      }
    }

    final intraNeighbors = <String, List<String>>{};
    final intraInDegree = <String, int>{};
    // Nodes that are the *source* of an edge reaching into another cluster
    // -- i.e. another cluster's node treats this one as its parent. Keeping
    // these near the wedge apex (root ring) too means the cross-cluster
    // edge they anchor starts out short, near the canvas center where every
    // cluster's apex is closest together, instead of deep inside the wedge.
    final crossClusterParentIds = <String>{};
    for (final e in edgePairs) {
      final clusterA = clusterIdByNodeId[e.key];
      final clusterB = clusterIdByNodeId[e.value];
      if (clusterA == null || clusterB == null) continue;
      if (clusterA != clusterB) {
        crossClusterParentIds.add(e.key);
        continue;
      }
      intraNeighbors.putIfAbsent(e.key, () => []).add(e.value);
      intraNeighbors.putIfAbsent(e.value, () => []).add(e.key);
      intraInDegree[e.value] = (intraInDegree[e.value] ?? 0) + 1;
    }

    // clusterOrder comes from data.clusters, but a node's own cluster_id can
    // reference a cluster that isn't in that list (malformed backend data --
    // e.g. a reconciliation pass that placed nodes into a cluster it forgot
    // to also declare). Falling back to `clusterOrder`-only iteration would
    // silently skip those nodes here while _clusterPairs/edge wiring below
    // still expects them to have a position, crashing the simulation later.
    // Appending the orphaned cluster ids as extra wedges keeps every node
    // grouped and positioned instead of dropping it.
    final effectiveClusterOrder = [
      ...clusterOrder,
      for (final id in byCluster.keys)
        if (!clusterOrder.contains(id)) id,
    ];

    final center = Offset(bounds.width / 2, bounds.height / 2);
    final homeRadius = min(bounds.width, bounds.height) * 0.22;
    final clusterCount = effectiveClusterOrder.length;
    final wedgeWidth = clusterCount > 0 ? (2 * pi / clusterCount) : (2 * pi);
    // Leave a gap between neighboring wedges so a fully-spread layer
    // doesn't sit flush against the next cluster's boundary.
    final wedgeHalfSpread = wedgeWidth / 2 * 0.8;

    for (var ci = 0; ci < effectiveClusterOrder.length; ci++) {
      final ids = byCluster[effectiveClusterOrder[ci]];
      if (ids == null || ids.isEmpty) continue;

      final wedgeCenterAngle = clusterCount <= 1 ? -pi / 2 : (2 * pi * ci / clusterCount) - pi / 2;

      final roots = [
        for (final id in ids)
          if ((intraInDegree[id] ?? 0) == 0 || crossClusterParentIds.contains(id)) id,
      ];
      final effectiveRoots = roots.isEmpty ? [ids.first] : roots;

      final layerOf = <String, int>{};
      final queue = Queue<String>();
      for (final root in effectiveRoots) {
        layerOf[root] = 0;
        queue.add(root);
      }
      while (queue.isNotEmpty) {
        final current = queue.removeFirst();
        final currentLayer = layerOf[current]!;
        for (final neighbor in intraNeighbors[current] ?? const <String>[]) {
          if (layerOf.containsKey(neighbor)) continue;
          layerOf[neighbor] = currentLayer + 1;
          queue.add(neighbor);
        }
      }
      final maxLayer = layerOf.values.isEmpty ? 0 : layerOf.values.reduce(max);
      for (final id in ids) {
        layerOf.putIfAbsent(id, () => maxLayer + 1);
      }

      final byLayer = <int, List<String>>{};
      for (final id in ids) {
        byLayer.putIfAbsent(layerOf[id]!, () => []).add(id);
      }

      for (final entry in byLayer.entries) {
        final layer = entry.key;
        final layerIds = entry.value;
        final n = layerIds.length;
        final radius = homeRadius + layer * 75.0;
        for (var k = 0; k < n; k++) {
          final angleOffset = n <= 1 ? 0.0 : wedgeHalfSpread * (2 * (k + 0.5) / n - 1);
          final angle = wedgeCenterAngle + angleOffset;
          final position = center + Offset.fromDirection(angle, radius);
          nodes[layerIds[k]] = ForceNode(id: layerIds[k], clusterId: effectiveClusterOrder[ci], position: position);
        }
      }
    }

    for (final id in unclustered) {
      final position = Offset(
        bounds.width * 0.5 + (rand.nextDouble() - 0.5) * bounds.width * 0.7,
        bounds.height * 0.5 + (rand.nextDouble() - 0.5) * bounds.height * 0.7,
      );
      nodes[id] = ForceNode(id: id, clusterId: null, position: position);
    }
  }

  final Map<String, ForceNode> nodes = {};
  late final List<MapEntry<String, String>> _edgePairs;
  final List<MapEntry<String, String>> _clusterPairs = [];

  /// (nodeId, neighborA, neighborB) for every degree-2 node -- candidates to
  /// be pulled straight between their two neighbors.
  late final List<(String, String, String)> _straightenTriples;

  final Size _bounds;
  final Random _jitterRandom = Random(7);

  static const double repulsionK = 52000;
  static const double edgeSpringK = 0.05;
  static const double edgeIdealLength = 185;
  static const double clusterSpringK = 0.14;
  static const double clusterIdealLength = 140;
  static const double centeringK = 0.008;
  static const double velocityDamping = 0.80;
  static const double minDistance = 1.0;
  static const double maxForcePerStep = 70;

  static const double straightenK = 0.06;
  static const double edgeRepulsionK = 9000;
  static const double edgeClearance = 42;

  // Keep in sync with kClusterBlobPadding in cluster_geometry.dart -- this is
  // the same margin the rendered blob is inflated by, so "these two circles
  // don't overlap" in the simulation means "these two blobs don't overlap"
  // on screen. force_layout/ doesn't depend on cluster_view/, so it's
  // duplicated rather than shared.
  static const double clusterBoundingPadding = 46;
  static const double clusterSeparationGap = 24;

  static const double alphaDecay = 0.965;
  static const double alphaMin = 0.001;

  double alpha = 1.0;
  bool get isRunning => alpha > alphaMin;

  /// Advances the simulation by one discrete tick. Frame-rate independent
  /// dt isn't used deliberately -- like d3-force, one call is one "tick",
  /// so the settle time is a fixed number of animation frames.
  void step() {
    if (!isRunning) return;

    final forces = <String, Offset>{for (final id in nodes.keys) id: Offset.zero};
    final ids = nodes.keys.toList(growable: false);

    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final a = nodes[ids[i]]!;
        final b = nodes[ids[j]]!;
        var delta = a.position - b.position;
        var dist = delta.distance;
        if (dist < minDistance) {
          final angle = _jitterRandom.nextDouble() * 2 * pi;
          delta = Offset(cos(angle), sin(angle)) * minDistance;
          dist = minDistance;
        }
        final forceMag = repulsionK / (dist * dist);
        final f = delta / dist * forceMag;
        forces[ids[i]] = forces[ids[i]]! + f;
        forces[ids[j]] = forces[ids[j]]! - f;
      }
    }

    void applySpring(String aId, String bId, double idealLength, double springK) {
      final a = nodes[aId]!;
      final b = nodes[bId]!;
      var delta = b.position - a.position;
      var dist = delta.distance;
      if (dist < 0.001) dist = 0.001;
      final forceMag = springK * (dist - idealLength);
      final f = delta / dist * forceMag;
      forces[aId] = forces[aId]! + f;
      forces[bId] = forces[bId]! - f;
    }

    for (final e in _edgePairs) {
      applySpring(e.key, e.value, edgeIdealLength, edgeSpringK);
    }
    for (final p in _clusterPairs) {
      applySpring(p.key, p.value, clusterIdealLength, clusterSpringK);
    }

    for (final (nodeId, neighborA, neighborB) in _straightenTriples) {
      final posA = nodes[neighborA]?.position;
      final posB = nodes[neighborB]?.position;
      if (posA == null || posB == null) continue;
      final midpoint = (posA + posB) * 0.5;
      final f = (midpoint - nodes[nodeId]!.position) * straightenK;
      forces[nodeId] = forces[nodeId]! + f;
    }

    for (final e in _edgePairs) {
      final segStart = nodes[e.key]!.position;
      final segEnd = nodes[e.value]!.position;
      final segVector = segEnd - segStart;
      final segLenSq = segVector.dx * segVector.dx + segVector.dy * segVector.dy;
      if (segLenSq < 1.0) continue;

      for (final id in ids) {
        if (id == e.key || id == e.value) continue;
        final point = nodes[id]!.position;
        final t = (((point - segStart).dx * segVector.dx + (point - segStart).dy * segVector.dy) / segLenSq)
            .clamp(0.0, 1.0);
        final closest = segStart + segVector * t;
        var delta = point - closest;
        var dist = delta.distance;
        if (dist >= edgeClearance) continue;
        if (dist < 0.5) {
          final angle = _jitterRandom.nextDouble() * 2 * pi;
          delta = Offset(cos(angle), sin(angle));
          dist = 1.0;
        }
        final forceMag = edgeRepulsionK / (dist * dist);
        forces[id] = forces[id]! + delta / dist * forceMag;
      }
    }

    final center = Offset(_bounds.width / 2, _bounds.height / 2);
    for (final id in ids) {
      forces[id] = forces[id]! + (center - nodes[id]!.position) * centeringK;
    }

    for (final id in ids) {
      final node = nodes[id]!;
      var f = forces[id]! * alpha;
      final fLen = f.distance;
      if (fLen > maxForcePerStep) {
        f = f / fLen * maxForcePerStep;
      }
      node.velocity = (node.velocity + f) * velocityDamping;
      node.position = node.position + node.velocity;
    }

    _separateClusters();

    alpha *= alphaDecay;
  }

  /// Node-level springs (edges, cluster affinity) have no notion of "these
  /// are two different clusters" -- enough cross-cluster edges can pull two
  /// clusters into each other no matter how strong individual repulsion is.
  /// This runs as a positional correction *after* the forces above have
  /// already moved everything, every single step: treat each cluster as the
  /// circle that (approximately) bounds its rendered blob -- centroid, plus
  /// the farthest member node's distance from it, plus the same padding the
  /// blob is drawn with -- and if two clusters' circles overlap, push both
  /// clusters (translating every one of their nodes together, rigidly)
  /// apart by exactly the overlap. Unlike a spring, this is a hard
  /// constraint, not a force balance: it runs every step, including the
  /// last one, so the final on-screen layout can never have two cluster
  /// blobs overlapping, regardless of how strongly other forces disagree.
  void _separateClusters() {
    final byCluster = <String, List<String>>{};
    for (final node in nodes.values) {
      final clusterId = node.clusterId;
      if (clusterId == null) continue;
      byCluster.putIfAbsent(clusterId, () => []).add(node.id);
    }
    if (byCluster.length < 2) return;

    final clusterIds = byCluster.keys.toList(growable: false);
    final centroids = <String, Offset>{};
    final radii = <String, double>{};
    for (final clusterId in clusterIds) {
      final ids = byCluster[clusterId]!;
      var sum = Offset.zero;
      for (final id in ids) {
        sum += nodes[id]!.position;
      }
      final centroid = sum / ids.length.toDouble();
      var maxDist = 0.0;
      for (final id in ids) {
        final d = (nodes[id]!.position - centroid).distance;
        if (d > maxDist) maxDist = d;
      }
      centroids[clusterId] = centroid;
      radii[clusterId] = maxDist + clusterBoundingPadding;
    }

    for (var i = 0; i < clusterIds.length; i++) {
      for (var j = i + 1; j < clusterIds.length; j++) {
        final a = clusterIds[i];
        final b = clusterIds[j];
        final centerA = centroids[a]!;
        final centerB = centroids[b]!;
        var delta = centerB - centerA;
        var dist = delta.distance;
        final minSeparation = radii[a]! + radii[b]! + clusterSeparationGap;
        if (dist >= minSeparation) continue;
        if (dist < 0.001) {
          final angle = _jitterRandom.nextDouble() * 2 * pi;
          delta = Offset(cos(angle), sin(angle));
          dist = 1.0;
        }
        final push = delta / dist * ((minSeparation - dist) / 2);
        for (final id in byCluster[a]!) {
          nodes[id]!.position -= push;
        }
        for (final id in byCluster[b]!) {
          nodes[id]!.position += push;
        }
      }
    }
  }
}
