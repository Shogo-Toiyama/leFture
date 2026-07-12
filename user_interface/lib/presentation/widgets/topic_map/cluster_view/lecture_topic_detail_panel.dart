// Inline bottom panel shown when Lecture View or Topic View is entered (see
// ClusterMapView._loadPanelData) -- gives the tapped lecture/topic a face
// (title + summary) and a way out to the real LectureViewerPage.
//
// Deliberately a plain in-layout panel (not a showModalBottomSheet), so it
// pushes the map up from below instead of covering it with a modal barrier:
// the map stays fully visible and tappable in whatever space is left above
// this panel (see ClusterMapView.build()'s Stack/Positioned split).

import 'package:flutter/material.dart';

import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

/// One of a Topic's graph neighbors, for the "Related Topics" section --
/// only shown in Topic View. [isOutgoing] is true when the tapped topic is
/// the edge's source (it points *at* [title]), false when it's the target
/// (the edge points *from* [title] at the tapped topic).
class RelatedTopicEdge {
  const RelatedTopicEdge({
    required this.title,
    required this.relationType,
    required this.isOutgoing,
  });

  final String title;
  final String relationType;
  final bool isOutgoing;
}

class LectureTopicDetailPanel extends StatelessWidget {
  const LectureTopicDetailPanel({
    super.key,
    required this.courseTitle,
    required this.lectureNum,
    this.topicNum,
    required this.title,
    this.summary,
    this.clusterName,
    this.relatedTopics = const [],
    required this.onGoToLecture,
    required this.onClose,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final String courseTitle;
  final int lectureNum;

  /// Null for Lecture View; set for Topic View (the node's fixed position
  /// within its own lecture -- see TopicMapNode.topicIndexInLecture).
  final int? topicNum;

  /// Lecture View: the lecture's own display title. Topic View: the topic
  /// node's own title (the lecture it belongs to is still named in the
  /// breadcrumb and reachable via [onGoToLecture]).
  final String title;
  final String? summary;

  /// Topic View only -- null if the topic is unclustered ("isolated" per
  /// the topic-mapping pipeline's rules) or this is Lecture View.
  final String? clusterName;

  /// Topic View only -- every edge touching this topic, each resolved to
  /// the other node's title + humanized relation type. Empty in Lecture
  /// View or for a topic with no edges yet.
  final List<RelatedTopicEdge> relatedTopics;

  final VoidCallback onGoToLecture;
  final VoidCallback onClose;

  /// Drag the header/handle to resize the panel between its initial
  /// (min) and fully-expanded (max) height -- see ClusterMapView's
  /// _panelExtent/_onPanelDragUpdate/_onPanelDragEnd.
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double?> onDragEnd;

  bool get _isTopicView => topicNum != null;

  String get _breadcrumb {
    final parts = ['Lecture $lectureNum'];
    if (topicNum != null) parts.add('Topic $topicNum');
    return '$courseTitle, ${parts.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final hasSummary = summary?.trim().isNotEmpty == true;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C2E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AppColors.universe.glassBorder)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, -6)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drag handle + breadcrumb + close button stay put as a fixed
            // header while the body below scrolls. The header (not the
            // scrollable body, to avoid fighting its own vertical scroll
            // gesture) is also the drag target for resizing the panel
            // between its initial and fully-expanded height.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) => onDragUpdate(details.delta.dy),
              onVerticalDragEnd: (details) => onDragEnd(details.primaryVelocity),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.universe.glassBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 8, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _breadcrumb.toUpperCase(),
                            style: TextStyle(
                              color: AppColors.starGold,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.keyboard_arrow_down, color: AppColors.universe.textComet),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: onClose,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppColors.universe.textStarlight,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      hasSummary
                          ? summary!.trim()
                          : 'This is still being analyzed. The summary will appear here once it\'s ready.',
                      style: TextStyle(
                        color: hasSummary
                            ? AppColors.universe.textComet
                            : AppColors.universe.textComet.withValues(alpha: 0.6),
                        fontSize: 13.5,
                        height: 1.5,
                        fontStyle: hasSummary ? FontStyle.normal : FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: onGoToLecture,
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [AppColors.starGold, Color(0xFFFFD700)]),
                          borderRadius: BorderRadius.circular(23),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.starGold.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.play_circle_fill, color: AppColors.universe.voidBackground, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Go to this Lecture',
                              style: TextStyle(
                                color: AppColors.universe.voidBackground,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isTopicView) ..._buildTopicViewExtras(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTopicViewExtras() {
    return [
      const SizedBox(height: 22),
      _SectionLabel('CLUSTER'),
      const SizedBox(height: 8),
      Text(
        clusterName ?? 'Unclustered (isolated topic)',
        style: TextStyle(
          color: clusterName != null
              ? AppColors.universe.textStarlight
              : AppColors.universe.textComet.withValues(alpha: 0.6),
          fontSize: 14,
          fontWeight: FontWeight.w600,
          fontStyle: clusterName != null ? FontStyle.normal : FontStyle.italic,
        ),
      ),
      const SizedBox(height: 22),
      _SectionLabel('RELATED TOPICS'),
      const SizedBox(height: 8),
      if (relatedTopics.isEmpty)
        Text(
          'No connected topics yet.',
          style: TextStyle(
            color: AppColors.universe.textComet.withValues(alpha: 0.6),
            fontSize: 13,
            fontStyle: FontStyle.italic,
          ),
        )
      else
        ...relatedTopics.map(
          (edge) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  edge.isOutgoing ? Icons.arrow_forward : Icons.arrow_back,
                  color: AppColors.starGold,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        edge.title,
                        style: TextStyle(
                          color: AppColors.universe.textStarlight,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        edge.isOutgoing ? edge.relationType : '${edge.relationType} (of this)',
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.universe.textComet,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
      ),
    );
  }
}
