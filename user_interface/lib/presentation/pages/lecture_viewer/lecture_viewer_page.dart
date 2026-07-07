import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:lecture_companion_ui/application/auth/auth_provider.dart';
import 'package:lecture_companion_ui/core/utils/sid_citation.dart';
import 'package:lecture_companion_ui/core/utils/text_preview.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_providers.dart';
import 'package:lecture_companion_ui/application/lecture_viewer/lecture_viewer_data_provider.dart';
import 'package:lecture_companion_ui/domain/entities/announcement.dart';
import 'package:lecture_companion_ui/domain/entities/deep_note.dart';
import 'package:lecture_companion_ui/domain/entities/fun_fact.dart';
import 'package:lecture_companion_ui/domain/entities/keyword.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_data.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_topic.dart';
import 'package:lecture_companion_ui/domain/entities/review_card.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/announcement_type_icon.dart';
import 'package:lecture_companion_ui/presentation/widgets/recording_timer_chip.dart';
import 'package:lecture_companion_ui/app/routes.dart';

class LectureViewerPage extends HookConsumerWidget {
  const LectureViewerPage({
    super.key,
    required this.lectureId,
  });

  final String lectureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDummy = lectureId.startsWith('dummy_');
    
    // Panel States
    final isExpanded = useState(false);
    final currentTab = useState(0); // 0: Cards, 1: Notes, 2: Keywords, 3: Transcript
    final currentCardIndex = useState<int>(0);
    final selectedNoteIndex = useState<int?>(null);
    final selectedText = useState<String?>(null);

    if (isDummy) {
      final dummyLecture = Lecture(
        id: lectureId,
        userId: 'dummy_user',
        courseId: 'dummy_course',
        title: 'Introduction to OOP & Classes',
        isDeleted: false,
        sortOrder: 0,
        lectureDatetime: DateTime.now().subtract(const Duration(days: 2)),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      return _buildViewerBody(
        context: context,
        ref: ref,
        lecture: dummyLecture,
        isExpanded: isExpanded,
        currentTab: currentTab,
        currentCardIndex: currentCardIndex,
        selectedNoteIndex: selectedNoteIndex,
        selectedText: selectedText,
      );
    }

    final lectureAsync = ref.watch(lectureProvider(lectureId));

    return lectureAsync.when(
      loading: () => Scaffold(backgroundColor: AppColors.universe.voidBackground, body: const Center(child: CircularProgressIndicator(color: AppColors.starGold))),
      error: (err, stack) => Scaffold(backgroundColor: AppColors.universe.voidBackground, body: Center(child: Text('Error: $err', style: const TextStyle(color: AppColors.correctionRed)))),
      data: (lecture) {
        if (lecture == null) {
          return Scaffold(backgroundColor: AppColors.universe.voidBackground, body: const Center(child: Text('Lecture not found', style: TextStyle(color: Colors.white))));
        }

        return _buildViewerBody(
          context: context,
          ref: ref,
          lecture: lecture,
          isExpanded: isExpanded,
          currentTab: currentTab,
          currentCardIndex: currentCardIndex,
          selectedNoteIndex: selectedNoteIndex,
          selectedText: selectedText,
        );
      },
    );
  }

