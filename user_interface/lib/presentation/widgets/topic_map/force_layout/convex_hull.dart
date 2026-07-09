// Convex hull (Andrew's monotone chain), polygon inflate, and a smooth-blob
// Path builder -- used to draw the "cluster zone" outlines in the Cluster
// View (hit-testing uses Path.contains on the same shapes; see
// cluster_geometry.dart).

import 'dart:ui';

/// Returns the convex hull of [points] in counter-clockwise order.
/// Degenerate inputs (0-2 distinct points) are returned as-is; callers should
/// special-case those (see [clusterBlobPath]).
List<Offset> convexHull(List<Offset> points) {
  final unique = <Offset>{...points}.toList();
  if (unique.length < 3) return unique;

  unique.sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));

  double cross(Offset o, Offset a, Offset b) =>
      (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

  final lower = <Offset>[];
  for (final p in unique) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }

  final upper = <Offset>[];
  for (final p in unique.reversed) {
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }

  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

/// Pushes each hull vertex outward from the hull's centroid by [padding].
/// Not a mathematically exact uniform offset, but close enough for a soft
/// "cluster zone" outline at the paddings this UI uses.
List<Offset> inflatePolygon(List<Offset> hull, double padding) {
  if (hull.isEmpty) return hull;
  final centroid = hull.reduce((a, b) => a + b) / hull.length.toDouble();
  return hull.map((p) {
    final dir = p - centroid;
    final len = dir.distance;
    if (len < 0.001) return p + const Offset(1, 0) * padding;
    return p + dir / len * padding;
  }).toList();
}

/// Builds the visual "cluster zone" blob around [rawPoints] (the cluster's
/// current node positions), already inflated by [padding]:
///   - 0 points: empty path (caller should skip drawing).
///   - 1 point: a plain circle.
///   - 2 points: a capsule (handled by the caller via a round-capped stroke,
///     since that's simpler than constructing the path by hand -- see
///     [ClusterBlobShape]).
///   - 3+ points: convex hull, inflated, smoothed through edge midpoints so
///     it reads as a soft blob rather than a faceted polygon.
class ClusterBlobShape {
  const ClusterBlobShape.circle(this.center, this.radius)
      : capsuleStart = null,
        capsuleEnd = null,
        path = null;

  const ClusterBlobShape.capsule(this.capsuleStart, this.capsuleEnd, this.radius)
      : center = null,
        path = null;

  const ClusterBlobShape.path(this.path)
      : center = null,
        capsuleStart = null,
        capsuleEnd = null,
        radius = 0;

  final Offset? center;
  final Offset? capsuleStart;
  final Offset? capsuleEnd;
  final Path? path;
  final double radius;
}

ClusterBlobShape buildClusterBlob(List<Offset> points, {required double padding}) {
  if (points.isEmpty) {
    return const ClusterBlobShape.circle(Offset.zero, 0);
  }
  if (points.length == 1) {
    return ClusterBlobShape.circle(points.first, padding);
  }

  final hull = convexHull(points);
  if (hull.length < 3) {
    // Collinear or 2-point case: a capsule between the two extremes reads
    // better than a degenerate sliver polygon.
    var a = points.first;
    var b = points.first;
    var maxDist = 0.0;
    for (final p in points) {
      for (final q in points) {
        final d = (p - q).distance;
        if (d > maxDist) {
          maxDist = d;
          a = p;
          b = q;
        }
      }
    }
    return ClusterBlobShape.capsule(a, b, padding);
  }

  final inflated = inflatePolygon(hull, padding);
  return ClusterBlobShape.path(_smoothClosedPath(inflated));
}

/// Rounds a closed polygon by routing through each edge's midpoint with a
/// quadratic curve toward the original vertex -- a cheap, standard trick for
/// turning a faceted polygon into a soft blob.
Path _smoothClosedPath(List<Offset> pts) {
  final path = Path();
  final n = pts.length;
  Offset mid(Offset a, Offset b) => Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

  final firstMid = mid(pts[n - 1], pts[0]);
  path.moveTo(firstMid.dx, firstMid.dy);
  for (var i = 0; i < n; i++) {
    final current = pts[i];
    final next = pts[(i + 1) % n];
    final m = mid(current, next);
    path.quadraticBezierTo(current.dx, current.dy, m.dx, m.dy);
  }
  path.close();
  return path;
}
