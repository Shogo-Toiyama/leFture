// Cluster View / Lecture View / Topic View: three explicit readings of the
// same force-directed canvas, distinguished purely by what's selected --
// nothing (Cluster View), a lecture number (Lecture View), or a node (Topic
// View). Nodes repel each other, real edges pull their endpoints together,
// and same-cluster nodes get an extra attraction so chapters clump on their
// own -- no hand-written placement rules. The simulation is run to full
// convergence synchronously in initState (see GraphForceSimulation.alpha),
// so the very first frame already shows the settled layout -- nothing
// animates into place on screen.
//
// The simulation's own `bounds` (_simulationSeedBounds) only shapes the
// *initial* radial seeding (see GraphForceSimulation._seedInitialPositions)
// -- nothing clamps where forces can actually settle nodes afterward, so a
// bigger/denser graph legitimately ends up larger than that seed box. The
// render canvas is therefore a *separate*, second size: computed from the
// real bounding box of the settled positions (plus padding) right after
// convergence, with every node position shifted so that box starts at
// (0,0). That's what makes "the whole map, never clipped, regardless of
// graph size" possible without an actually-infinite canvas -- the canvas is
// just sized to exactly fit what's there. The Stack it's drawn in also
// doesn't clip (see build()), as a second line of defense.
//
// On top of that, the very first frame sets the InteractiveViewer's
// transform to center and scale-to-fit that canvas in whatever viewport
// size is available (_fitToContent), so the map opens already framed
// instead of pinned to its top-left corner. It only runs once, before the
// user's first pan/zoom gesture.
//
// InteractiveViewer has its own hardcoded minimum-zoom floor, independent
// of the `minScale` we pass it: on every scale gesture it clamps to
// max(viewport.width / boundaryRect.width, viewport.height /
// boundaryRect.height), where boundaryRect is the canvas inflated by
// `boundaryMargin` (see _matrixScale in the framework's
// interactive_viewer.dart). That's a "cover" scale (the larger of the two
// axis ratios, so the boundary always fills the viewport with no gap);
// our own fit-to-content scale is a "contain" scale (the *smaller* axis
// ratio, so the whole canvas is visible). Those two only agree when the
// canvas and viewport share the same aspect ratio -- otherwise the
// framework's floor is strictly higher, so the instant a scale/pan
// gesture starts, it snaps the view up to that floor, discarding our fit.
// _computeBoundaryMargin below picks a margin that inflates the canvas to
// exactly the aspect ratio needed for the framework's floor to land on
// our own fit scale, so the two can't disagree.

import 'dart:math' show max, min;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture_viewer/lecture_viewer_data_provider.dart';
import 'package:lecture_companion_ui/core/utils/sid_citation.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

import '../force_layout/graph_force_simulation.dart';
import '../topic_map_models.dart';
import '../topic_map_style.dart';
import 'cluster_geometry.dart';
import 'cluster_map_painter.dart';
import 'cluster_selection.dart';
import 'lecture_topic_detail_panel.dart';
import 'zoom_detail.dart';

/// Above this zoom scale, the big centered cluster title (Cluster View)
/// hides -- it's an overview cue, not useful once you've zoomed into detail.
const double _kClusterCenterLabelMaxScale = 1.15;

const double _kMinZoomScale = 0.3;
const double _kMaxZoomScale = 2.5;

/// Room left around the outermost node's settled position when sizing the
/// render canvas -- has to clear the cluster blob padding (46, see
/// kClusterBlobPadding) plus its outside label and a little breathing room.
const double _kContentPadding = 160;

class ClusterMapView extends ConsumerStatefulWidget {
  const ClusterMapView({
    super.key,
    required this.data,
    required this.courseId,
    this.initialSelection,
    this.interactive = true,
  });

  final TopicMapData data;

  /// Needed to look up the real Lecture (title/summary/id) behind a
  /// lecture_num when showing the Lecture/Topic View detail sheet -- see
  /// _showLectureOrTopicSheet.
  final String courseId;

  /// Selection to open with instead of the default Cluster View overview --
  /// e.g. `ClusterSelection.lecture(n)` to embed a Lecture-View preview.
  final ClusterSelection? initialSelection;

  /// When false, renders as a static, non-interactive preview: no top
  /// overlay (mode title/lecture chips), no pan/zoom/tap, no detail sheet.
  /// Meant for small embedded thumbnails (e.g. a course page card) where
  /// the enclosing widget owns tap handling instead.
  final bool interactive;

  @override
  ConsumerState<ClusterMapView> createState() => _ClusterMapViewState();
}

/// Duration/curve for the camera flying to frame a just-selected lecture's
/// nodes (see [_ClusterMapViewState._animateToLectureBounds]).
const Duration _kLectureFitAnimationDuration = Duration(milliseconds: 450);
const Curve _kLectureFitAnimationCurve = Curves.easeInOutCubic;