  Widget _buildViewerBody({
    required BuildContext context,
    required WidgetRef ref,
    required Lecture lecture,
    required ValueNotifier<bool> isExpanded,
    required ValueNotifier<int> currentTab,
    required ValueNotifier<int> currentCardIndex,
    required ValueNotifier<int?> selectedNoteIndex,
    required ValueNotifier<String?> selectedText,
  }) {
    // --- 実データの取得 ---
    final topics = ref.watch(lectureTopicsProvider(lecture.id)).asData?.value ?? const <LectureTopic>[];
    final deepNotes = ref.watch(deepNotesProvider(lecture.id)).asData?.value ?? const <DeepNote>[];
    final reviewCards = ref.watch(reviewCardsProvider(lecture.id)).asData?.value ?? const <ReviewCard>[];
    final keywords = ref.watch(lectureKeywordsProvider(lecture.id)).asData?.value ?? const <Keyword>[];
    final funFacts = ref.watch(funFactsForLectureProvider(lecture.id)).asData?.value ?? const <FunFact>[];
    final announcements = ref.watch(announcementsForLectureProvider(lecture.id)).asData?.value ?? const <Announcement>[];

    final uid = ref.watch(currentUserProvider)?.id;
    final transcriptAsync = uid == null
        ? const AsyncValue<List<TranscriptSentence>?>.data(null)
        : ref.watch(transcriptProvider(uid: uid, lectureId: lecture.id));

    // topic を index で引けるようにしておく
    final topicByIndex = <int, LectureTopic>{
      for (final t in topics) t.index: t,
    };

    // Deep Notes: lecture_topics の並び順に、対応するnote_contentsを合わせて1つのリストにする。
    // LLM生成物に含まれるSID引用(⟦s000011⟧など)は表示時には除去する。
    final noteTopics = topics
        .map((t) => _NoteTopic(
              title: t.displayTitle,
              summary: stripSidCitations(t.summary ?? ''),
              content: stripSidCitations(deepNotes
                      .firstWhere(
                        (n) => n.topicNumber == t.index,
                        orElse: () => DeepNote(id: '', topicNumber: t.index, createdAt: DateTime.now()),
                      )
                      .noteContents ??
                  ''),
            ))
        .toList();

    // Review Cards: topic_number 昇順、かつ cardType（hook -> core_why -> gotcha -> next_action）の順にソートしてグルーピング
    const cardTypeOrder = {
      'hook': 0,
      'core_why': 1,
      'gotcha': 2,
      'next_action': 3,
    };

    final sortedReviewCards = List<ReviewCard>.from(reviewCards)
      ..sort((a, b) {
        if (a.topicNumber != b.topicNumber) {
          return a.topicNumber.compareTo(b.topicNumber);
        }
        final orderA = cardTypeOrder[a.cardType?.toLowerCase()] ?? 99;
        final orderB = cardTypeOrder[b.cardType?.toLowerCase()] ?? 99;
        return orderA.compareTo(orderB);
      });

    final reviewGroups = <_ReviewTopicGroup>[];
    for (final card in sortedReviewCards) {
      if (reviewGroups.isEmpty || reviewGroups.last.topicNumber != card.topicNumber) {
        final topic = topicByIndex[card.topicNumber];
        reviewGroups.add(_ReviewTopicGroup(
          topicNumber: card.topicNumber,
          title: topic?.displayTitle ?? 'Topic ${card.topicNumber}',
          imagePath: topic?.imagePath,
          cards: [card],
        ));
      } else {
        reviewGroups.last.cards.add(card);
      }
    }


    final paperTheme = ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.paper.background,
      colorScheme: ColorScheme.light(
        surface: AppColors.paper.surface,
        onSurface: AppColors.paper.textInk,
        onSurfaceVariant: AppColors.paper.textPencil,
        primary: AppColors.deepGold,
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: AppColors.paper.textInk),
        bodyMedium: TextStyle(color: AppColors.paper.textInk),
        titleLarge: TextStyle(color: AppColors.paper.textInk, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: AppColors.paper.textInk, fontWeight: FontWeight.bold),
        labelSmall: TextStyle(color: AppColors.paper.textPencil),
      ),
    );

    useEffect(() {
      if (isExpanded.value) {
        if (currentTab.value == 1 && selectedNoteIndex.value == null) {
          selectedNoteIndex.value = 0;
        }
      } else {
        selectedNoteIndex.value = null;
      }
      return null;
    }, [isExpanded.value, currentTab.value]);

    useEffect(() {
      selectedText.value = null;
      return null;
    }, [currentTab.value, isExpanded.value, selectedNoteIndex.value]);

    final headerHeight = useState<double>(280.0);
    final screenHeight = MediaQuery.of(context).size.height;
    
    final collapsedTopOffset = headerHeight.value+20;
    final topOffset = isExpanded.value ? 0.0 : collapsedTopOffset;
    final panelHeight = isExpanded.value ? screenHeight : screenHeight - collapsedTopOffset;

    final dateStr = DateFormat.yMMMd().format(lecture.lectureDatetime);
    final timeStr = DateFormat.Hm().format(lecture.lectureDatetime);

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: Stack(
        children: [
          // 1. Background Content (Header)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _MeasureSize(
              onChange: (size) {
                if (headerHeight.value != size.height) {
                  headerHeight.value = size.height;
                }
              },
              child: _buildBackgroundContent(
                context,
                lecture,
                dateStr,
                timeStr,
                funFacts: funFacts,
                announcements: announcements,
              ),
            ),
          ),

          // 2. Slidable Foreground Panel
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            top: topOffset,
            left: 0,
            right: 0,
            height: panelHeight,
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                if (details.delta.dy < -5 && !isExpanded.value) {
                  isExpanded.value = true;
                } else if (details.delta.dy > 5 && isExpanded.value) {
                  isExpanded.value = false;
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: isExpanded.value
                      ? AppColors.paper.background
                      : AppColors.paper.background.withValues(alpha: 0.5),
                  border: isExpanded.value ? null : Border(top: BorderSide(color: AppColors.universe.glassBorder)),
                  borderRadius: isExpanded.value 
                      ? BorderRadius.zero 
                      : const BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: Theme(
                  data: paperTheme,
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Tab Header Area
                          _buildPanelHeader(
                            context: context,
                            isExpanded: isExpanded.value, 
                            currentTab: currentTab,
                            onToggleExpand: () {
                              isExpanded.value = !isExpanded.value;
                            },
                          ),
                          // Panel Content Area
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: _buildPanelContent(
                                currentTab: currentTab.value,
                                isExpanded: isExpanded.value,
                                currentCardIndex: currentCardIndex,
                                selectedNoteIndex: selectedNoteIndex,
                                onExpand: () => isExpanded.value = true,
                                selectedText: selectedText,
                                reviewGroups: reviewGroups,
                                noteTopics: noteTopics,
                                keywords: keywords,
                                transcriptAsync: transcriptAsync,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (isExpanded.value && selectedText.value != null && selectedText.value!.isNotEmpty)
                        Positioned(
                          top: MediaQuery.of(context).padding.top + 104.0,
                          left: 16,
                          right: 16,
                          child: Builder(
                            builder: (context) {
                              final isDark = Theme.of(context).brightness == Brightness.dark;
                              return Container(
                                height: 46,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.universe.voidBackground.withValues(alpha: 0.92)
                                      : AppColors.paper.surface.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark
                                        ? AppColors.universe.glassBorder
                                        : Colors.black.withValues(alpha: 0.08),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isDark
                                          ? Colors.black.withValues(alpha: 0.4)
                                          : Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.gesture, 
                                          color: isDark 
                                              ? AppColors.universe.textComet 
                                              : AppColors.paper.textPencil, 
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'テキストアクション',
                                          style: TextStyle(
                                            color: isDark 
                                                ? Colors.white70 
                                                : AppColors.paper.textPencil,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 24),
                                        _ToolbarButton(
                                          icon: Icons.auto_awesome,
                                          label: 'AIに質問',
                                          color: AppColors.starGold,
                                          onTap: () {
                                            final text = selectedText.value;
                                            if (text != null && text.isNotEmpty) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  backgroundColor: AppColors.universe.voidBackground,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(6),
                                                    side: BorderSide(color: AppColors.universe.glassBorder),
                                                  ),
                                                  behavior: SnackBarBehavior.floating,
                                                  content: Text('AIに質問中: "$text"', style: const TextStyle(color: Colors.white)),
                                                ),
                                              );
                                              selectedText.value = null; // Close menu
                                            }
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        _ToolbarButton(
                                          icon: Icons.edit,
                                          label: 'マーカー',
                                          color: isDark ? Colors.white : AppColors.paper.textInk,
                                          onTap: () {
                                            final text = selectedText.value;
                                            if (text != null && text.isNotEmpty) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  backgroundColor: AppColors.universe.voidBackground,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(12),
                                                    side: BorderSide(color: AppColors.universe.glassBorder),
                                                  ),
                                                  behavior: SnackBarBehavior.floating,
                                                  content: Text('マーカーを追加: "$text"', style: const TextStyle(color: Colors.white)),
                                                ),
                                              );
                                              selectedText.value = null; // Close menu
                                            }
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        _ToolbarButton(
                                          icon: Icons.copy,
                                          label: 'コピー',
                                          color: isDark ? Colors.white : AppColors.paper.textInk,
                                          onTap: () {
                                            final text = selectedText.value;
                                            if (text != null && text.isNotEmpty) {
                                              Clipboard.setData(ClipboardData(text: text));
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  backgroundColor: AppColors.universe.voidBackground,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(12),
                                                    side: BorderSide(color: AppColors.universe.glassBorder),
                                                  ),
                                                  behavior: SnackBarBehavior.floating,
                                                  content: const Text('クリップボードにコピーしました', style: TextStyle(color: Colors.white)),
                                                ),
                                              );
                                              selectedText.value = null; // Close menu
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundContent(
    BuildContext context,
    Lecture lecture,
    String dateStr,
    String timeStr, {
    required List<FunFact> funFacts,
    required List<Announcement> announcements,
  }) {
    final displayTitle = lecture.title?.trim().isNotEmpty == true
        ? lecture.title!
        : (lecture.titleGenerated?.trim().isNotEmpty == true ? lecture.titleGenerated! : 'Untitled Lecture');
    final summary = lecture.summary == null ? null : stripSidCitations(lecture.summary!).trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Custom Home-style AppBar with Back button
        const _LectureAppBar(),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date & Time
              Text(
                '$dateStr • $timeStr',
                style: TextStyle(
                  color: AppColors.universe.textComet,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),

              // Title
              Text(
                displayTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // Summary
              Text(
                (summary != null && summary.isNotEmpty)
                    ? summary
                    : 'This lecture is still being analyzed. The summary will appear here once it\'s ready.',
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 13,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),

              if (announcements.isNotEmpty || funFacts.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (announcements.isNotEmpty) ...[
                      _HighlightChip(
                        icon: Icons.campaign_outlined,
                        label: '${announcements.length} announcement${announcements.length == 1 ? '' : 's'}',
                        onTap: () => _showAnnouncementsSheet(context, announcements),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (funFacts.isNotEmpty)
                      _HighlightChip(
                        icon: Icons.auto_awesome,
                        label: '${funFacts.length} fun fact${funFacts.length == 1 ? '' : 's'}',
                        onTap: () => _showFunFactsSheet(context, funFacts),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _showAnnouncementsSheet(BuildContext context, List<Announcement> announcements) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LectureInfoSheet.announcements(announcements),
    );
  }

  void _showFunFactsSheet(BuildContext context, List<FunFact> funFacts) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LectureInfoSheet.funFacts(funFacts),
    );
  }

  Widget _buildPanelHeader({
    required BuildContext context,
    required bool isExpanded, 
    required ValueNotifier<int> currentTab,
    required VoidCallback onToggleExpand,
  }) {
    final safeTop = MediaQuery.of(context).padding.top;
    return Container(
      decoration: isExpanded
          ? BoxDecoration(
              color: Color.lerp(AppColors.paper.background, AppColors.paper.textInk, 0.035),
              border: Border(
                bottom: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
              ),
            )
          : null,
      padding: EdgeInsets.only(
        top: isExpanded ? safeTop + 16.0 : 16.0, 
        bottom: isExpanded ? 12.0 : 8.0,
      ),
      child: Column(
        children: [
          // Up indicator (only when collapsed)
          if (!isExpanded)
            GestureDetector(
              onTap: onToggleExpand,
              child: Icon(Icons.keyboard_arrow_up, color: AppColors.universe.textComet, size: 28),
            ),
          
          if (!isExpanded) const SizedBox(height: 8),

          // Tabs（横幅が狭い端末でも折り返さないよう横スクロール可能にしておく）
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TabItem(title: 'Review Cards', index: 0, currentTab: currentTab, isExpanded: isExpanded),
                const SizedBox(width: 8),
                _TabItem(title: 'Deep Notes', index: 1, currentTab: currentTab, isExpanded: isExpanded),
                const SizedBox(width: 8),
                _TabItem(title: 'Keywords', index: 2, currentTab: currentTab, isExpanded: isExpanded),
                const SizedBox(width: 8),
                _TabItem(title: 'Transcript', index: 3, currentTab: currentTab, isExpanded: isExpanded),
              ],
            ),
          ),

          // Down indicator (only when expanded)
          if (isExpanded)
            GestureDetector(
              onTap: onToggleExpand,
              child: Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Icon(Icons.keyboard_arrow_down, color: AppColors.paper.textPencil, size: 28),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPanelContent({
    required int currentTab,
    required bool isExpanded,
    required ValueNotifier<int> currentCardIndex,
    required ValueNotifier<int?> selectedNoteIndex,
    required VoidCallback onExpand,
    required ValueNotifier<String?> selectedText,
    required List<_ReviewTopicGroup> reviewGroups,
    required List<_NoteTopic> noteTopics,
    required List<Keyword> keywords,
    required AsyncValue<List<TranscriptSentence>?> transcriptAsync,
  }) {
    if (currentTab == 0) {
      return _ReviewCardsView(
        key: const ValueKey('tab_0'),
        isExpanded: isExpanded,
        currentCardIndex: currentCardIndex,
        onExpand: onExpand,
        groups: reviewGroups,
      );
    } else if (currentTab == 1) {
      return _DeepNotesView(
        key: const ValueKey('tab_1'),
        isExpanded: isExpanded,
        selectedNoteIndex: selectedNoteIndex,
        onExpand: onExpand,
        selectedText: selectedText,
        topics: noteTopics,
      );
    } else if (currentTab == 2) {
      return _KeywordsView(
        key: const ValueKey('tab_2'),
        keywords: keywords,
      );
    } else {
      return _TranscriptView(
        key: const ValueKey('tab_3'),
        transcriptAsync: transcriptAsync,
      );
    }
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.title,
    required this.index,
    required this.currentTab,
    required this.isExpanded,
  });

  final String title;
  final int index;
  final ValueNotifier<int> currentTab;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final isActive = currentTab.value == index;
    
    if (isExpanded) {
      // Expanded: Subtle, flat design
      return GestureDetector(
        onTap: () => currentTab.value = index,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: isActive ? Border(bottom: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)) : null,
          ),
          child: Text(
            title,
            style: TextStyle(
              color: isActive ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
      );
    } else {
      // Collapsed: Prominent, button-like design (styled for dark/transparent background)
      return GestureDetector(
        onTap: () => currentTab.value = index,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.starGold.withValues(alpha: 0.15) : AppColors.universe.glassWhiteLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? AppColors.starGold : AppColors.universe.glassBorder,
            ),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: isActive ? AppColors.starGold : AppColors.universe.textStarlight,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Deep Notes / Review Cards 用の軽量データクラス
// ---------------------------------------------------------------------------

/// Deep Notesタブの1トピック分（lecture_topics + deep_notes を結合したもの）
class _NoteTopic {
  const _NoteTopic({required this.title, required this.summary, required this.content});

  final String title;
  final String summary;
  final String content;
}

/// Review Cardsタブの1トピック分（review_cardsをtopic_numberでグルーピングしたもの）
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

  /// lecture_topics.image_path (R2ストレージパス)。生成前はnull。
  final String? imagePath;
}

// ---------------------------------------------------------------------------
// ヘッダーの「Xお知らせ」「Y Fun Facts」チップ
// ---------------------------------------------------------------------------
class _HighlightChip extends StatelessWidget {
  const _HighlightChip({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.universe.glassWhiteLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.universe.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.starGold, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: AppColors.universe.textStarlight,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 「Xお知らせ」「Y Fun Facts」チップをタップした時に開くボトムシート
// ---------------------------------------------------------------------------
class _LectureInfoSheet extends StatelessWidget {
  const _LectureInfoSheet._({required this.title, required this.itemsBuilder});

  factory _LectureInfoSheet.announcements(List<Announcement> announcements) {
    return _LectureInfoSheet._(
      title: 'Announcements',
      itemsBuilder: (context) =>
          announcements.map((a) => _AnnouncementRow(announcement: a)).toList(),
    );
  }

  factory _LectureInfoSheet.funFacts(List<FunFact> funFacts) {
    return _LectureInfoSheet._(
      title: 'Fun Facts',
      itemsBuilder: (context) => funFacts.map((f) => _FunFactRow(funFact: f)).toList(),
    );
  }

  final String title;
  final List<Widget> Function(BuildContext context) itemsBuilder;

  @override
  Widget build(BuildContext context) {
    final items = itemsBuilder(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1C2E),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: AppColors.universe.glassBorder)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.universe.glassBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppColors.universe.textStarlight,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text('Nothing here yet',
                            style: TextStyle(color: AppColors.universe.textComet)),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        itemCount: items.length,
                        separatorBuilder: (context, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) => items[index],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AnnouncementRow extends StatelessWidget {
  const _AnnouncementRow({required this.announcement});

  final Announcement announcement;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconForAnnouncementType(announcement.type), color: AppColors.starGold, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  announcement.title?.trim().isNotEmpty == true
                      ? announcement.title!.trim()
                      : 'Announcement',
                  style: TextStyle(
                    color: AppColors.universe.textStarlight,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (announcement.description?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    announcement.description!.trim(),
                    style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FunFactRow extends StatelessWidget {
  const _FunFactRow({required this.funFact});

  final FunFact funFact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            funFact.title?.trim().isNotEmpty == true ? funFact.title!.trim() : 'Fun Fact',
            style: const TextStyle(
              color: AppColors.starGold,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          if (funFact.hook?.trim().isNotEmpty == true) ...[
            MarkdownBody(
              data: stripSidCitations(funFact.hook!.trim()),
              styleSheet: _funFactStyle(
                TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
                context,
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (funFact.body?.trim().isNotEmpty == true)
            MarkdownBody(
              data: stripSidCitations(funFact.body!.trim()),
              styleSheet: _funFactStyle(
                TextStyle(color: AppColors.universe.textComet, fontSize: 13, height: 1.4),
                context,
              ),
            ),
        ],
      ),
    );
  }

  MarkdownStyleSheet _funFactStyle(TextStyle base, BuildContext context) {
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base,
      strong: base.copyWith(fontWeight: FontWeight.bold, color: AppColors.universe.textStarlight),
      em: base.copyWith(fontStyle: FontStyle.italic),
      listBullet: base.copyWith(color: AppColors.starGold),
    );
  }
}

// ---------------------------------------------------------------------------
// Keywords View
// ---------------------------------------------------------------------------
class _KeywordsView extends StatelessWidget {
  const _KeywordsView({super.key, required this.keywords});

  final List<Keyword> keywords;

  @override
  Widget build(BuildContext context) {
    if (keywords.isEmpty) {
      return Center(
        child: Text(
          'No keywords yet',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: keywords.length,
      separatorBuilder: (context, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final k = keywords[index];
        final hasDefinition = k.definition?.trim().isNotEmpty == true;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.paper.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                k.keyword?.trim().isNotEmpty == true ? k.keyword!.trim() : 'Untitled term',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                hasDefinition ? k.definition!.trim() : 'Definition pending…',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 14,
                  height: 1.4,
                  fontStyle: hasDefinition ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


// ---------------------------------------------------------------------------
// 1. Review Cards View
// ---------------------------------------------------------------------------
/// Review Cardsタブのフラットなカード1枚分。[card]がnullなら表紙(トピック画像+タイトル)。
class _ReviewCardItem {
  const _ReviewCardItem({required this.groupIndex, this.card});

  final int groupIndex;
  final ReviewCard? card;

  bool get isCover => card == null;
}

class _ReviewCardsView extends HookConsumerWidget {
  const _ReviewCardsView({
    super.key,
    required this.isExpanded,
    required this.currentCardIndex,
    required this.onExpand,
    required this.groups,
  });

  final bool isExpanded;
  final ValueNotifier<int> currentCardIndex;
  final VoidCallback onExpand;
  final List<_ReviewTopicGroup> groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animationController = useAnimationController(
      duration: const Duration(milliseconds: 350),
    );
    useAnimation(animationController);

    final previousCardIndex = useState<int>(currentCardIndex.value);
    final isAnimating = useState<bool>(false);
    final isGoingForward = useState<bool>(true);

    final screenWidth = MediaQuery.of(context).size.width;

    // groupsを「表紙 + コンテンツカード」のフラットな1本のリストに展開する。
    // 「フラットindex -> どのgroupか」「groupごとの開始index」も併せて作っておく。
    final flatItems = useMemoized(() {
      final list = <_ReviewCardItem>[];
      for (var gi = 0; gi < groups.length; gi++) {
        list.add(_ReviewCardItem(groupIndex: gi)); // 表紙
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
        idx += g.cards.length + 1; // +1は表紙
      }
      return starts;
    }, [groups]);

    final totalCards = flatItems.length;

    // トピック画像 (R2からローカルキャッシュ経由で取得)。groupIndex -> File?
    final imageFiles = <int, File?>{};
    for (var gi = 0; gi < groups.length; gi++) {
      final path = groups[gi].imagePath;
      imageFiles[gi] =
          path == null ? null : ref.watch(artifactFileProvider(path)).asData?.value;
    }

    final navigateTo = useCallback((int newIndex, {bool immediate = false}) {
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
      return _ContentCard(card: item.card!, imageFile: imageFile);
    }

    if (totalCards == 0) {
      return Center(
        child: Text(
          'No review cards yet',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    if (!isExpanded) {
      // Collapsed State: Card Dashboard (Start button + Horizontal Scroll Rows)
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: groups.length + 1,
        separatorBuilder: (context, _) => const SizedBox(height: 24),
        itemBuilder: (context, topicIdx) {
          if (topicIdx == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: GestureDetector(
                onTap: () {
                  navigateTo(0, immediate: true);
                  onExpand();
                },
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.starGold, Color(0xFFFFD700)],
                    ),
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.starGold.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_circle_fill, color: AppColors.universe.voidBackground, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Start Review Session!',
                        style: TextStyle(
                          color: AppColors.universe.voidBackground,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final group = groups[topicIdx - 1];
          final groupStart = groupStartIndex[topicIdx - 1];
          final imageFile = imageFiles[topicIdx - 1];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Topic Header
              Text(
                group.title,
                style: TextStyle(
                  color: AppColors.paper.textInk,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),

              // 横スクロールのカード列: 先頭は表紙(画像入り)、続けてコンテンツカード
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: group.cards.length + 1,
                  separatorBuilder: (context, _) => const SizedBox(width: 12),
                  itemBuilder: (context, tileIdx) {
                    if (tileIdx == 0) {
                      // 表紙タイル
                      return GestureDetector(
                        onTap: () {
                          navigateTo(groupStart, immediate: true);
                          onExpand();
                        },
                        child: SizedBox(
                          width: 110,
                          child: _CoverCard(
                            title: group.title,
                            imageFile: imageFile,
                            borderRadius: 16,
                            compact: true,
                          ),
                        ),
                      );
                    }

                    final card = group.cards[tileIdx - 1];
                    final preview = card.title?.trim().isNotEmpty == true
                        ? card.title!.trim()
                        : plainTextPreview(
                            card.cardContent.isNotEmpty ? (card.cardContent.first.text ?? '') : '');
                    return GestureDetector(
                      onTap: () {
                        navigateTo(groupStart + tileIdx, immediate: true);
                        onExpand();
                      },
                      child: Container(
                        width: 110,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.paper.background,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
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
                              Text(card.heroEmoji!.trim(), style: const TextStyle(fontSize: 24)),
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
      );
    }

    // Expanded State: Immersive Instagram Stories-style Card Viewer
    final index = currentCardIndex.value.clamp(0, totalCards - 1);
    final currentGroupIndex = flatItems[index].groupIndex;
    final topic = groups[currentGroupIndex];

    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Topic Title above the card
          Text(
            topic.title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // 2. Stories Progress Indicators (Grouped by Topic, 表紙も1本として数える)
          Row(
            children: List.generate(groups.length, (topicIdx) {
              final group = groups[topicIdx];
              final groupStart = groupStartIndex[topicIdx];
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: List.generate(group.cards.length + 1, (cardIdx) {
                      final absIdx = groupStart + cardIdx;
                      final isFilled = absIdx <= currentCardIndex.value;
                      final isActive = absIdx == currentCardIndex.value;

                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      final activeColor = Theme.of(context).colorScheme.primary;
                      final filledColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.6);
                      final unfilledColor = isDark ? Colors.white12 : Colors.black12;

                      return Expanded(
                        child: Container(
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(
                            color: isActive
                                ? activeColor
                                : isFilled
                                    ? filledColor
                                    : unfilledColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),

          // 3. Card Area
          // タップ判定はカードを覆うオーバーレイではなく、この親GestureDetectorのonTapUpで行う。
          // (オーバーレイ方式だとカード内のスクロールジェスチャーを奪ってしまうため。
          //  Scrollableは縦ドラッグのみを主張するので、タップは親に届き、縦スクロールは
          //  カード内のSingleChildScrollViewが処理する。)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final cardWidth = screenWidth - 32;
                if (details.localPosition.dx < cardWidth * 0.3) {
                  // 左30%タップ → 前のカード
                  if (currentCardIndex.value > 0) {
                    navigateTo(currentCardIndex.value - 1);
                  }
                } else {
                  // 右70%タップ → 次のカード
                  if (currentCardIndex.value < totalCards - 1) {
                    navigateTo(currentCardIndex.value + 1);
                  }
                }
              },
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity == null) return;
                // Swipe Left (velocity < -300) -> Next Topic
                if (details.primaryVelocity! < -300) {
                  if (currentGroupIndex < groups.length - 1) {
                    navigateTo(groupStartIndex[currentGroupIndex + 1]);
                  }
                }
                // Swipe Right (velocity > 300) -> Previous Topic
                else if (details.primaryVelocity! > 300) {
                  if (currentGroupIndex > 0) {
                    navigateTo(groupStartIndex[currentGroupIndex - 1]);
                  }
                }
              },
              child: Builder(
                builder: (context) {
                  if (isAnimating.value) {
                    final progress = animationController.value;
                    if (isGoingForward.value) {
                      return Stack(
                        children: [
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
                              offset: Offset(-progress * screenWidth, 0),
                              child: Transform.rotate(
                                angle: -progress * 0.2,
                                alignment: Alignment.bottomCenter,
                                child: buildCard(previousCardIndex.value),
                              ),
                            ),
                          ),
                        ],
                      );
                    } else {
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: Transform.scale(
                              scale: 1.0 - (0.08 * progress),
                              child: Opacity(
                                opacity: 1.0 - (0.5 * progress),
                                child: buildCard(previousCardIndex.value),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: Transform.translate(
                              offset: Offset(-(1.0 - progress) * screenWidth, 0),
                              child: Transform.rotate(
                                angle: -(1.0 - progress) * 0.2,
                                alignment: Alignment.bottomCenter,
                                child: buildCard(currentCardIndex.value),
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                  } else {
                    return buildCard(currentCardIndex.value);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// トピックの表紙カード。画像を全面に敷き、その上にタイトルを重ねる。
/// 画像の色味が読めないため、タイトルは半透明の白帯 + 白縁取りの黒文字で保護する。
class _CoverCard extends StatelessWidget {
  const _CoverCard({
    required this.title,
    required this.imageFile,
    required this.borderRadius,
    this.compact = false,
  });

  final String title;
  final File? imageFile;
  final double borderRadius;

  /// ダッシュボードの小さいタイル用 (フォント等を縮小)
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final titleStyle = TextStyle(
      color: Colors.black,
      fontSize: compact ? 12 : 22,
      fontWeight: FontWeight.bold,
      height: 1.3,
      // 白縁取り (ハロー) で画像の色に負けないようにする
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
            // 画像がまだ無い場合のフォールバック背景
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFE0B2), Color(0xFFFFF8E1)],
                ),
              ),
            ),
          // タイトル帯 (半透明の白)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 20,
                vertical: compact ? 8 : 16,
              ),
              color: Colors.white.withValues(alpha: 0.72),
              child: Text(
                title,
                style: titleStyle,
                textAlign: TextAlign.center,
                maxLines: compact ? 3 : 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// コンテンツカード。トピック画像がある場合はカードの縁に画像が覗くよう、
/// 画像を背景全面に敷いた上で、少し内側に本文パネルを重ねる。
class _ContentCard extends StatelessWidget {
  const _ContentCard({required this.card, required this.imageFile});

  final ReviewCard card;
  final File? imageFile;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasImage = imageFile != null;

    final content = SingleChildScrollView(
      padding: EdgeInsets.all(hasImage ? 20 : 28),
      child: Column(
        children: [
          Text(
            card.heroEmoji?.trim().isNotEmpty == true ? card.heroEmoji!.trim() : '💡',
            style: const TextStyle(fontSize: 56),
          ),
          const SizedBox(height: 24),
          if (card.title?.trim().isNotEmpty == true) ...[
            Text(
              card.title!.trim(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
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
                child: _ReviewCardBlockView(block: block),
              )),
        ],
      ),
    );

    if (!hasImage) {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.universe.glassWhiteLow : AppColors.paper.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? AppColors.universe.glassBorder : Colors.black.withValues(alpha: 0.08),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black38 : Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: content,
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        image: DecorationImage(image: FileImage(imageFile!), fit: BoxFit.cover),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black38 : Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      // 縁として画像を見せるための余白
      padding: const EdgeInsets.all(10),
      child: Container(
        decoration: BoxDecoration(
          color: (isDark ? AppColors.universe.voidBackground : AppColors.paper.surface)
              .withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(16),
        ),
        child: content,
      ),
    );
  }
}

/// review_cards.card_content の1ブロック（paragraph / quote / list）を描画する。
/// テキストはMarkdown(太字など)を含むためMarkdownBodyで描画し、SID引用は除去する。
class _ReviewCardBlockView extends StatelessWidget {
  const _ReviewCardBlockView({required this.block});

  final ReviewCardBlock block;

  MarkdownStyleSheet _styleSheet(BuildContext context, {bool italic = false}) {
    final baseColor = Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.9);
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
        color: Theme.of(context).colorScheme.onSurface,
      ),
      em: style.copyWith(fontStyle: FontStyle.italic),
      code: style.copyWith(fontFamily: 'monospace', backgroundColor: Colors.transparent),
      listBullet: style.copyWith(color: AppColors.starGold),
      textAlign: WrapAlignment.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (block.type) {
      case 'quote':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.starGold, width: 3)),
          ),
          child: MarkdownBody(
            data: stripSidCitations(block.text ?? ''),
            styleSheet: _styleSheet(context, italic: true).copyWith(textAlign: WrapAlignment.start),
          ),
        );
      case 'list':
        final items = block.items ?? const <String>[];
        // 各itemをMarkdownの箇条書きにまとめて1つのMarkdownBodyで描画する
        final markdown = items.map((item) => '- ${stripSidCitations(item)}').join('\n');
        return MarkdownBody(
          data: markdown,
          styleSheet: _styleSheet(context).copyWith(textAlign: WrapAlignment.start),
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

// ---------------------------------------------------------------------------
// 2. Deep Notes View
// ---------------------------------------------------------------------------
class _DeepNotesView extends HookWidget {
  const _DeepNotesView({
    super.key,
    required this.isExpanded,
    required this.selectedNoteIndex,
    required this.onExpand,
    required this.selectedText,
    required this.topics,
  });

  final bool isExpanded;
  final ValueNotifier<int?> selectedNoteIndex;
  final VoidCallback onExpand;
  final ValueNotifier<String?> selectedText;
  final List<_NoteTopic> topics;

  @override
  Widget build(BuildContext context) {
    final shouldStartAtBottom = useState(false);
    final noteIndex = selectedNoteIndex.value;

    if (topics.isEmpty) {
      return Center(
        child: Text(
          'Deep notes are being generated…',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: noteIndex == null
          ? _buildNoteList(context)
          : _NoteDetailView(
              key: ValueKey('note_detail_$noteIndex'),
              noteIndex: noteIndex,
              topic: topics[noteIndex],
              totalTopics: topics.length,
              startAtBottom: shouldStartAtBottom.value,
              selectedText: selectedText,
              onNext: () {
                if (noteIndex < topics.length - 1) {
                  shouldStartAtBottom.value = false;
                  selectedNoteIndex.value = noteIndex + 1;
                }
              },
              onPrev: () {
                if (noteIndex > 0) {
                  shouldStartAtBottom.value = true;
                  selectedNoteIndex.value = noteIndex - 1;
                }
              },
            ),
    );
  }

  Widget _buildNoteList(BuildContext context) {
    return ListView.separated(
      key: const ValueKey('note_list'),
      padding: const EdgeInsets.all(16),
      itemCount: topics.length,
      separatorBuilder: (context, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final topic = topics[index];
        return GestureDetector(
          onTap: () {
            selectedNoteIndex.value = index;
            onExpand();
          },
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.paper.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
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
                        const SizedBox(height: 8),
                        Text(
                          topic.summary,
                          style: TextStyle(
                            color: AppColors.paper.textPencil,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.primary, size: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NoteDetailView extends HookWidget {
  const _NoteDetailView({
    super.key,
    required this.noteIndex,
    required this.topic,
    required this.totalTopics,
    required this.startAtBottom,
    required this.onNext,
    required this.onPrev,
    required this.selectedText,
  });

  final int noteIndex;
  final _NoteTopic topic;
  final int totalTopics;
  final bool startAtBottom;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final ValueNotifier<String?> selectedText;

  @override
  Widget build(BuildContext context) {
    final scrollController = useScrollController();
    final isTransitioning = useState(false);
    
    // Markers to track where scroll gestures start
    final startedAtTop = useState(false);
    final startedAtBottom = useState(false);
    final shouldGoToNext = useState(false);
    final shouldGoToPrev = useState(false);

    // Jump to bottom if startAtBottom is true
    useEffect(() {
      if (startAtBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollController.hasClients) {
            scrollController.jumpTo(scrollController.position.maxScrollExtent);
          }
        });
      }
      return null;
    }, [noteIndex]);

    return Container(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (isTransitioning.value) return false;
                
                // Track where scroll starts
                if (notification is ScrollStartNotification) {
                  final metrics = notification.metrics;
                  startedAtTop.value = metrics.pixels <= 0.0;
                  startedAtBottom.value = metrics.pixels >= metrics.maxScrollExtent;
                  shouldGoToNext.value = false;
                  shouldGoToPrev.value = false;
                }
                
                // Trigger transitions ONLY when the user releases their finger (dragDetails becomes null)
                if (notification is ScrollEndNotification || 
                    (notification is ScrollUpdateNotification && notification.dragDetails == null)) {
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
                
                // Detect overscroll boundaries
                if (notification is ScrollUpdateNotification) {
                  final metrics = notification.metrics;
                  final isDragging = notification.dragDetails != null;
                  
                  if (isDragging) {
                    if (startedAtBottom.value && metrics.pixels >= metrics.maxScrollExtent + 50 && noteIndex < totalTopics - 1) {
                      shouldGoToNext.value = true;
                    }
                    if (startedAtTop.value && metrics.pixels <= metrics.minScrollExtent - 50 && noteIndex > 0) {
                      shouldGoToPrev.value = true;
                    }

                    // Reset page turn intent if user scrolls back before releasing
                    if (shouldGoToNext.value && metrics.pixels < metrics.maxScrollExtent + 10) {
                      shouldGoToNext.value = false;
                    }
                    if (shouldGoToPrev.value && metrics.pixels > metrics.minScrollExtent - 10) {
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
                onSelectionChanged: (content) {
                  selectedText.value = content?.plainText;
                },
                contextMenuBuilder: (context, selectableRegionState) {
                  return const SizedBox.shrink(); // Suppress standard OS selection menu
                },
                child: ListView(
                  controller: scrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  children: [
                    // Upper Arrow indicator (if previous note exists)
                    if (noteIndex > 0)
                      Center(
                        child: Column(
                          children: [
                            IconButton(
                              icon: Icon(Icons.keyboard_arrow_up, color: Theme.of(context).colorScheme.primary, size: 28),
                              onPressed: onPrev,
                            ),
                            const Text(
                              'Pull or tap to previous note',
                              style: TextStyle(color: Colors.white30, fontSize: 11),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),

                    Text(
                      topic.title,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (topic.summary.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        topic.summary,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 15,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    MarkdownBody(
                      data: topic.content.isNotEmpty
                          ? topic.content
                          : 'Deep notes for this topic are still being generated…',
                      selectable: false,
                      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                        p: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 16,
                          height: 1.6,
                        ),
                        h1: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        h2: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        h3: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        listBullet: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.starGold
                              : AppColors.deepGold,
                          fontSize: 16,
                        ),
                        code: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.greenAccent
                              : const Color(0xFF0F766E),
                          fontFamily: 'monospace',
                          fontSize: 14,
                          backgroundColor: Colors.transparent,
                        ),
                        codeblockPadding: const EdgeInsets.all(16),
                        codeblockDecoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.black45
                              : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? AppColors.universe.glassBorder
                                : Colors.black.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Lower Arrow indicator (if next note exists)
                    if (noteIndex < totalTopics - 1)
                      Center(
                        child: Column(
                          children: [
                            const SizedBox(height: 16),
                            IconButton(
                              icon: Icon(Icons.keyboard_arrow_down, color: Theme.of(context).colorScheme.primary, size: 28),
                              onPressed: onNext,
                            ),
                            const Text(
                              'Pull or tap to next note',
                              style: TextStyle(color: Colors.white30, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Transcript View
// ---------------------------------------------------------------------------
class _TranscriptView extends StatelessWidget {
  const _TranscriptView({super.key, required this.transcriptAsync});

  final AsyncValue<List<TranscriptSentence>?> transcriptAsync;

  static String _formatMs(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return transcriptAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.starGold)),
      error: (err, _) => Center(
        child: Text(
          'Transcript unavailable',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
      data: (sentences) {
        if (sentences == null || sentences.isEmpty) {
          return Center(
            child: Text(
              'Transcript is being generated…',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          );
        }
        return Container(
          color: Colors.transparent,
          child: ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: sentences.length,
            separatorBuilder: (context, _) => const SizedBox(height: 24),
            itemBuilder: (context, index) {
              final sentence = sentences[index];
              final isSideChatter = sentence.role != 'lecture';
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatMs(sentence.start),
                    style: const TextStyle(
                      color: AppColors.starGold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      sentence.text,
                      style: TextStyle(
                        color: isSideChatter
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                        height: 1.5,
                        fontStyle: isSideChatter ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _LectureAppBar extends StatelessWidget {
  const _LectureAppBar();

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.only(top: safeTop, left: 16, right: 16, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => context.pop(),
              ),
              const SizedBox(width: 8),
              const RecordingTimerChip(),
            ],
          ),
          GestureDetector(
            onTap: () => context.push(AppRoutes.profile),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    value: 0.7,
                    strokeWidth: 3,
                    backgroundColor: AppColors.universe.glassWhiteLow,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.starGold),
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: const Icon(Icons.person, color: Colors.grey, size: 20),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _MeasureSize extends StatefulWidget {
  final Widget child;
  final OnWidgetSizeChange onChange;

  const _MeasureSize({
    required this.onChange,
    required this.child,
  });

  @override
  _MeasureSizeState createState() => _MeasureSizeState();
}

typedef OnWidgetSizeChange = void Function(Size size);

class _MeasureSizeState extends State<_MeasureSize> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          widget.onChange(box.size);
        }
      }
    });
    return widget.child;
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}