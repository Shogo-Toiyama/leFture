// lib/presentation/pages/review_cards/review_cards_viewer_page.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_providers.dart';
import 'package:lecture_companion_ui/application/lecture_viewer/lecture_viewer_data_provider.dart';
import 'package:lecture_companion_ui/core/utils/sid_citation.dart';
import 'package:lecture_companion_ui/core/utils/text_preview.dart';
import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_topic.dart';
import 'package:lecture_companion_ui/domain/entities/review_card.dart';
import 'package:lecture_companion_ui/presentation/pages/course/widgets/course_style_helper.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------
class _ReviewTopicGroup {
  _ReviewTopicGroup({
    required this.topicNumber,
    required this.title,
    required this.cards,
    this.imagePath,
  });

  final int topicNumber;
  final String title;
  final List<ReviewCard> cards;
  final String? imagePath;
}

class _ReviewCardItem {
  const _ReviewCardItem({required this.groupIndex, this.card});
  final int groupIndex;
  final ReviewCard? card;
  bool get isCover => card == null;
}

// ---------------------------------------------------------------------------
// Viewer Page
// ---------------------------------------------------------------------------
class ReviewCardsViewerPage extends HookConsumerWidget {
  const ReviewCardsViewerPage({
    super.key,
    required this.lectureId,
    this.initialIndex = 0,
  });

  final String lectureId;
  final int initialIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topicsAsync = ref.watch(lectureTopicsProvider(lectureId));
    final cardsAsync  = ref.watch(reviewCardsProvider(lectureId));

    final groups = useMemoized(() {
      final topics = topicsAsync.asData?.value ?? <LectureTopic>[];
      final cards  = cardsAsync.asData?.value  ?? <ReviewCard>[];
      final map = <int, List<ReviewCard>>{};
      for (final c in cards) {
        map.putIfAbsent(c.topicNumber, () => []).add(c);
      }
      return topics.map((t) => _ReviewTopicGroup(
        topicNumber: t.index,
        title: t.displayTitle,
        cards: sortReviewCards(map[t.index] ?? []),
        imagePath: t.imagePath,
      )).toList();
    }, [topicsAsync, cardsAsync]);

    if (cardsAsync.isLoading || topicsAsync.isLoading) {
      return Scaffold(
        backgroundColor: AppColors.paper.background,
        body: const Center(
            child: CircularProgressIndicator(color: AppColors.deepGold)),
      );
    }

    if (groups.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.paper.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.close, color: AppColors.paper.textInk),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Text(
            'No review cards yet',
            style: TextStyle(color: AppColors.paper.textPencil, fontSize: 16),
          ),
        ),
      );
    }

    return _ReviewCardsViewerBody(
      lectureId: lectureId,
      groups: groups,
      ref: ref,
      initialIndex: initialIndex,
    );
  }
}

// ---------------------------------------------------------------------------
// Viewer Body (stateful via hooks)
// ---------------------------------------------------------------------------
class _ReviewCardsViewerBody extends HookConsumerWidget {
  const _ReviewCardsViewerBody({
    required this.lectureId,
    required this.groups,
    required this.ref,
    this.initialIndex = 0,
  });

  final String lectureId;
  final List<_ReviewTopicGroup> groups;
  final WidgetRef ref;
  final int initialIndex;

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final lectureAsync = widgetRef.watch(lectureProvider(lectureId));
    final lecture = lectureAsync.asData?.value;

    final coursesAsync = widgetRef.watch(courseListProvider);
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

    final animationController =
        useAnimationController(duration: const Duration(milliseconds: 350));
    useAnimation(animationController);

    final currentCardIndex  = useState<int>(initialIndex);
    final previousCardIndex = useState<int>(initialIndex);
    final isAnimating       = useState<bool>(false);
    final isGoingForward    = useState<bool>(true);

    final screenWidth = MediaQuery.of(context).size.width;

    // Build flat list: cover + content cards per group
    final flatItems = useMemoized(() {
      final list = <_ReviewCardItem>[];
      for (var gi = 0; gi < groups.length; gi++) {
        list.add(_ReviewCardItem(groupIndex: gi));
        for (final card in groups[gi].cards) {
          list.add(_ReviewCardItem(groupIndex: gi, card: card));
        }
      }
      return list;
    }, [groups]);

