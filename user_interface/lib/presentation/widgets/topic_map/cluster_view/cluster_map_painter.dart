// Background layer of the Cluster View: the soft cluster "zone" blobs and
// every real edge from the source data (straight lines now -- positions come
// straight out of the force simulation, so there's no layered geometry to
// route around). Node/ghost markers and cluster name labels are separate
// widgets on top (see cluster_map_view.dart) so they can be tapped/animated
// independently of this static paint layer.
//
// Edges are deliberately plain: a single uniform ink color/width, the same
// for every edge regardless of how many other edges connect the same pair
// of clusters, with a small arrowhead for direction. relation_type carries
// no color/dash meaning any more -- it's
// revealed as a text label along the line once zoomed in far enough to read
// it (see _paintEdges).
//
// Past that same zoom threshold, edge width/arrow size and the label's own
// font size are shrunk by detailShrinkFactor (see zoom_detail.dart) so they
// stop growing with the pinch-zoom and instead stay a constant, decluttered
// size on screen.

import 'dart:math';

import 'package:flutter/material.dart';

import '../force_layout/convex_hull.dart';
import '../force_layout/graph_force_simulation.dart';
import '../topic_map_models.dart';
import '../topic_map_style.dart';
import 'cluster_selection.dart';
import 'zoom_detail.dart';

class ClusterMapPainter extends CustomPainter {
  ClusterMapPainter({
    required this.data,
    required this.simulation,
    required this.brightness,
    required this.selection,
    required this.viewMode,
    required this.highlight,
    required this.blobs,
    required this.clusterColorByClusterId,
    required this.ghostNodeIds,
    required this.currentScale,
  });

  final TopicMapData data;
  final GraphForceSimulation simulation;
  final Brightness brightness;
  final ClusterSelection? selection;
  final TopicMapViewMode viewMode;
  final HighlightSet highlight;
  final Map<String, ClusterBlobShape> blobs;
  final Map<String, Color> clusterColorByClusterId;
  final Set<String> ghostNodeIds;
  final double currentScale;

  static const double dimOpacity = 0.4;
  static const double highlightOpacity = 0.95;
  static const double suppressedOpacityTopic = 0.30;
  static const double suppressedOpacityCluster = 0.08;
  static const double baseEdgeWidth = 1.6;
  static const double arrowLength = 10;
  static const double arrowWidth = 7;

  @override
  void paint(Canvas canvas, Size size) {
    _paintClusterBlobs(canvas);
    _paintEdges(canvas);
  }

