import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_providers.dart';
import 'package:lecture_companion_ui/application/lecture_viewer/lecture_viewer_data_provider.dart';
import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_topic.dart';
import 'package:lecture_companion_ui/domain/entities/deep_note.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/repositories/deep_note_repository_drift.dart';
import 'package:lecture_companion_ui/core/utils/sid_citation.dart';
import 'package:lecture_companion_ui/presentation/pages/course/widgets/course_style_helper.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_scrollbar.dart';
import 'package:lecture_companion_ui/presentation/widgets/card_selection_toolbar.dart';
import 'deep_notes_list_page.dart';

// ---------------------------------------------------------------------------
// Detail Page
// ---------------------------------------------------------------------------
class DeepNotesDetailPage extends HookConsumerWidget {
  const DeepNotesDetailPage({
    super.key,
    required this.lectureId,
    required this.topicIndex,
    required this.topics,
  });

  final String lectureId;
  final int topicIndex;
  final List<DeepNoteTopic> topics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // If topics are passed from route state (e.g. from the list page), use them.
    // Otherwise, fetch them directly.
    final hasPassedTopics = topics.isNotEmpty;
    
    final topicsAsync = hasPassedTopics ? null : ref.watch(lectureTopicsProvider(lectureId));
    final notesAsync  = hasPassedTopics ? null : ref.watch(deepNotesProvider(lectureId));

    // Fetch lecture and parent course to get theme colors
    final lectureAsync = ref.watch(lectureProvider(lectureId));
    final lecture = lectureAsync.asData?.value;

    final coursesAsync = ref.watch(courseListProvider);
    final courses = coursesAsync.asData?.value;
    Course? course;
    if (courses != null && lecture != null) {
      for (final c in courses) {
        if (c.id == lecture.courseId) {
          course = c;
          break;
        }
      }
    }

    final themeColor = course != null
        ? CourseStyleHelper.hexToColor(course.color, fallback: AppColors.deepGold)
        : AppColors.deepGold;

    final HSLColor hsl = HSLColor.fromColor(themeColor);
    final textThemeColor = hsl.lightness > 0.65 ? hsl.withLightness(0.5).toColor() : themeColor;

    final resolvedTopics = useMemoized(() {
      if (hasPassedTopics) return topics;

      final rawTopics = topicsAsync?.asData?.value ?? <LectureTopic>[];
      final notes     = notesAsync?.asData?.value  ?? <DeepNote>[];
      final noteMap   = {for (final n in notes) n.topicNumber: n};

      return rawTopics.asMap().entries.map((entry) {
        final i = entry.key;
        final t = entry.value;
        final note = noteMap[t.index];
        return DeepNoteTopic(
          index: i,
          title: t.displayTitle,
          summary: t.summary ?? '',
          content: note?.noteContents ?? '',
          noteId: note?.id,
          reaction: note?.reaction,
          saved: note?.saved ?? false,
        );
      }).toList();
    }, [hasPassedTopics, topics, topicsAsync, notesAsync]);

    final index = resolvedTopics.isEmpty ? 0 : topicIndex.clamp(0, resolvedTopics.length - 1);
    final currentIndex = useState<int>(index);
    // 直近の遷移方向: 1=次のノートへ, -1=前のノートへ, 0=遷移直後ではない。
    // 遷移先のノートを開いた瞬間のスクロール位置を決めるために使う。
    final navigationDirection = useState<int>(0);
    // Tracks whether the user currently has text selected inside the note,
    // mirroring the same pattern used by the Review Cards viewer.
    final hasSelection = useState<bool>(false);

    // When resolvedTopics loads, update the currentIndex value to initial topicIndex
    useEffect(() {
      if (resolvedTopics.isNotEmpty) {
        currentIndex.value = topicIndex.clamp(0, resolvedTopics.length - 1);
      }
      return null;
    }, [resolvedTopics]);