    final groupStartIndex = useMemoized(() {
      final starts = <int>[];
      var idx = 0;
      for (final g in groups) {
        starts.add(idx);
        idx += g.cards.length + 1;
      }
      return starts;
    }, [groups]);

    final totalCards = flatItems.length;

    // Preload image files per group
    final imageFiles = <int, File?>{};
    for (var gi = 0; gi < groups.length; gi++) {
      final path = groups[gi].imagePath;
      imageFiles[gi] = path == null
          ? null
          : widgetRef.watch(artifactFileProvider(path)).asData?.value;
    }

    final navigateTo =
        useCallback((int newIndex, {bool immediate = false}) {
      if (isAnimating.value || newIndex == currentCardIndex.value) return;
      if (immediate) {
        currentCardIndex.value = newIndex;
        previousCardIndex.value = newIndex;
        return;
      }
      previousCardIndex.value = currentCardIndex.value;
      isGoingForward.value = newIndex > currentCardIndex.value;
      currentCardIndex.value = newIndex;
      isAnimating.value = true;
      animationController.forward(from: 0.0).then((_) {
        isAnimating.value = false;
        previousCardIndex.value = newIndex;
      });
    }, [currentCardIndex.value, isAnimating.value]);

    Widget buildCard(int cardIdx) {
      final item = flatItems[cardIdx.clamp(0, totalCards - 1)];
      final imageFile = imageFiles[item.groupIndex];
      if (item.isCover) {
        return _CoverCard(
          title: groups[item.groupIndex].title,
          imageFile: imageFile,
          borderRadius: 24,
        );
      }
      return _ContentCard(
          card: item.card!, imageFile: imageFile, themeColor: textThemeColor);
    }

    final index = currentCardIndex.value.clamp(0, totalCards - 1);
    final currentGroupIndex = flatItems[index].groupIndex;
    final topic = groups[currentGroupIndex];

