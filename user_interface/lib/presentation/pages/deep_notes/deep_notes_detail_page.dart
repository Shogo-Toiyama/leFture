// lib/presentation/pages/deep_notes/deep_notes_detail_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lecture_companion_ui/core/utils/sid_citation.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_scrollbar.dart';
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
    final currentIndex = useState<int>(topicIndex.clamp(0, topics.length - 1));
    // 直近の遷移方向: 1=次のノートへ, -1=前のノートへ, 0=遷移直後ではない。
    // 遷移先のノートを開いた瞬間のスクロール位置を決めるために使う。
    final navigationDirection = useState<int>(0);

    if (topics.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.paper.background,
        appBar: AppBar(
          backgroundColor: AppColors.paper.background,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: AppColors.paper.textInk),
            onPressed: () => context.pop(),
          ),
          title: Text(
            'Deep Notes',
            style: TextStyle(
              color: AppColors.paper.textInk,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: const Center(child: Text('No notes available')),
      );
    }

    final topic = topics[currentIndex.value];
    final totalTopics = topics.length;

    return Scaffold(
      backgroundColor: AppColors.paper.background,
      appBar: AppBar(
        backgroundColor: AppColors.paper.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.paper.textInk),
          onPressed: () => context.pop(),
        ),
        title: Text(
          topic.title,
          style: TextStyle(
            color: AppColors.paper.textInk,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${currentIndex.value + 1} / $totalTopics',
                style: TextStyle(
                  color: AppColors.paper.textPencil,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _NoteDetailContent(
        topic: topic,
        topicIndex: currentIndex.value,
        totalTopics: totalTopics,
        arrivalDirection: navigationDirection.value,
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
  });

  final DeepNoteTopic topic;
  final int topicIndex;
  final int totalTopics;
  final int arrivalDirection;
  final VoidCallback onNext;
  final VoidCallback onPrev;

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
                            color: AppColors.deepGold,
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
                        listBullet: const TextStyle(
                          color: AppColors.deepGold,
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
                            color: AppColors.deepGold,
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