    if (resolvedTopics.isEmpty) {
      final isLoading = (topicsAsync?.isLoading ?? false) || (notesAsync?.isLoading ?? false);
      return Scaffold(
        backgroundColor: AppColors.paper.background,
        body: Container(
          decoration: BoxDecoration(
            color: AppColors.paper.background,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                textThemeColor.withValues(alpha: 0.12),
                textThemeColor.withValues(alpha: 0.02),
                Colors.transparent,
              ],
              stops: const [0.0, 0.4, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _buildAppBar(context, ref, 'Deep Notes', currentIndex.value, 0, () => _showNotesListSheet(context, resolvedTopics, currentIndex, navigationDirection, textThemeColor), hasSelection.value, textThemeColor, null),
                Expanded(
                  child: Center(
                    child: isLoading
                        ? CircularProgressIndicator(color: textThemeColor)
                        : const Text('No notes available'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final topic = resolvedTopics[currentIndex.value];
    final totalTopics = resolvedTopics.length;

    return Scaffold(
      backgroundColor: AppColors.paper.background,
      body: Container(
        decoration: BoxDecoration(
          color: AppColors.paper.background,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              textThemeColor.withValues(alpha: 0.12),
              textThemeColor.withValues(alpha: 0.02),
              Colors.transparent,
            ],
            stops: const [0.0, 0.4, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context, ref, topic.title, currentIndex.value, totalTopics, () => _showNotesListSheet(context, resolvedTopics, currentIndex, navigationDirection, textThemeColor), hasSelection.value, textThemeColor, topic),
              Expanded(
                child: _NoteDetailContent(
                  topic: topic,
                  topicIndex: currentIndex.value,
                  totalTopics: totalTopics,
                  arrivalDirection: navigationDirection.value,
                  textThemeColor: textThemeColor,
                  onSelectionChanged: (selected) => hasSelection.value = selected,
                  onNext: () {
                    if (currentIndex.value < totalTopics - 1) {
                      navigationDirection.value = 1;
                      currentIndex.value = currentIndex.value + 1;
                    }
                  },
                  onPrev: () {
                    if (currentIndex.value > 0) {
                      navigationDirection.value = -1;
                      currentIndex.value = currentIndex.value - 1;
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    String title,
    int currentIndex,
    int totalCount,
    VoidCallback onGridTap,
    bool hasSelection,
    Color accentColor,
    DeepNoteTopic? topic,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row 1: Close button & Title
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.close, color: AppColors.paper.textInk),
                onPressed: () => context.pop(),
              ),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppColors.paper.textInk,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 48), // keeps title centered
            ],
          ),
        ),
        // Row 2: Grid view button, toolbar & Page counter
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.grid_view, color: AppColors.paper.textInk),
                onPressed: onGridTap,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'View List',
              ),
              Expanded(
                child: CardSelectionToolbar(
                  hasSelection: hasSelection,
                  accentColor: accentColor,
                  reaction: topic?.reaction,
                  saved: topic?.saved ?? false,
                  onLike: topic?.noteId == null
                      ? null
                      : () async {
                          await ref.read(deepNoteRepositoryDriftProvider).updateReaction(
                                id: topic!.noteId!,
                                reaction: topic.reaction == 'like' ? null : 'like',
                              );
                          ref.read(lectureControllerProvider.notifier).pushOutboxNow();
                        },
                  onDislike: topic?.noteId == null
                      ? null
                      : () async {
                          await ref.read(deepNoteRepositoryDriftProvider).updateReaction(
                                id: topic!.noteId!,
                                reaction: topic.reaction == 'dislike' ? null : 'dislike',
                              );
                          ref.read(lectureControllerProvider.notifier).pushOutboxNow();
                        },
                  onSave: topic?.noteId == null
                      ? null
                      : () async {
                          await ref.read(deepNoteRepositoryDriftProvider).updateSaved(
                                id: topic!.noteId!,
                                saved: !topic.saved,
                              );
                          ref.read(lectureControllerProvider.notifier).pushOutboxNow();
                        },
                ),
              ),
              const SizedBox(width: 8),
              if (totalCount > 0)
                Text(
                  '${currentIndex + 1} / $totalCount',
                  style: TextStyle(
                    color: AppColors.paper.textPencil,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _showNotesListSheet(
    BuildContext context,
    List<DeepNoteTopic> resolvedTopics,
    ValueNotifier<int> currentIndex,
    ValueNotifier<int> navigationDirection,
    Color textThemeColor,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: AppColors.paper.background,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.paper.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Deep Notes List',
                          style: TextStyle(
                            color: AppColors.paper.textInk,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: AppColors.paper.textInk),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                      itemCount: resolvedTopics.length,
                      separatorBuilder: (_, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final topic = resolvedTopics[index];
                        final isSelected = index == currentIndex.value;
                        return GestureDetector(
                          onTap: () {
                            navigationDirection.value = 0; // jump directly
                            currentIndex.value = index;
                            Navigator.pop(context);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? textThemeColor.withValues(alpha: 0.05)
                                  : AppColors.paper.background,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? textThemeColor.withValues(alpha: 0.3)
                                    : Colors.black.withValues(alpha: 0.07),
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                // Index badge
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: textThemeColor.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: textThemeColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        topic.title,
                                        style: TextStyle(
                                          color: AppColors.paper.textInk,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (topic.summary.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          topic.summary,
                                          style: TextStyle(
                                            color: AppColors.paper.textPencil,
                                            fontSize: 13,
                                            height: 1.4,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Note detail content (scrollable markdown + overscroll navigation)
// ---------------------------------------------------------------------------
class _NoteDetailContent extends HookWidget {
  const _NoteDetailContent({
    required this.topic,
    required this.topicIndex,
    required this.totalTopics,
    required this.arrivalDirection,
    required this.onNext,
    required this.onPrev,
    required this.textThemeColor,
    required this.onSelectionChanged,
  });

  final DeepNoteTopic topic;
  final int topicIndex;
  final int totalTopics;
  final int arrivalDirection;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final Color textThemeColor;
  final ValueChanged<bool> onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final scrollController = useScrollController();
    final isTransitioning = useState(false);

    final startedAtTop = useState(false);
    final startedAtBottom = useState(false);
    final shouldGoToNext = useState(false);
    final shouldGoToPrev = useState(false);

    // Reset transition lock when topic changes, and jump the scroll position
    // to match the direction of travel: arriving via "next" should land at the
    // top of the new note, arriving via "prev" should land at its bottom.
    useEffect(() {
      isTransitioning.value = false;
      if (arrivalDirection != 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!scrollController.hasClients) return;
          if (arrivalDirection > 0) {
            scrollController.jumpTo(scrollController.position.minScrollExtent);
          } else {
            scrollController.jumpTo(scrollController.position.maxScrollExtent);
          }
        });
      }
      return null;
    }, [topicIndex]);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (isTransitioning.value) return false;

        if (notification is ScrollStartNotification) {
          final m = notification.metrics;
          startedAtTop.value = m.pixels <= 0.0;
          startedAtBottom.value = m.pixels >= m.maxScrollExtent;
          shouldGoToNext.value = false;
          shouldGoToPrev.value = false;
        }

        if (notification is ScrollEndNotification ||
            (notification is ScrollUpdateNotification &&
                notification.dragDetails == null)) {
          if (shouldGoToNext.value) {
            shouldGoToNext.value = false;
            shouldGoToPrev.value = false;
            isTransitioning.value = true;
            onNext();
          } else if (shouldGoToPrev.value) {
            shouldGoToNext.value = false;
            shouldGoToPrev.value = false;
            isTransitioning.value = true;
            onPrev();
          }
        }

        if (notification is ScrollUpdateNotification) {
          final m = notification.metrics;
          final isDragging = notification.dragDetails != null;
          if (isDragging) {
            if (startedAtBottom.value &&
                m.pixels >= m.maxScrollExtent + 50 &&
                topicIndex < totalTopics - 1) {
              shouldGoToNext.value = true;
            }
            if (startedAtTop.value &&
                m.pixels <= m.minScrollExtent - 50 &&
                topicIndex > 0) {
              shouldGoToPrev.value = true;
            }
            if (shouldGoToNext.value && m.pixels < m.maxScrollExtent + 10) {
              shouldGoToNext.value = false;
            }
            if (shouldGoToPrev.value && m.pixels > m.minScrollExtent - 10) {
              shouldGoToPrev.value = false;
            }
          }
        }

        if (notification is ScrollEndNotification) {
          startedAtTop.value = false;
          startedAtBottom.value = false;
        }
        return false;
      },
      child: SelectionArea(
        contextMenuBuilder: (context, selectableRegionState) =>
            const SizedBox.shrink(),
        onSelectionChanged: (content) =>
            onSelectionChanged(content != null && content.plainText.isNotEmpty),
        child: CustomScrollbar(
          controller: scrollController,
          // 1トピック分のノートは有限かつ短いドキュメントなので、フィード向けの
          // 遅延読み込み(Sliver)を伴うListViewではなく、最初から全体を一括で
          // レイアウトするSingleChildScrollViewを使う。これによりmaxScrollExtent
          // が常に正確な値になり、スクロールバーのサイズ/位置が揺れなくなる。
          child: SingleChildScrollView(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Prev arrow ─────────────────────────────────────────────
                if (topicIndex > 0)
                  Center(
                    child: Column(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.keyboard_arrow_up,
                            color: textThemeColor,
                            size: 28,
                          ),
                          onPressed: onPrev,
                        ),
                        Text(
                          'Pull or tap to previous note',
                          style: TextStyle(
                            color: AppColors.paper.textPencil,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),

                // ── Title ──────────────────────────────────────────────────
                Text(
                  topic.title,
                  style: TextStyle(
                    color: AppColors.paper.textInk,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: textThemeColor.withValues(alpha: 0.35),
                        blurRadius: 10,
                      ),
                      Shadow(
                        color: textThemeColor.withValues(alpha: 0.15),
                        blurRadius: 22,
                      ),
                    ],
                  ),
                ),

                // ── Summary ────────────────────────────────────────────────
                if (topic.summary.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    topic.summary,
                    style: TextStyle(
                      color: AppColors.paper.textPencil,
                      fontSize: 15,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // ── Markdown content ───────────────────────────────────────
                MarkdownBody(
                  data: topic.content.isNotEmpty
                      ? stripSidCitations(topic.content)
                      : 'Deep notes for this topic are still being generated…',
                  selectable: false,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                      .copyWith(
                        p: TextStyle(
                          color: AppColors.paper.textInk,
                          fontSize: 16,
                          height: 1.6,
                        ),
                        h1: TextStyle(
                          color: AppColors.paper.textInk,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        h2: TextStyle(
                          color: AppColors.paper.textInk,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        h3: TextStyle(
                          color: AppColors.paper.textInk,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        listBullet: TextStyle(
                          color: textThemeColor,
                          fontSize: 16,
                        ),
                        code: TextStyle(
                          color: const Color(0xFF0F766E),
                          fontFamily: 'monospace',
                          fontSize: 14,
                          backgroundColor: Colors.transparent,
                        ),
                        codeblockPadding: const EdgeInsets.all(16),
                        codeblockDecoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                ),
                const SizedBox(height: 32),

                // ── Next arrow ─────────────────────────────────────────────
                if (topicIndex < totalTopics - 1)
                  Center(
                    child: Column(
                      children: [
                        Text(
                          'Pull or tap to next note',
                          style: TextStyle(
                            color: AppColors.paper.textPencil,
                            fontSize: 11,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.keyboard_arrow_down,
                            color: textThemeColor,
                            size: 28,
                          ),
                          onPressed: onNext,
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