    return Scaffold(
      backgroundColor: AppColors.paper.background,
      body: Container(
        decoration: BoxDecoration(
          color: AppColors.paper.background,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              textThemeColor.withValues(alpha: 0.22),
              textThemeColor.withValues(alpha: 0.06),
              Colors.transparent,
            ],
            stops: const [0.0, 0.4, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
            // ── Row 1: Close button & Title ──
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
                      topic.title,
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
            // ── Row 2: Grid view button & Page counter ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.grid_view, color: AppColors.paper.textInk),
                    onPressed: () => _showCardsListSheet(
                      context,
                      widgetRef,
                      groups,
                      groupStartIndex,
                      imageFiles,
                      flatItems,
                      navigateTo,
                      textThemeColor,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'View List',
                  ),
                  Text(
                    '${index + 1} / $totalCards',
                    style: TextStyle(
                      color: AppColors.paper.textPencil,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            // ── Progress bars (Stories-style) ────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: List.generate(groups.length, (topicIdx) {
                  final group = groups[topicIdx];
                  final groupStart = groupStartIndex[topicIdx];
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Row(
                        children: List.generate(
                          group.cards.length + 1,
                          (cardIdx) {
                            final absIdx = groupStart + cardIdx;
                            final isFilled = absIdx <= index;
                            final isActive = absIdx == index;
                            return Expanded(
                              child: Container(
                                height: 3,
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 1),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? textThemeColor
                                      : isFilled
                                          ? textThemeColor
                                              .withValues(alpha: 0.55)
                                          : Colors.white,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 12),

            // ── Card area ────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final cardWidth = screenWidth - 32;
                    if (details.localPosition.dx < cardWidth * 0.3) {
                      if (currentCardIndex.value > 0) {
                        navigateTo(currentCardIndex.value - 1);
                      }
                    } else {
                      if (currentCardIndex.value < totalCards - 1) {
                        navigateTo(currentCardIndex.value + 1);
                      }
                    }
                  },
                  onHorizontalDragEnd: (details) {
                    if (details.primaryVelocity == null) return;
                    if (details.primaryVelocity! < -300) {
                      if (currentGroupIndex < groups.length - 1) {
                        navigateTo(groupStartIndex[currentGroupIndex + 1]);
                      }
                    } else if (details.primaryVelocity! > 300) {
                      if (currentGroupIndex > 0) {
                        navigateTo(groupStartIndex[currentGroupIndex - 1]);
                      }
                    }
                  },
                  child: Builder(builder: (context) {
                    if (isAnimating.value) {
                      final progress = animationController.value;
                      if (isGoingForward.value) {
                        return Stack(children: [
                          Positioned.fill(
                            child: Transform.scale(
                              scale: 0.92 + (0.08 * progress),
                              child: Opacity(
                                opacity: 0.5 + (0.5 * progress),
                                child: buildCard(currentCardIndex.value),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: Transform.translate(
                              offset:
                                  Offset(-progress * screenWidth, 0),
                              child: Transform.rotate(
                                angle: -progress * 0.2,
                                alignment: Alignment.bottomCenter,
                                child: buildCard(
                                    previousCardIndex.value),
                              ),
                            ),
                          ),
                        ]);
                      } else {
                        return Stack(children: [
                          Positioned.fill(
                            child: Transform.scale(
                              scale: 1.0 - (0.08 * progress),
                              child: Opacity(
                                opacity: 1.0 - (0.5 * progress),
                                child:
                                    buildCard(previousCardIndex.value),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: Transform.translate(
                              offset: Offset(
                                  -(1.0 - progress) * screenWidth, 0),
                              child: Transform.rotate(
                                angle: -(1.0 - progress) * 0.2,
                                alignment: Alignment.bottomCenter,
                                child:
                                    buildCard(currentCardIndex.value),
                              ),
                            ),
                          ),
                        ]);
                      }
                    }
                    return buildCard(currentCardIndex.value);
                  }),
                ),
              ),
            ),

            // ── Bottom nav hint ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chevron_left,
                      color: AppColors.paper.textPencil, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    'Tap left / right  •  Swipe to change topic',
                    style: TextStyle(
                        color: AppColors.paper.textPencil, fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right,
                      color: AppColors.paper.textPencil, size: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  void _showCardsListSheet(
    BuildContext context,
    WidgetRef ref,
    List<_ReviewTopicGroup> groups,
    List<int> groupStartIndex,
    Map<int, File?> imageFiles,
    List<_ReviewCardItem> flatItems,
    void Function(int) navigateTo,
    Color themeColor,
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
                          'Review Cards List',
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
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                      itemCount: groups.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 28),
                      itemBuilder: (context, idx) {
                        final group = groups[idx];
                        final groupStart = groupStartIndex[idx];
                        final imageFile = imageFiles[idx];

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.title,
                              style: TextStyle(
                                color: AppColors.paper.textInk,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 155,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                itemCount: group.cards.length + 1,
                                separatorBuilder: (_, _) => const SizedBox(width: 12),
                                itemBuilder: (context, tileIdx) {
                                  if (tileIdx == 0) {
                                    return GestureDetector(
                                      onTap: () {
                                        Navigator.pop(context);
                                        navigateTo(groupStart);
                                      },
                                      child: SizedBox(
                                        width: 115,
                                        child: _CoverCardTile(title: group.title, imageFile: imageFile),
                                      ),
                                    );
                                  }
                                  final card = group.cards[tileIdx - 1];
                                  final preview = card.title?.trim().isNotEmpty == true
                                      ? card.title!.trim()
                                      : plainTextPreview(
                                          card.cardContent.isNotEmpty
                                              ? (card.cardContent.first.text ?? '')
                                              : '');
                                  return GestureDetector(
                                    onTap: () {
                                      Navigator.pop(context);
                                      navigateTo(groupStart + tileIdx);
                                    },
                                    child: Container(
                                      width: 115,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Color.lerp(AppColors.paper.surface, themeColor, 0.1)!,
                                            AppColors.paper.surface,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                            color: Colors.black.withValues(alpha: 0.07)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.03),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          if (card.heroEmoji?.trim().isNotEmpty == true) ...[
                                            Text(card.heroEmoji!.trim(),
                                                style: const TextStyle(fontSize: 26)),
                                            const SizedBox(height: 6),
                                          ],
                                          Text(
                                            preview,
                                            style: TextStyle(
                                              color: AppColors.paper.textInk,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 4,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
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
// Cover card
// ---------------------------------------------------------------------------
class _CoverCard extends StatelessWidget {
  const _CoverCard({
    required this.title,
    required this.imageFile,
    required this.borderRadius,
  });

  final String title;
  final File? imageFile;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final titleStyle = TextStyle(
      color: Colors.black,
      fontSize: 22,
      fontWeight: FontWeight.bold,
      height: 1.3,
      shadows: const [
        Shadow(color: Colors.white, blurRadius: 2),
        Shadow(color: Colors.white, blurRadius: 4),
        Shadow(color: Colors.white, blurRadius: 8),
      ],
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageFile != null)
            Image.file(imageFile!, fit: BoxFit.cover)
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFE0B2), Color(0xFFFFF8E1)],
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
              color: Colors.white.withValues(alpha: 0.72),
              child: Text(
                title,
                style: titleStyle,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Content card
// ---------------------------------------------------------------------------
class _ContentCard extends StatelessWidget {
  const _ContentCard({
    required this.card,
    required this.imageFile,
    required this.themeColor,
  });

  final ReviewCard card;
  final File? imageFile;
  final Color themeColor;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageFile != null;

    final content = SingleChildScrollView(
      padding: EdgeInsets.all(hasImage ? 20 : 28),
      child: Column(
        children: [
          Text(
            card.heroEmoji?.trim().isNotEmpty == true
                ? card.heroEmoji!.trim()
                : '💡',
            style: const TextStyle(fontSize: 56),
          ),
          const SizedBox(height: 24),
          if (card.title?.trim().isNotEmpty == true) ...[
            Text(
              card.title!.trim(),
              style: TextStyle(
                color: AppColors.paper.textInk,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ],
          ...card.cardContent.map((block) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ReviewCardBlockView(block: block, themeColor: themeColor),
              )),
        ],
      ),
    );

    if (!hasImage) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.paper.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.08),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 36,
              spreadRadius: 4,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: content,
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        image:
            DecorationImage(image: FileImage(imageFile!), fit: BoxFit.cover),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 36,
            spreadRadius: 4,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.paper.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(16),
        ),
        child: content,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card block renderer
// ---------------------------------------------------------------------------
class _ReviewCardBlockView extends StatelessWidget {
  const _ReviewCardBlockView({required this.block, required this.themeColor});

  final ReviewCardBlock block;
  final Color themeColor;

  MarkdownStyleSheet _styleSheet(BuildContext context,
      {bool italic = false}) {
    final baseColor = AppColors.paper.textInk;
    final style = TextStyle(
      color: baseColor,
      fontSize: 15,
      height: 1.4,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    );
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: style,
      strong: style.copyWith(
        fontWeight: FontWeight.bold,
        color: AppColors.paper.textInk,
      ),
      em: style.copyWith(fontStyle: FontStyle.italic),
      code: style.copyWith(
          fontFamily: 'monospace', backgroundColor: Colors.transparent),
      listBullet: style.copyWith(color: themeColor),
      textAlign: WrapAlignment.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (block.type) {
      case 'quote':
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: themeColor, width: 3)),
          ),
          child: MarkdownBody(
            data: stripSidCitations(block.text ?? ''),
            styleSheet: _styleSheet(context, italic: true)
                .copyWith(textAlign: WrapAlignment.start),
          ),
        );
      case 'list':
        final items = block.items ?? const <String>[];
        final markdown =
            items.map((item) => '- ${stripSidCitations(item)}').join('\n');
        return MarkdownBody(
          data: markdown,
          styleSheet:
              _styleSheet(context).copyWith(textAlign: WrapAlignment.start),
        );
      case 'paragraph':
      default:
        return MarkdownBody(
          data: stripSidCitations(block.text ?? ''),
          styleSheet: _styleSheet(context),
        );
    }
  }
}

class _CoverCardTile extends StatelessWidget {
  const _CoverCardTile({required this.title, required this.imageFile});

  final String title;
  final File? imageFile;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageFile != null)
            Image.file(imageFile!, fit: BoxFit.cover)
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFE0B2), Color(0xFFFFF8E1)],
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              color: Colors.white.withValues(alpha: 0.75),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(color: Colors.white, blurRadius: 2),
                    Shadow(color: Colors.white, blurRadius: 4),
                  ],
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