class _ClusterMapViewState extends ConsumerState<ClusterMapView>
    with TickerProviderStateMixin {
  /// Only shapes the initial radial seeding -- see the file-level comment.
  static const Size _simulationSeedBounds = Size(1100, 1400);

  late final GraphForceSimulation _simulation;
  late final Map<String, String?> _clusterIdByNodeId;
  late final Map<String, int> _lectureNumByNodeId;
  late final Set<String> _ghostNodeIds;

  /// Computed from the settled layout's actual bounding box, not the seed
  /// bounds above -- see the file-level comment.
  late final Size _renderCanvasSize;

  final TransformationController _transformController =
      TransformationController();
  ClusterSelection? _selection;
  bool _hasScheduledFitToContent = false;
  AnimationController? _lectureFitController;

  /// The last viewport size build() actually laid out with (see the
  /// LayoutBuilder in build()) -- cached so gesture callbacks like
  /// _selectLecture, which run outside of build, can still compute a fit
  /// without relying on MediaQuery (wrong when embedded in a constrained
  /// preview smaller than the full screen).
  Size _lastViewportSize = Size.zero;

  /// Drives the bottom detail panel (see build()'s Column/Expanded split)
  /// -- null hides it. Resolved asynchronously by _loadPanelData since it
  /// needs the real Lecture (and, for Topic View, LectureTopic) rows behind
  /// a lecture_num/topic_num, not just what's in the map's own json.
  _PanelData? _panelData;

  /// Current panel height in px; 0 when closed. Opens at [_panelMinExtent]
  /// (small, map still mostly visible/draggable) and can be dragged up to
  /// [_panelMaxExtent] via the panel's own drag handle -- see
  /// _onPanelDragUpdate/_onPanelDragEnd. Both extents are recomputed every
  /// build from the current layout size (see build()'s LayoutBuilder) and
  /// cached here so the drag callbacks, which run outside of build, can
  /// clamp against the latest values.
  double _panelExtent = 0;
  double _panelMinExtent = 0;
  double _panelMaxExtent = 0;

  /// While actively dragging, height changes apply with zero animation
  /// duration so the panel tracks the finger 1:1; released drags (and the
  /// initial open) snap/animate over a short duration instead.
  bool _isDraggingPanel = false;

  @override
  void initState() {
    super.initState();
    _selection = widget.initialSelection;
    final data = widget.data;
    _clusterIdByNodeId = buildClusterIdByNodeId(data);
    _lectureNumByNodeId = buildLectureNumByNodeId(data);
    _ghostNodeIds = {for (final g in data.ghostNodes) g.id};

    final nodeIds = [
      for (final n in data.nodes) n.id,
      for (final g in data.ghostNodes) g.id,
    ];
    final edgePairs = [
      for (final e in data.edges) MapEntry(e.sourceId, e.targetId),
      // Ghost nodes have no entry in data.edges, but derived_from_topic_id
      // is effectively an edge too -- feeding it into the simulation as a
      // spring pulls the ghost near the real topic it was predicted from,
      // instead of it only being held in place by cluster affinity.
      for (final g in data.ghostNodes)
        if (g.derivedFromTopicId != null) MapEntry(g.derivedFromTopicId!, g.id),
    ];

    _simulation = GraphForceSimulation(
      nodeIds: nodeIds,
      clusterIdByNodeId: _clusterIdByNodeId,
      edgePairs: edgePairs,
      clusterOrder: [for (final c in data.clusters) c.id],
      bounds: _simulationSeedBounds,
    );

    // Run to full convergence before the first frame instead of animating
    // step-by-step on screen -- at this node count it settles in a few
    // milliseconds, so there's nothing to gain from watching it happen and
    // it removes the initial "wobble" entirely.
    while (_simulation.isRunning) {
      _simulation.step();
    }
    _renderCanvasSize = _normalizeSettledPositions();

    _transformController.addListener(_onTransformChanged);
  }

  /// Shifts every settled node position so the content's own bounding box
  /// (plus padding) starts at (0,0), and returns that box's size -- the
  /// render canvas is sized to exactly fit the graph however big it grew,
  /// instead of a fixed guess that a denser graph can outgrow.
  Size _normalizeSettledPositions() {
    final positions = _simulation.nodes.values.map((n) => n.position);
    if (positions.isEmpty) return _simulationSeedBounds;

    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in positions) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }

    final shift = Offset(-minX + _kContentPadding, -minY + _kContentPadding);
    for (final node in _simulation.nodes.values) {
      node.position += shift;
    }
    return Size(
      maxX - minX + _kContentPadding * 2,
      maxY - minY + _kContentPadding * 2,
    );
  }

  /// The scale at which the whole render canvas exactly fits inside
  /// [viewportSize] (with a little margin), *before* clamping to any zoom
  /// limit -- shared by the initial fit-to-content transform and by the
  /// InteractiveViewer's own `minScale`, so the two can never disagree
  /// about how far out "fully zoomed out" needs to go.
  double _computeFitScale(Size viewportSize) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) return 1.0;
    final scaleX = viewportSize.width / _renderCanvasSize.width;
    final scaleY = viewportSize.height / _renderCanvasSize.height;
    return min(scaleX, scaleY) * 0.92;
  }

  /// `minScale` should never be *more restrictive* than what's needed to
  /// see the whole map -- otherwise a large enough graph can outgrow the
  /// fixed floor and permanently overflow the viewport no matter how far
  /// out you zoom (that was the actual bug: a hardcoded 0.3 floor stopped
  /// being able to fit an 8-cluster graph, which needed ~0.22 to fit).
  /// Tying it to the same fit-scale calculation instead of a fixed number
  /// means it can never happen again regardless of how big the graph gets.
  double _effectiveMinScale(Size viewportSize) =>
      min(_kMinZoomScale, _computeFitScale(viewportSize));

  /// Picks `boundaryMargin` so InteractiveViewer's own internal zoom-out
  /// floor (see the file-level comment) lands on our `_computeFitScale`
  /// instead of above it. Solving boundaryRect = canvas + 2*margin for
  /// "viewport / boundaryRect == fitScale" on each axis independently
  /// gives the margin that axis needs; a small constant is added on top
  /// so the framework's floor sits *just under* fitScale rather than
  /// exactly on it, which would risk a one-pixel jump from floating-point
  /// rounding. Also gives a little pan headroom beyond the exact fit, like
  /// the fixed margin this replaces used to.
  EdgeInsets _computeBoundaryMargin(Size viewportSize) {
    final fitScale = _computeFitScale(viewportSize);
    if (fitScale <= 0) return const EdgeInsets.all(40);

    const extraSlack = 24.0;
    final requiredWidth = viewportSize.width / fitScale;
    final requiredHeight = viewportSize.height / fitScale;
    final marginX =
        max(0.0, (requiredWidth - _renderCanvasSize.width) / 2) + extraSlack;
    final marginY =
        max(0.0, (requiredHeight - _renderCanvasSize.height) / 2) + extraSlack;
    return EdgeInsets.symmetric(horizontal: marginX, vertical: marginY);
  }

  /// Centers and scales the view to fit the whole (now exactly-sized)
  /// canvas in [viewportSize]. Runs once, from the first post-frame
  /// callback after this widget lays out -- scheduled from build() since
  /// the viewport size isn't known any earlier, guarded so it never
  /// overrides a transform the user has since set by panning/zooming.
  void _fitToContent(Size viewportSize) {
    if (!mounted || viewportSize.width <= 0 || viewportSize.height <= 0) return;
    _transformController.value = _matrixForBounds(
      Offset.zero & _renderCanvasSize,
      viewportSize,
      fitScaleOverride: _computeFitScale(viewportSize),
    );
  }

  /// Builds the transform that centers and scales [targetBounds] (in canvas
  /// coordinates) to fit inside [viewportSize], clamped to this view's zoom
  /// limits. Shared by the initial whole-canvas fit ([_fitToContent], which
  /// passes its own already-computed fit scale to stay in lockstep with
  /// [_effectiveMinScale]/[_computeBoundaryMargin]) and by
  /// [_animateToLectureBounds] (which fits a subset of the canvas instead).
  Matrix4 _matrixForBounds(
    Rect targetBounds,
    Size viewportSize, {
    double? fitScaleOverride,
  }) {
    final rawScale =
        fitScaleOverride ??
        (targetBounds.width <= 0 || targetBounds.height <= 0
            ? 1.0
            : min(
                    viewportSize.width / targetBounds.width,
                    viewportSize.height / targetBounds.height,
                  ) *
                  0.85);
    final scale = rawScale.clamp(
      _effectiveMinScale(viewportSize),
      _kMaxZoomScale,
    );

    final contentCenter = targetBounds.center;
    final viewportCenter = Offset(
      viewportSize.width / 2,
      viewportSize.height / 2,
    );
    final tx = viewportCenter.dx - contentCenter.dx * scale;
    final ty = viewportCenter.dy - contentCenter.dy * scale;

    // Column-major: scale on the diagonal (all three axes, so
    // Matrix4.getMaxScaleOnAxis() -- which currentScale is read from --
    // reports fitScale instead of being dragged up to the unscaled z
    // axis's length of 1), translation in the last column.
    return Matrix4(
      scale,
      0,
      0,
      0, //
      0,
      scale,
      0,
      0, //
      0,
      0,
      scale,
      0, //
      tx,
      ty,
      0,
      1, //
    );
  }

  /// Bounding box (in canvas coordinates) of every real node belonging to
  /// [lectureNum] -- ghosts have no lecture_num so they never factor in,
  /// matching the same "real nodes only" rule the highlight itself uses
  /// (see computeHighlight's lecture branch).
  Rect? _lectureNodeBounds(int lectureNum) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    var found = false;
    for (final entry in _lectureNumByNodeId.entries) {
      if (entry.value != lectureNum) continue;
      final position = _simulation.nodes[entry.key]?.position;
      if (position == null) continue;
      found = true;
      if (position.dx < minX) minX = position.dx;
      if (position.dy < minY) minY = position.dy;
      if (position.dx > maxX) maxX = position.dx;
      if (position.dy > maxY) maxY = position.dy;
    }
    if (!found) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(kNodeRadius + 60);
  }

  /// Flies the camera to frame exactly [lectureNum]'s own nodes, so entering
  /// Lecture View doesn't leave the previous (possibly unrelated) framing on
  /// screen. Cancels/replaces any fit animation already in flight so rapid
  /// lecture switches don't queue up stale animations.
  void _animateToLectureBounds(int lectureNum, Size viewportSize) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) return;
    final bounds = _lectureNodeBounds(lectureNum);
    if (bounds == null) return;

    final target = _matrixForBounds(bounds, viewportSize);
    final from = _transformController.value.clone();

    // Swap out any in-flight fit animation first, and drop our reference to
    // it -- otherwise both this dispose and the new controller's own
    // completion-triggered dispose below could end up disposing the same
    // (old) instance twice.
    final oldController = _lectureFitController;
    _lectureFitController = null;
    oldController?.dispose();

    final controller = AnimationController(
      vsync: this,
      duration: _kLectureFitAnimationDuration,
    );
    _lectureFitController = controller;
    final animation = Matrix4Tween(begin: from, end: target).animate(
      CurvedAnimation(parent: controller, curve: _kLectureFitAnimationCurve),
    );
    animation.addListener(() {
      if (!mounted) return;
      _transformController.value = animation.value;
    });
    // One-shot controller: dispose itself once the fly-to finishes instead
    // of lingering until the next lecture switch or widget teardown --
    // whichever tears the widget down later would otherwise try to dispose
    // an already-disposed controller.
    controller.addStatusListener((status) {
      if (status != AnimationStatus.completed &&
          status != AnimationStatus.dismissed) {
        return;
      }
      if (identical(_lectureFitController, controller)) {
        _lectureFitController = null;
      }
      controller.dispose();
    });
    controller.forward();
  }

  void _onTransformChanged() => setState(() {});

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    _lectureFitController?.dispose();
    super.dispose();
  }

  void _selectNode(String nodeId) {
    final wasSelected =
        _selection?.type == ClusterSelectionType.node && _selection!.id == nodeId;
    setState(() {
      final next = ClusterSelection.node(nodeId);
      _selection = _selection == next ? null : next;
    });
    if (wasSelected || !widget.interactive) {
      if (wasSelected) {
        setState(() {
          _panelData = null;
          _panelExtent = 0;
        });
      }
      return;
    }

    // Ghost nodes are predictions, not real recorded topics -- they have no
    // lecture_num/summary/lecture to jump to, so they don't get a detail
    // panel (buildLectureNumByNodeId deliberately excludes them too).
    TopicMapNode? node;
    for (final n in widget.data.nodes) {
      if (n.id == nodeId) {
        node = n;
        break;
      }
    }
    if (node != null) {
      _loadPanelData(lectureNum: node.lectureNum, topicNode: node);
    } else {
      setState(() {
        _panelData = null;
        _panelExtent = 0;
      });
    }
  }

  void _selectLecture(int lectureNum) {
    final wasSameLecture =
        _selection?.type == ClusterSelectionType.lecture &&
        _selection!.id == lectureNum.toString();
    setState(() {
      final next = ClusterSelection.lecture(lectureNum);
      _selection = _selection == next ? null : next;
    });
    if (wasSameLecture || _selection == null) {
      setState(() {
        _panelData = null;
        _panelExtent = 0;
      });
      return;
    }
    _animateToLectureBounds(lectureNum, _lastViewportSize);
    if (widget.interactive) {
      _loadPanelData(lectureNum: lectureNum, topicNode: null);
    }
  }

  /// Trailing number in a topic_id like "node_lc1_3" -> 3 (the topic's
  /// position within its lecture) -- see task_runners.py's
  /// `f"node_lc{lecture_num}_{i}"` for where that shape comes from.
  static final RegExp _topicNumPattern = RegExp(r'_(\d+)$');

  int? _topicNumFromTopicId(String topicId) {
    return int.tryParse(_topicNumPattern.firstMatch(topicId)?.group(1) ?? '');
  }

  String _lectureDisplayTitle(Lecture lecture) {
    if (lecture.title?.trim().isNotEmpty == true) return lecture.title!.trim();
    if (lecture.titleGenerated?.trim().isNotEmpty == true) return lecture.titleGenerated!.trim();
    return 'Untitled Lecture';
  }

  String? _clusterNameFor(String? clusterId) {
    if (clusterId == null) return null;
    for (final c in widget.data.clusters) {
      if (c.id == clusterId) return c.name;
    }
    return null;
  }

  String? _nodeTitleById(String nodeId) {
    for (final n in widget.data.nodes) {
      if (n.id == nodeId) return n.title;
    }
    return null;
  }

  /// Every edge touching [nodeId], resolved to the other endpoint's title
  /// -- edges only ever connect real nodes (see topic_map_models.dart), so
  /// ghost nodes never show up here.
  List<RelatedTopicEdge> _relatedTopicsFor(String nodeId) {
    final related = <RelatedTopicEdge>[];
    for (final e in widget.data.edges) {
      if (e.sourceId == nodeId) {
        final title = _nodeTitleById(e.targetId);
        if (title != null) {
          related.add(RelatedTopicEdge(title: title, relationType: e.humanizedRelationType, isOutgoing: true));
        }
      } else if (e.targetId == nodeId) {
        final title = _nodeTitleById(e.sourceId);
        if (title != null) {
          related.add(RelatedTopicEdge(title: title, relationType: e.humanizedRelationType, isOutgoing: false));
        }
      }
    }
    return related;
  }

  /// Resolves the bottom panel's content and stores it in [_panelData].
  /// Lecture View: title comes from the local `lectures` row, but summary
  /// is fetched fresh from Supabase (see lectureProvider) -- summary is
  /// AI-generated well after recording, and the local-first Drift table
  /// (LocalLectures in app_database.dart) only mirrors recording-time
  /// fields, so it's always null there.
  /// Topic View: title is the map node's own title, but its summary has to
  /// come from `lecture_topics.summary` -- the map itself never carries
  /// one. topicNum (from the topic_id) is 1-based position among *only*
  /// this lecture's ACADEMIC topics (see task_runners.py's
  /// `academic_topics` filter), whereas lecture_topics.index is the row's
  /// raw position among *all* topic types (ACADEMIC and LOGISTICS mixed) --
  /// so the match has to replicate that same "filter to ACADEMIC, then
  /// take the Nth" step client-side rather than compare index directly.
  ///
  /// Lectures are streamed newest-first from the local DB; lecture_num is
  /// assigned by oldest-first position (see task_runners.py's
  /// `_fetch_course_and_lecture_num_sync`), so this has to un-reverse the
  /// same way CoursePage does before indexing by lecture_num - 1.
  Future<void> _loadPanelData({required int lectureNum, TopicMapNode? topicNode}) async {
    final lectures = (await ref.read(lectureListStreamProvider(widget.courseId).future)).reversed.toList();
    if (lectureNum < 1 || lectureNum > lectures.length) {
      if (mounted) {
        setState(() {
          _panelData = null;
          _panelExtent = 0;
        });
      }
      return;
    }
    final lecture = lectures[lectureNum - 1];
    final title = topicNode?.title ?? _lectureDisplayTitle(lecture);
    int? topicNum;
    String? summary;

    // Best-effort: a failed summary fetch (offline, RLS, transient error)
    // shouldn't silently swallow the whole panel -- _selectLecture/
    // _selectNode call this without awaiting it, so an uncaught exception
    // here would otherwise just vanish into an unhandled Future error and
    // the panel would never appear at all.
    try {
      if (topicNode == null) {
        // A plain one-shot query, not the realtime `lectureProvider` stream
        // -- this fires on every tap, and there's no reason to open/tear
        // down a realtime channel just to read one field once.
        final row = await supabase
            .from('lectures')
            .select('summary')
            .eq('id', lecture.id)
            .maybeSingle();
        final rawSummary = row?['summary'] as String?;
        summary = rawSummary == null ? null : stripSidCitations(rawSummary);
      } else {
        topicNum = _topicNumFromTopicId(topicNode.id);
        if (topicNum != null) {
          final lectureTopics = await ref.read(lectureTopicsProvider(lecture.id).future);
          final academicTopics = lectureTopics.where((t) => t.topicType == 'ACADEMIC').toList();
          if (topicNum >= 1 && topicNum <= academicTopics.length) {
            final matched = academicTopics[topicNum - 1];
            summary = matched.summary == null ? null : stripSidCitations(matched.summary!);
          }
        }
      }
    } catch (_) {
      summary = null;
    }

    final clusterName = topicNode == null ? null : _clusterNameFor(topicNode.clusterId);
    final relatedTopics = topicNode == null ? const <RelatedTopicEdge>[] : _relatedTopicsFor(topicNode.id);

    if (!mounted) return;
    setState(() {
      _panelData = _PanelData(
        lecture: lecture,
        lectureNum: lectureNum,
        topicNum: topicNum,
        title: title,
        clusterName: clusterName,
        relatedTopics: relatedTopics,
        summary: summary,
      );
      // Open at the small initial extent -- but only when actually
      // (re)opening from closed. Switching between lecture/topic while
      // the panel's already up (e.g. tapping a different node) keeps
      // whatever extent the user had dragged it to.
      if (_panelExtent <= 0) _panelExtent = _panelMinExtent;
    });
  }

  /// Applies a live drag delta to the panel's height, clamped to the
  /// min/max extents computed by the current build (see build()'s
  /// LayoutBuilder). Zero-duration while dragging so it tracks the finger
  /// 1:1 -- see _isDraggingPanel.
  void _onPanelDragUpdate(double deltaY) {
    setState(() {
      _isDraggingPanel = true;
      _panelExtent = (_panelExtent - deltaY).clamp(_panelMinExtent, _panelMaxExtent);
    });
  }

  /// Snaps to whichever of min/max extent the drag ended closer to (a
  /// fast enough fling overrides that towards the fling's direction).
  void _onPanelDragEnd(double? velocity) {
    const flingThreshold = 300.0;
    final double target;
    if (velocity != null && velocity < -flingThreshold) {
      target = _panelMaxExtent;
    } else if (velocity != null && velocity > flingThreshold) {
      target = _panelMinExtent;
    } else {
      final midpoint = (_panelMinExtent + _panelMaxExtent) / 2;
      target = _panelExtent >= midpoint ? _panelMaxExtent : _panelMinExtent;
    }
    setState(() {
      _isDraggingPanel = false;
      _panelExtent = target;
    });
  }

  void _handleBackgroundTapUp(TapUpDetails details) {
    final blobs = computeClusterBlobs(widget.data, _simulation);
    for (final entry in blobs.entries) {
      if (clusterBlobContains(entry.value, details.localPosition)) {
        setState(() {
          final next = ClusterSelection.cluster(entry.key);
          _selection = _selection == next ? null : next;
          _panelData = null;
          _panelExtent = 0;
        });
        return;
      }
    }
    setState(() {
      _selection = null;
      _panelData = null;
      _panelExtent = 0;
    });
  }

  /// Topic View: glow only the single tapped node, not the graph neighbors
  /// [highlight] also brightens. Lecture View: glow every node in
  /// [highlight] (the whole lecture). Cluster View never glows.
  bool _isGlowing(
    String nodeId,
    HighlightSet highlight,
    TopicMapViewMode viewMode,
  ) {
    switch (viewMode) {
      case TopicMapViewMode.topic:
        return _selection?.type == ClusterSelectionType.node &&
            _selection!.id == nodeId;
      case TopicMapViewMode.lecture:
        return highlight.nodeIds.contains(nodeId);
      case TopicMapViewMode.cluster:
        return false;
    }
  }

  String? _selectedEntityLabel(TopicMapData data) {
    final selection = _selection;
    if (selection == null) return null;
    switch (selection.type) {
      case ClusterSelectionType.node:
        for (final n in data.nodes) {
          if (n.id == selection.id) return n.title;
        }
        for (final g in data.ghostNodes) {
          if (g.id == selection.id) return g.name;
        }
        return null;
      case ClusterSelectionType.lecture:
        return 'Lecture ${selection.id}';
      case ClusterSelectionType.cluster:
        for (final c in data.clusters) {
          if (c.id == selection.id) return c.name;
        }
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Local layout size, not MediaQuery.sizeOf(context) -- this widget
        // can be embedded at any size (a small course-page preview card,
        // not just a fullscreen page), and the fit/zoom-limit math below
        // has to match whatever box it's actually laid out in. Unlike an
        // earlier version of this panel, the map's own size never changes
        // when the panel opens -- it's drawn as an overlay on top instead
        // (see below), so there's no relayout of this (expensive) map
        // subtree on every animation frame.
        final viewportSize = constraints.biggest;
        _lastViewportSize = viewportSize;

        if (!_hasScheduledFitToContent) {
          _hasScheduledFitToContent = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _fitToContent(viewportSize),
          );
        }

        // The panel opens small (mostly-map, easy to keep browsing the
        // graph) and can be dragged up almost to the top -- just enough of
        // the map (mapPeekHeight) always stays clear and touchable at the
        // panel's tallest so it never structurally reaches zero height
        // (it's an overlay, so its real layout size never changes anyway).
        const mapPeekHeight = 72.0;
        _panelMinExtent = min(320.0, constraints.maxHeight * 0.5);
        _panelMaxExtent = max(_panelMinExtent, constraints.maxHeight - mapPeekHeight);

        return Stack(
          children: [
            // Positioned.fill rather than a bare (non-positioned) child --
            // Stack only sizes itself to constraints.biggest when *every*
            // child is positioned; a single non-positioned child would
            // shrink the whole Stack down to that child's own preferred
            // size instead (the exact bug hit earlier with the back
            // button in topic_map_page.dart).
            Positioned.fill(child: _buildContent(context, viewportSize)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedContainer(
                // Zero duration while the finger is actively dragging it
                // (1:1 tracking, no lag); animated for the initial open and
                // for the post-drag snap to min/max.
                duration: _isDraggingPanel ? Duration.zero : const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                height: _panelData == null ? 0 : _panelExtent,
                // A fixed (not open-ended) height -- the panel's body
                // scrolls internally now (see LectureTopicDetailPanel),
                // which needs a bounded height to size its
                // Expanded/SingleChildScrollView against.
                child: _panelData == null
                    ? const SizedBox(width: double.infinity)
                    : LectureTopicDetailPanel(
                        courseTitle: widget.data.courseTitle,
                        lectureNum: _panelData!.lectureNum,
                        topicNum: _panelData!.topicNum,
                        title: _panelData!.title,
                        summary: _panelData!.summary,
                        clusterName: _panelData!.clusterName,
                        relatedTopics: _panelData!.relatedTopics,
                        onDragUpdate: _onPanelDragUpdate,
                        onDragEnd: _onPanelDragEnd,
                        // Only hides the panel -- keeps the Lecture/Topic
                        // View selection (and its highlight/glow) intact,
                        // unlike tapping the background/a cluster, which
                        // clears both. Tapping a different node/lecture
                        // still opens a fresh panel as usual.
                        onClose: () => setState(() {
                          _panelData = null;
                          _panelExtent = 0;
                        }),
                        onGoToLecture: () {
                          final lecture = _panelData!.lecture;
                          final courseId = widget.courseId;
                          setState(() {
                            _selection = null;
                            _panelData = null;
                            _panelExtent = 0;
                          });
                          context.push('${AppRoutes.notesRootPath}/c/$courseId/v/${lecture.id}');
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, Size viewportSize) {
    final data = widget.data;
    final brightness = Theme.of(context).brightness;

    final clusterColorByClusterId = <String, Color>{
      for (var i = 0; i < data.clusters.length; i++)
        data.clusters[i].id: TopicMapPalette.clusterColor(i, brightness),
    };

    final highlight = computeHighlight(
      data,
      _selection,
      _clusterIdByNodeId,
      _lectureNumByNodeId,
    );
    final blobs = computeClusterBlobs(data, _simulation);
    final viewMode = viewModeForSelection(_selection);
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final shrink = detailShrinkFactor(currentScale);

    return IgnorePointer(
      ignoring: !widget.interactive,
      child: Container(
        color: TopicMapPalette.surface(brightness),
        child: Stack(
          children: [
            InteractiveViewer(
              transformationController: _transformController,
              constrained: false,
              minScale: _effectiveMinScale(viewportSize),
              maxScale: _kMaxZoomScale,
              boundaryMargin: _computeBoundaryMargin(viewportSize),
              child: SizedBox(
                width: _renderCanvasSize.width,
                height: _renderCanvasSize.height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: _handleBackgroundTapUp,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CustomPaint(
                        size: _renderCanvasSize,
                        painter: ClusterMapPainter(
                          data: data,
                          simulation: _simulation,
                          brightness: brightness,
                          selection: _selection,
                          viewMode: viewMode,
                          highlight: highlight,
                          blobs: blobs,
                          clusterColorByClusterId: clusterColorByClusterId,
                          ghostNodeIds: _ghostNodeIds,
                          currentScale: currentScale,
                        ),
                      ),
                      for (final node in data.nodes)
                        _NodeMarker(
                          key: ValueKey(node.id),
                          position: _simulation.nodes[node.id]!.position,
                          label: node.title,
                          color:
                              clusterColorByClusterId[node.clusterId] ??
                              TopicMapPalette.mutedInk(brightness),
                          brightness: brightness,
                          viewMode: viewMode,
                          hasSelection: _selection != null,
                          isHighlighted: highlight.nodeIds.contains(node.id),
                          isGlowing: _isGlowing(node.id, highlight, viewMode),
                          shrink: shrink,
                          onTap: () => _selectNode(node.id),
                        ),
                      for (final ghost in data.ghostNodes)
                        _NodeMarker(
                          key: ValueKey(ghost.id),
                          position: _simulation.nodes[ghost.id]!.position,
                          label: ghost.name,
                          color:
                              clusterColorByClusterId[ghost.clusterId] ??
                              TopicMapPalette.mutedInk(brightness),
                          brightness: brightness,
                          viewMode: viewMode,
                          hasSelection: _selection != null,
                          isHighlighted: highlight.nodeIds.contains(ghost.id),
                          isGlowing: _isGlowing(ghost.id, highlight, viewMode),
                          isGhost: true,
                          ghostFaded: ghost.status == GhostStatus.faded,
                          shrink: shrink,
                          onTap: () => _selectNode(ghost.id),
                        ),
                      for (final cluster in data.clusters)
                        if (blobs[cluster.id] != null)
                          if (viewMode == TopicMapViewMode.cluster &&
                              currentScale <= _kClusterCenterLabelMaxScale)
                            _ClusterCenterLabel(
                              key: ValueKey('center-${cluster.id}'),
                              anchor: clusterBlobCenter(blobs[cluster.id]!),
                              name: cluster.name,
                              color: clusterColorByClusterId[cluster.id]!,
                              brightness: brightness,
                              growFactor: clusterLabelGrowFactor(currentScale),
                            )
                          else
                            _ClusterOutsideLabel(
                              key: ValueKey('outside-${cluster.id}'),
                              anchor: clusterBlobOutsideTopAnchor(
                                blobs[cluster.id]!,
                              ),
                              name: cluster.name,
                              color: clusterColorByClusterId[cluster.id]!,
                              brightness: brightness,
                              shrink: shrink,
                            ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.interactive)
              _TopOverlay(
                brightness: brightness,
                viewMode: viewMode,
                subtitle: _selectedEntityLabel(data),
                totalLectures: data.totalLecturesCovered,
                selectedLecture:
                    _selection?.type == ClusterSelectionType.lecture
                    ? int.parse(_selection!.id)
                    : null,
                onSelectLecture: _selectLecture,
              ),
          ],
        ),
      ),
    );
  }
}

/// Resolved content for the bottom detail panel -- see
/// _ClusterMapViewState._loadPanelData.
class _PanelData {
  const _PanelData({
    required this.lecture,
    required this.lectureNum,
    required this.topicNum,
    required this.title,
    required this.summary,
    required this.clusterName,
    required this.relatedTopics,
  });

  final Lecture lecture;
  final int lectureNum;
  final int? topicNum;
  final String title;
  final String? summary;

  /// Topic View only -- null for Lecture View.
  final String? clusterName;

  /// Topic View only -- empty for Lecture View.
  final List<RelatedTopicEdge> relatedTopics;
}

class _TopOverlay extends StatelessWidget {
  const _TopOverlay({
    required this.brightness,
    required this.viewMode,
    required this.subtitle,
    required this.totalLectures,
    required this.selectedLecture,
    required this.onSelectLecture,
  });

  final Brightness brightness;
  final TopicMapViewMode viewMode;
  final String? subtitle;
  final int totalLectures;
  final int? selectedLecture;
  final ValueChanged<int> onSelectLecture;

  String get _modeTitle {
    switch (viewMode) {
      case TopicMapViewMode.cluster:
        return 'Cluster View';
      case TopicMapViewMode.lecture:
        return 'Lecture View';
      case TopicMapViewMode.topic:
        return 'Topic View';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      // ClusterMapView is sometimes embedded edge-to-edge (no enclosing
      // AppBar/Scaffold reserving the status bar/notch inset for it), so
      // this overlay has to claim that inset itself -- otherwise its title
      // and lecture chips render partly underneath the system chrome.
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.only(top: 14, bottom: 10),
          decoration: BoxDecoration(
            color: TopicMapPalette.surface(brightness).withValues(alpha: 0.92),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _modeTitle,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: TopicMapPalette.primaryInk(brightness),
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: TopicMapPalette.secondaryInk(brightness),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              _LectureSelectorBar(
                totalLectures: totalLectures,
                selectedLecture: selectedLecture,
                brightness: brightness,
                onSelect: onSelectLecture,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LectureSelectorBar extends StatelessWidget {
  const _LectureSelectorBar({
    required this.totalLectures,
    required this.selectedLecture,
    required this.brightness,
    required this.onSelect,
  });

  final int totalLectures;
  final int? selectedLecture;
  final Brightness brightness;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var lectureNum = 1; lectureNum <= totalLectures; lectureNum++)
              Padding(
                key: ValueKey('lecture_chip_$lectureNum'),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _LectureChip(
                  label: 'Lecture $lectureNum',
                  selected: selectedLecture == lectureNum,
                  brightness: brightness,
                  onTap: () => onSelect(lectureNum),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LectureChip extends StatelessWidget {
  const _LectureChip({
    required this.label,
    required this.selected,
    required this.brightness,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Brightness brightness;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = TopicMapPalette.primaryInk(brightness);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? ink : TopicMapPalette.surface(brightness),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: ink.withValues(alpha: selected ? 1.0 : 0.25),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? TopicMapPalette.surface(brightness) : ink,
          ),
        ),
      ),
    );
  }
}

class _ClusterCenterLabel extends StatelessWidget {
  const _ClusterCenterLabel({
    super.key,
    required this.anchor,
    required this.name,
    required this.color,
    required this.brightness,
    required this.growFactor,
  });

  final Offset anchor;
  final String name;
  final Color color;
  final Brightness brightness;
  final double growFactor;

  static const double baseWidth = 190;
  static const double baseFontSize = 16;

  @override
  Widget build(BuildContext context) {
    final width = baseWidth * growFactor;
    return Positioned(
      left: anchor.dx - width / 2,
      top: anchor.dy - 20 * growFactor,
      width: width,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 14 * growFactor,
              vertical: 7 * growFactor,
            ),
            decoration: BoxDecoration(
              color: TopicMapPalette.surface(
                brightness,
              ).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: baseFontSize * growFactor,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClusterOutsideLabel extends StatelessWidget {
  const _ClusterOutsideLabel({
    super.key,
    required this.anchor,
    required this.name,
    required this.color,
    required this.brightness,
    required this.shrink,
  });

  final Offset anchor;
  final String name;
  final Color color;
  final Brightness brightness;
  final double shrink;

  static const double width = 150;
  static const double height = 22;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: anchor.dx - width / 2,
      top: anchor.dy - height * shrink - 8,
      width: width,
      height: height * shrink,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 8 * shrink,
              vertical: 2 * shrink,
            ),
            decoration: BoxDecoration(
              color: TopicMapPalette.surface(
                brightness,
              ).withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(10 * shrink),
              border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
            ),
            child: Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11 * shrink,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How much non-highlighted nodes/edges dim to when a selection is active,
/// per view mode -- kept much gentler than the old flat 0.10 (see
/// [kEdgeSuppressedOpacityTopic]/[kEdgeSuppressedOpacityCluster] for the
/// edge equivalents). Lecture View doesn't dim at all: it should read
/// exactly like Cluster View with nothing selected, using the lecture
/// selector chips (not fading) to convey the selection.
const double kNodeSuppressedOpacityTopic = 0.35;
const double kNodeSuppressedOpacityCluster = 0.10;

class _NodeMarker extends StatelessWidget {
  const _NodeMarker({
    super.key,
    required this.position,
    required this.label,
    required this.color,
    required this.brightness,
    required this.viewMode,
    required this.hasSelection,
    required this.isHighlighted,
    required this.isGlowing,
    required this.shrink,
    required this.onTap,
    this.isGhost = false,
    this.ghostFaded = false,
  });

  final Offset position;
  final String label;
  final Color color;
  final Brightness brightness;
  final TopicMapViewMode viewMode;
  final bool hasSelection;
  final bool isHighlighted;

  /// Topic View: only the single tapped node (not its graph neighbors,
  /// even though they share [isHighlighted]). Lecture View: every node
  /// belonging to the selected lecture (same set as [isHighlighted]
  /// there). Drawn as a white glow around the node -- see build().
  final bool isGlowing;
  final double shrink;
  final VoidCallback onTap;
  final bool isGhost;
  final bool ghostFaded;

  static const double labelWidth = 96;
  static const double labelFontSize = 10;

  @override
  Widget build(BuildContext context) {
    final baseOpacity = isGhost ? (ghostFaded ? 0.30 : 0.55) : 0.55;
    final highlightOpacity = isGhost ? 0.85 : 1.0;
    double opacity;
    if (!hasSelection) {
      opacity = baseOpacity;
    } else if (viewMode == TopicMapViewMode.lecture) {
      // Lecture View never dims non-highlighted nodes below the Cluster
      // View base look, but the lecture's own nodes still light up.
      opacity = isHighlighted ? highlightOpacity : baseOpacity;
    } else if (isHighlighted) {
      opacity = highlightOpacity;
    } else {
      opacity = viewMode == TopicMapViewMode.topic
          ? kNodeSuppressedOpacityTopic
          : kNodeSuppressedOpacityCluster;
    }
    final r = (isGhost ? kGhostNodeRadius : kNodeRadius) * shrink;

    return Positioned(
      left: position.dx - labelWidth / 2,
      top: position.dy - r,
      width: labelWidth,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: isGlowing
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.35),
                          blurRadius: 14 * shrink,
                          spreadRadius: 3 * shrink,
                        ),
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.15),
                          blurRadius: 26 * shrink,
                          spreadRadius: 1 * shrink,
                        ),
                      ],
                    )
                  : null,
              child: SizedBox(
                width: r * 2,
                height: r * 2,
                child: isGhost
                    ? CustomPaint(
                        painter: _DashedCirclePainter(
                          color: color,
                          opacity: opacity,
                          shrink: shrink,
                        ),
                      )
                    : Opacity(
                        opacity: opacity,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color,
                            border: Border.all(
                              color: TopicMapPalette.surface(brightness),
                              width: 2.5 * shrink,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.3),
                                blurRadius: 5 * shrink,
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Opacity(
              opacity: opacity,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: labelFontSize * shrink,
                  fontWeight: isGhost ? FontWeight.w400 : FontWeight.w600,
                  fontStyle: isGhost ? FontStyle.italic : FontStyle.normal,
                  color: TopicMapPalette.primaryInk(brightness),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter({
    required this.color,
    required this.opacity,
    required this.shrink,
  });

  final Color color;
  final double opacity;
  final double shrink;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1.5 * shrink;

    final fillPaint = Paint()..color = color.withValues(alpha: 0.18 * opacity);
    canvas.drawCircle(center, radius, fillPaint);

    final borderPaint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * shrink;

    final dashLength = 3.0 * shrink;
    final gapLength = 2.5 * shrink;
    final circumference = 2 * 3.141592653589793 * radius;
    final dashCount = (circumference / (dashLength + gapLength)).floor();
    final angleStep = (dashLength + gapLength) / radius;
    var angle = 0.0;
    for (var i = 0; i < dashCount; i++) {
      final sweep = dashLength / radius;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        sweep,
        false,
        borderPaint,
      );
      angle += angleStep;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.opacity != opacity ||
      oldDelegate.shrink != shrink;
}