  void _paintClusterBlobs(Canvas canvas) {
    for (final entry in blobs.entries) {
      final clusterId = entry.key;
      final blob = entry.value;
      final color = clusterColorByClusterId[clusterId] ?? TopicMapPalette.mutedInk(brightness);

      final isSelectedCluster =
          selection?.type == ClusterSelectionType.cluster && selection!.id == clusterId;
      final isAnyClusterSelected = selection?.type == ClusterSelectionType.cluster;
      final fillAlpha = isSelectedCluster ? 0.20 : (isAnyClusterSelected ? 0.04 : 0.08);
      final strokeAlpha = isSelectedCluster ? 0.65 : (isAnyClusterSelected ? 0.18 : 0.38);

      final fillPaint = Paint()..color = color.withValues(alpha: fillAlpha);
      final strokePaint = Paint()
        ..color = color.withValues(alpha: strokeAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelectedCluster ? 2.4 : 1.6;

      if (blob.path != null) {
        canvas.drawPath(blob.path!, fillPaint);
        canvas.drawPath(blob.path!, strokePaint);
      } else if (blob.center != null) {
        canvas.drawCircle(blob.center!, blob.radius, fillPaint);
        canvas.drawCircle(blob.center!, blob.radius, strokePaint);
      } else if (blob.capsuleStart != null && blob.capsuleEnd != null) {
        final capsulePaintFill = Paint()
          ..color = fillPaint.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = blob.radius * 2
          ..strokeCap = StrokeCap.round;
        final capsulePaintStroke = Paint()
          ..color = strokePaint.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(blob.capsuleStart!, blob.capsuleEnd!, capsulePaintFill);
        canvas.drawLine(blob.capsuleStart!, blob.capsuleEnd!, capsulePaintStroke);
      }
    }
  }

  double _radiusFor(String nodeId, double shrink) =>
      (ghostNodeIds.contains(nodeId) ? kGhostNodeRadius : kNodeRadius) * shrink;

  void _paintEdges(Canvas canvas) {
    final hasSelection = selection != null;
    final shrink = detailShrinkFactor(currentScale);
    final showRelationLabels = currentScale >= kDetailShrinkStartScale;

    for (var i = 0; i < data.edges.length; i++) {
      final edge = data.edges[i];
      final from = simulation.nodes[edge.sourceId]?.position;
      final to = simulation.nodes[edge.targetId]?.position;
      if (from == null || to == null) continue;

      final delta = to - from;
      final dist = delta.distance;
      if (dist < 0.001) continue;
      final unit = delta / dist;

      final trimmedStart = from + unit * _radiusFor(edge.sourceId, shrink);
      final trimmedEnd = to - unit * _radiusFor(edge.targetId, shrink);

      final isHighlighted = highlight.edgeIndexes.contains(i);
      final double opacity;
      if (!hasSelection) {
        opacity = dimOpacity;
      } else if (viewMode == TopicMapViewMode.lecture) {
        // Lecture View never dims non-highlighted edges below the Cluster
        // View base look, but edges touching the lecture's own nodes still
        // light up.
        opacity = isHighlighted ? highlightOpacity : dimOpacity;
      } else if (isHighlighted) {
        opacity = highlightOpacity;
      } else {
        opacity = viewMode == TopicMapViewMode.topic ? suppressedOpacityTopic : suppressedOpacityCluster;
      }

      final strokeWidth = baseEdgeWidth * shrink;

      final color = TopicMapPalette.secondaryInk(brightness).withValues(alpha: opacity);
      final linePaint = Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(trimmedStart, trimmedEnd, linePaint);
      _drawArrowhead(canvas, trimmedEnd, unit, Paint()..color = color, shrink);

      if (showRelationLabels) {
        _drawRelationLabel(canvas, trimmedStart, trimmedEnd, edge.humanizedRelationType, opacity, shrink);
      }
    }
  }

  void _drawArrowhead(Canvas canvas, Offset tip, Offset unitDirection, Paint paint, double shrink) {
    final back = tip - unitDirection * (arrowLength * shrink);
    final normal = Offset(-unitDirection.dy, unitDirection.dx) * (arrowWidth * shrink / 2);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(back.dx + normal.dx, back.dy + normal.dy)
      ..lineTo(back.dx - normal.dx, back.dy - normal.dy)
      ..close();
    canvas.drawPath(path, paint..style = PaintingStyle.fill);
  }

  void _drawRelationLabel(
    Canvas canvas,
    Offset start,
    Offset end,
    String label,
    double opacity,
    double shrink,
  ) {
    final mid = Offset.lerp(start, end, 0.5)!;
    var angle = atan2(end.dy - start.dy, end.dx - start.dx);
    // Keep the text upright regardless of which way the edge points.
    if (angle > pi / 2 || angle < -pi / 2) angle += pi;

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 9.5 * shrink,
          fontWeight: FontWeight.w600,
          color: TopicMapPalette.primaryInk(brightness).withValues(alpha: opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.translate(mid.dx, mid.dy);
    canvas.rotate(angle);

    final labelOffset = -8.0 * shrink;
    final bgRect = Rect.fromCenter(
      center: Offset(0, labelOffset),
      width: textPainter.width + 8 * shrink,
      height: textPainter.height + 3 * shrink,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, Radius.circular(4 * shrink)),
      Paint()..color = TopicMapPalette.surface(brightness).withValues(alpha: opacity * 0.9),
    );
    textPainter.paint(canvas, Offset(-textPainter.width / 2, labelOffset - textPainter.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ClusterMapPainter oldDelegate) {
    // Node positions mutate in place inside the (shared) simulation object,
    // so identity/field comparisons can't detect motion -- repainting
    // unconditionally is fine at this node count (~30).
    return true;
  }
}
