// lib/presentation/pages/review_cards/review_cards_viewer_page.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_providers.dart';
import 'package:lecture_companion_ui/application/lecture_viewer/lecture_viewer_data_provider.dart';
import 'package:lecture_companion_ui/core/utils/annotation_text_utils.dart';
import 'package:lecture_companion_ui/core/utils/sid_citation.dart';
import 'package:lecture_companion_ui/core/utils/text_preview.dart';
import 'package:lecture_companion_ui/domain/entities/annotation.dart';
import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_topic.dart';
import 'package:lecture_companion_ui/domain/entities/review_card.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/repositories/review_card_repository_drift.dart';
import 'package:lecture_companion_ui/presentation/pages/course/widgets/course_style_helper.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/card_selection_toolbar.dart';
import 'package:lecture_companion_ui/presentation/widgets/highlight_sub_toolbar.dart';
import 'package:lecture_companion_ui/presentation/widgets/markdown_annotation_builder.dart';
import 'package:lecture_companion_ui/presentation/widgets/note_sub_toolbar.dart';
import 'package:lecture_companion_ui/presentation/widgets/announcement_transcript_modal.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_data.dart';

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

// Maps the shared transition [overall] progress (0..1) to a layer's own local
// progress (0..1), staggering [stepIndex] of [totalSteps] so later layers
// start (and finish) slightly after earlier ones, with some overlap so the
// motion reads as one continuous cascade rather than separate steps.
double _staggeredLocal(double overall, int stepIndex, int totalSteps) {
  if (totalSteps <= 1) return overall;
  const overlap = 0.5;
  final windowWidth = (1.0 / totalSteps) * (1 + overlap);
  final stepGap = (1.0 - windowWidth) / (totalSteps - 1);
  final begin = stepIndex * stepGap;
  final end = (begin + windowWidth).clamp(0.0, 1.0);
  if (end <= begin) return overall >= end ? 1.0 : 0.0;
  return Curves.easeInOut.transform(
    ((overall - begin) / (end - begin)).clamp(0.0, 1.0),
  );
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
    final cardsAsync = ref.watch(reviewCardsProvider(lectureId));

    final groups = useMemoized(() {
      final topics = topicsAsync.asData?.value ?? <LectureTopic>[];
      final cards = cardsAsync.asData?.value ?? <ReviewCard>[];
      final map = <int, List<ReviewCard>>{};
      for (final c in cards) {
        map.putIfAbsent(c.topicNumber, () => []).add(c);
      }
      return topics
          .map(
            (t) => _ReviewTopicGroup(
              topicNumber: t.index,
              title: t.displayTitle,
              cards: sortReviewCards(map[t.index] ?? []),
              imagePath: t.imagePath,
            ),
          )
          .toList();
    }, [topicsAsync, cardsAsync]);

    if (cardsAsync.isLoading || topicsAsync.isLoading) {
      return Scaffold(
        backgroundColor: AppColors.paper.background,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.deepGold),
        ),
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
        ? CourseStyleHelper.hexToColor(
            course.color,
            fallback: AppColors.deepGold,
          )
        : AppColors.deepGold;

    final HSLColor hsl = HSLColor.fromColor(themeColor);
    final textThemeColor = hsl.lightness > 0.65
        ? hsl.withLightness(0.5).toColor()
        : themeColor;

    final animationController = useAnimationController(
      duration: const Duration(milliseconds: 350),
    );
    final currentCardIndex = useState<int>(initialIndex);
    final previousCardIndex = useState<int>(initialIndex);
    final isAnimating = useState<bool>(false);
    final isGoingForward = useState<bool>(true);

    // Tracks whether the user currently has text selected inside the card.
    // A tap that lands on top of an existing selection should just dismiss
    // it, not also be treated as a page-navigation tap -- otherwise the
    // navigation GestureDetector and SelectionArea fight over the same tap
    // (navigating away mid-selection, or landing a selection on the card you
    // just navigated to).
    final hasSelection = useState<bool>(false);
    // 現在選択されているプレーンテキスト。Highlight/Note確定時に、どのブロックの
    // どの範囲かを逆引きするために使う(SelectedContent.plainTextをそのまま保持)。
    final selectedText = useState<String?>(null);
    // カード本文(ブロック群のみ、タイトル/絵文字は除く)専用のSelectionListener。
    // SelectableRegionは選択範囲の絶対文字位置(SelectedContentRange)を公開する
    // publicなAPIを持たないため、範囲を正確に取得するにはこのSelectionListener
    // 経由で取得する必要がある。カードが変わるたびに作り直す(かつては同時に
    // 複数の_ContentCardが並行してマウントされる遷移アニメーション中に、同じ
    // notifierへ二重登録されるのを避けるため、現在表示中のカードにしか渡さない)。
    final selectionListenerNotifier = useMemoized(
      () => SelectionListenerNotifier(),
      [currentCardIndex.value],
    );
    useEffect(() => selectionListenerNotifier.dispose, [selectionListenerNotifier]);
    // Highlightサブツールバー(line/wave/marker/eraser + 色選択)の開閉状態。
    final highlightToolbarOpen = useState<bool>(false);
    final highlightMode = useState<String?>(null);
    final highlightColor = useState<Color>(CourseStyleHelper.presetColors.first);
    // Noteサブツールバーの開閉状態。Highlightと同時に開かないよう排他制御する。
    final noteToolbarOpen = useState<bool>(false);
    // Noteツールバーを開いた時点の選択範囲をキャッシュしておく。TextFieldに
    // フォーカスが移るとSelectableRegionの選択は自動解除されてしまうため、
    // 保存時に生の選択範囲を読み直すと取得できない。
    final cachedNoteLocation = useState<TextLocation?>(null);
    // 注: テキスト選択ハンドルはFlutter内部で常にOverlayの一番上に新規追加される
    // ため(SelectionOverlay.showHandles)、OverlayPortal経由でサブツールバーを
    // 前面に出す手段は無い(ホストのOverlayEntryスロット固定で、show()呼び出し
    // 順は無関係)。ハンドルとサブツールバーが重なることは許容する。
    // Rebuilt (and thus given a fresh GlobalKey) every time the current card
    // changes. SelectableRegion's internal selection registrar doesn't
    // survive having its descendant Text/RichText widgets torn down and
    // remounted across navigations cleanly -- after even one navigation, the
    // shared SelectableRegionState stops recognizing new selection gestures
    // entirely, on every card, permanently. Forcing a full remount per card
    // resets it to a known-good state instead of reusing the tainted one.
    final selectionAreaKey = useMemoized(
      () => GlobalKey<SelectionAreaState>(),
      [currentCardIndex.value],
    );
    final temporaryHighlight = useState<Annotation?>(null);
    final temporaryHighlightBlockIdx = useState<int?>(null);
    final activeNoteAnnotation = useState<Annotation?>(null);
    final isEditingNote = useState<bool>(false);
    // カードを切り替えたら、開いたままのサブツールバーとキャッシュ済み選択範囲を
    // 破棄する。NoteSubToolbarはカード切り替え後も選択解除だけでは閉じなく
    // なったため、切り替え自体をトリガーに明示的に閉じる必要がある(放置すると
    // 別カード宛のcachedNoteLocationで保存してしまう)。
    useEffect(() {
      highlightToolbarOpen.value = false;
      noteToolbarOpen.value = false;
      cachedNoteLocation.value = null;
      temporaryHighlight.value = null;
      temporaryHighlightBlockIdx.value = null;
      activeNoteAnnotation.value = null;
      isEditingNote.value = false;
      return null;
    }, [currentCardIndex.value]);

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

    // ノート編集をキャンセルする(保存せずに閉じる)。外側タップ時に呼ばれる。
    void cancelNote() {
      if (!noteToolbarOpen.value) return;
      noteToolbarOpen.value = false;
      cachedNoteLocation.value = null;
      temporaryHighlight.value = null;
      temporaryHighlightBlockIdx.value = null;
      selectionAreaKey.currentState?.selectableRegion.clearSelection();
    }

    void closeActiveNote() {
      activeNoteAnnotation.value = null;
      isEditingNote.value = false;
      temporaryHighlight.value = null;
      temporaryHighlightBlockIdx.value = null;
    }

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
        card: item.card!,
        imageFile: imageFile,
        themeColor: textThemeColor,
        // Only the settled (non-animating) current card gets the live
        // notifier. During a swipe transition this same card is *also*
        // rendered as one of the animated `layers` in a structurally
        // different part of the tree (wrapped in Transform/Positioned);
        // attaching the same SelectionListenerNotifier to both would mean
        // two SelectionListener widgets fighting over one notifier within
        // the same frame (the old Element hasn't finished disposing before
        // the new one tries to register), which throws
        // '!registered'. Selection during a swipe is meaningless anyway, so
        // simply withholding the notifier while animating avoids the clash.
        selectionListenerNotifier:
            cardIdx == currentCardIndex.value && !isAnimating.value
                ? selectionListenerNotifier
                : null,
        temporaryHighlight: cardIdx == currentCardIndex.value ? temporaryHighlight.value : null,
        temporaryHighlightBlockIdx: cardIdx == currentCardIndex.value ? temporaryHighlightBlockIdx.value : null,
        onAnnotationTap: (a) {
          if (a.annotationType == 'notes') {
            cancelNote();
            activeNoteAnnotation.value = a;
            isEditingNote.value = false;
            temporaryHighlight.value = a;
            temporaryHighlightBlockIdx.value = a.blockIdx;
          }
        },
      );
    }

    final index = currentCardIndex.value.clamp(0, totalCards - 1);
    final currentGroupIndex = flatItems[index].groupIndex;
    final topic = groups[currentGroupIndex];

    // 現在選択中の範囲が、現在のカードのどのブロックの何文字目〜何文字目に
    // あたるかを求める。SelectableRegion.getSelection()はタイトル/絵文字を
    // 除いた本文(ブロック群)だけを対象にした絶対文字位置を返すので、テキスト
    // 検索(indexOf)と違って同じ文字列の重複があっても正確に一致する。
    TextLocation? locateSelection() {
      final card = flatItems[index].card;
      if (card == null || !selectionListenerNotifier.registered) return null;
      final range = selectionListenerNotifier.selection.range;
      if (range == null) return null;
      return locateFromReviewCardRange(card, range);
    }

    Future<void> commitHighlight(String mode) async {
      final card = flatItems[index].card;
      final located = locateSelection();
      if (card == null || located == null) return;
      final repo = widgetRef.read(reviewCardRepositoryDriftProvider);
      if (mode == 'eraser') {
        final blockText = reviewCardBlockPlainText(card.cardContent[located.blockIdx!]);
        await repo.eraseHighlightRange(
          cardId: card.id,
          blockIdx: located.blockIdx,
          startIdx: located.startIdx,
          endIdx: located.endIdx,
          blockText: blockText,
        );
      } else {
        await repo.addAnnotation(
          cardId: card.id,
          blockIdx: located.blockIdx,
          startIdx: located.startIdx,
          endIdx: located.endIdx,
          annotationType: 'highlight',
          annotatedWords: selectedText.value!,
          contents: {'type': mode, 'color': colorToHex(highlightColor.value)},
        );
      }
      widgetRef.read(lectureControllerProvider.notifier).pushOutboxNow();
      selectionAreaKey.currentState?.selectableRegion.clearSelection();
      highlightToolbarOpen.value = false;
    }

    Future<void> commitNote(String text) async {
      final card = flatItems[index].card;
      // TextFieldにフォーカスが移った時点で選択は解除済みのため、Noteツールバーを
      // 開いた時点でキャッシュしておいた選択範囲を使う(locateSelection()の
      // 生の値はこの時点では既にnullになっている)。
      final located = cachedNoteLocation.value;
      if (card == null || located == null || text.trim().isEmpty) return;
      await widgetRef.read(reviewCardRepositoryDriftProvider).addAnnotation(
            cardId: card.id,
            blockIdx: located.blockIdx,
            startIdx: located.startIdx,
            endIdx: located.endIdx,
            annotationType: 'notes',
            annotatedWords: selectedText.value!,
            contents: text.trim(),
          );
      widgetRef.read(lectureControllerProvider.notifier).pushOutboxNow();
      selectionAreaKey.currentState?.selectableRegion.clearSelection();
      noteToolbarOpen.value = false;
      cachedNoteLocation.value = null;
      temporaryHighlight.value = null;
      temporaryHighlightBlockIdx.value = null;
    }


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
              // ── Row 2: Grid view button, toolbar & Page counter ──
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.grid_view,
                        color: AppColors.paper.textInk,
                      ),
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
                    Expanded(
                      child: flatItems[index].isCover
                          ? const SizedBox.shrink()
                          : CardSelectionToolbar(
                              hasSelection: hasSelection.value,
                              accentColor: textThemeColor,
                              reaction: flatItems[index].card?.reaction,
                              saved: flatItems[index].card?.saved ?? false,
                              isHighlightActive: highlightToolbarOpen.value,
                              onHighlightTap: () {
                                highlightToolbarOpen.value = !highlightToolbarOpen.value;
                                if (highlightToolbarOpen.value) cancelNote();
                              },
                              isNoteActive: noteToolbarOpen.value,
                              onNoteTap: () {
                                if (noteToolbarOpen.value) {
                                  // 既に開いている場合の再タップはキャンセル扱い
                                  // (保存しない)。
                                  cancelNote();
                                  return;
                                }
                                // 開く瞬間の選択範囲をキャッシュする。TextFieldに
                                // フォーカスが移った後は選択が解除されており、
                                // この時点でしか読み取れない。
                                final located = locateSelection();
                                if (located == null) return;
                                cachedNoteLocation.value = located;
                                highlightToolbarOpen.value = false;
                                noteToolbarOpen.value = true;

                                // 選択をダミーでハイライトしたまま維持する
                                // (Source機能と同じパターン)。clearSelection()と
                                // 同じフレーム内でMarkdownBodyのKeyを変えると
                                // SelectionAreaが再入アサーションを起こすことが
                                // あるため、次フレームまで遅延させる。
                                selectionAreaKey.currentState?.selectableRegion
                                    .clearSelection();
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  temporaryHighlight.value = Annotation(
                                    id: '-1',
                                    blockIdx: located.blockIdx,
                                    startIdx: located.startIdx,
                                    endIdx: located.endIdx,
                                    annotationType: 'highlight',
                                    annotatedWords: '',
                                    contents: const {
                                      'type': 'marker',
                                      'color': '#FFE082',
                                    },
                                  );
                                  temporaryHighlightBlockIdx.value = located.blockIdx;
                                });
                              },
                              onSourceTap: () async {
                                final card = flatItems[index].card;
                                final located = locateSelection();
                                if (card == null || located == null) return;

                                try {
                                  final block = card.cardContent[located.blockIdx!];
                                  final rawText = reviewCardBlockRawMarkdownSource(block);

                                  final result = findSourceContextRange(
                                    rawText,
                                    located.startIdx,
                                    located.endIdx,
                                  );

                                  if (result == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('No source found for the selection.'),
                                      ),
                                    );
                                    return;
                                  }

                                  final citation = result.citation;

                                  // Debug Log
                                  final uid = supabase.auth.currentUser?.id;
                                  if (uid != null && lectureId.isNotEmpty) {
                                    try {
                                      final sentences = await widgetRef.read(transcriptProvider(uid: uid, lectureId: lectureId).future);
                                      if (!context.mounted) return;
                                      if (sentences != null) {
                                        final targetSid = citation.sidStrings.first;
                                        TranscriptSentence? targetSentence;
                                        for (final s in sentences) {
                                          if (s.sid == targetSid) {
                                            targetSentence = s;
                                            break;
                                          }
                                        }
                                        final flattenedMap = buildFlattenedTextMap(rawText);
                                        final rawEnd = flattenedMap.toRaw(located.endIdx);
                                        final citationEndWithMargin = (citation.end + 5) > rawText.length
                                            ? rawText.length
                                            : (citation.end + 5);
                                        final textUntilCitation = rawText.substring(rawEnd, citationEndWithMargin);

                                        debugPrint("=== Source Navigation Debug Log (Review Card) ===");
                                        debugPrint("1. Selected Text: '${selectedText.value}'");
                                        debugPrint("2. Text until citation: '$textUntilCitation'");
                                        debugPrint("3. Resolved SID: '$targetSid'");
                                        debugPrint("4. Transcript Sentence: '${targetSentence?.text}'");
                                        debugPrint("=================================================");
                                      }
                                    } catch (e) {
                                      debugPrint("Failed to output debug log: $e");
                                    }
                                  }

                                  // 選択状態をクリア
                                  selectionAreaKey.currentState?.selectableRegion.clearSelection();

                                  // 一時的ハイライトを設定 (メモリ内アノテーション)
                                  // NOTE: この代入はMarkdownBodyのKeyを変え、選択中の
                                  // Selectableを即座に破棄・再生成させる。clearSelection()
                                  // が同一フレーム内でScrollableのSelection状態をリセットし
                                  // 切る前にこれを行うと、SelectionAreaがScrollable内で
                                  // '_selectionStartsInScrollable' の再入アサーションを
                                  // 起こすことがあるため、次フレームまで遅延させる。
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    temporaryHighlight.value = Annotation(
                                      id: '-1', // Dummy ID
                                      blockIdx: located.blockIdx,
                                      startIdx: result.startIdx,
                                      endIdx: result.endIdx,
                                      annotationType: 'highlight',
                                      annotatedWords: '',
                                      contents: const {'type': 'marker', 'color': '#FFE082'}, // 琥珀色のマーカー
                                    );
                                    temporaryHighlightBlockIdx.value = located.blockIdx;
                                  });

                                  final sortedSids = List<int>.from(citation.sids)..sort();
                                  final startSid = formatSid(sortedSids.first);
                                  final endSid = formatSid(sortedSids.last);

                                  final courseIdVal = course?.id;
                                  if (!context.mounted) return;
                                  if (lectureId.isNotEmpty) {
                                    await showAnnouncementTranscriptModal(
                                      context,
                                      lectureId: lectureId,
                                      startSid: startSid,
                                      endSid: endSid,
                                      highlightSids: citation.sidStrings,
                                      courseId: courseIdVal,
                                    );
                                  }

                                  // モーダルが閉じられたら一時的ハイライトを消去
                                  // (同様の理由でクリア後の再構築も次フレームに遅延させる)
                                  selectionAreaKey.currentState?.selectableRegion.clearSelection();
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    temporaryHighlight.value = null;
                                    temporaryHighlightBlockIdx.value = null;
                                  });

                                } on SelectionTooBroadException catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.message)),
                                  );
                                }
                              },
                              onCopyTap: () async {
                                final text = selectedText.value;
                                if (text != null && text.isNotEmpty) {
                                  await Clipboard.setData(ClipboardData(text: text));
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Copied to clipboard'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                                onLike: flatItems[index].card == null
                                    ? null
                                    : () async {
                                        await widgetRef.read(reviewCardRepositoryDriftProvider).updateReaction(
                                              id: flatItems[index].card!.id,
                                              reaction: flatItems[index].card!.reaction == 'like' ? null : 'like',
                                            );
                                        widgetRef.read(lectureControllerProvider.notifier).pushOutboxNow();
                                      },
                                onDislike: flatItems[index].card == null
                                    ? null
                                    : () async {
                                        await widgetRef.read(reviewCardRepositoryDriftProvider).updateReaction(
                                              id: flatItems[index].card!.id,
                                              reaction: flatItems[index].card!.reaction == 'dislike' ? null : 'dislike',
                                            );
                                        widgetRef.read(lectureControllerProvider.notifier).pushOutboxNow();
                                      },
                                onSave: flatItems[index].card == null
                                    ? null
                                    : () async {
                                        await widgetRef.read(reviewCardRepositoryDriftProvider).updateSaved(
                                              id: flatItems[index].card!.id,
                                              saved: !flatItems[index].card!.saved,
                                            );
                                        widgetRef.read(lectureControllerProvider.notifier).pushOutboxNow();
                                      },
                              ),
                    ),
                    const SizedBox(width: 8),
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
                          children: List.generate(group.cards.length + 1, (
                            cardIdx,
                          ) {
                            final absIdx = groupStart + cardIdx;
                            final isFilled = absIdx <= index;
                            final isActive = absIdx == index;
                            return Expanded(
                              child: Container(
                                height: 3,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? textThemeColor
                                      : isFilled
                                      ? textThemeColor.withValues(alpha: 0.55)
                                      : Colors.white,
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
              ),
              const SizedBox(height: 12),

              // ── Card area ────────────────────────────────────────────────
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SelectionArea(
                        key: selectionAreaKey,
                    contextMenuBuilder: (context, selectableRegionState) =>
                        const SizedBox.shrink(),
                    onSelectionChanged: (content) {
                      hasSelection.value =
                          content != null && content.plainText.isNotEmpty;
                      if (hasSelection.value) {
                        selectedText.value = content!.plainText;
                      } else {
                        highlightToolbarOpen.value = false;
                        // NoteSubToolbar内のTextFieldにフォーカスが移る際にも
                        // ここを通るが、Noteツールバーは選択解除では閉じない
                        // (保存/再タップで明示的に閉じるまで開いたままにする)。
                      }
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) {
                        if (hasSelection.value) {
                          // A tap while text is selected just dismisses the
                          // selection; it shouldn't also navigate.
                          selectionAreaKey.currentState?.selectableRegion
                              .clearSelection();
                          return;
                        }
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
                        if (hasSelection.value) return;
                        if (details.primaryVelocity == null) return;
                        if (details.primaryVelocity! < -300) {
                          if (currentGroupIndex < groups.length - 1) {
                            navigateTo(groupStartIndex[currentGroupIndex + 1]);
                          }
                        } else if (details.primaryVelocity! > 300) {
                          final currentTopicCoverIndex =
                              groupStartIndex[currentGroupIndex];
                          if (currentCardIndex.value > currentTopicCoverIndex) {
                            // Jump to the cover of the current topic if we are on a content card
                            navigateTo(currentTopicCoverIndex);
                          } else if (currentGroupIndex > 0) {
                            // Jump to the cover of the previous topic only if we are already on the current cover
                            navigateTo(groupStartIndex[currentGroupIndex - 1]);
                          }
                        }
                      },
                      child: Builder(
                        builder: (context) {
                          // Pre-warm the widget cache for both neighbors so the
                          // Markdown parse / decoration setup for the next card
                          // has already happened by the time it's actually
                          // needed, instead of paying that cost synchronously
                          // at the start of the transition.
                          if (currentCardIndex.value > 0) {
                            buildCard(currentCardIndex.value - 1);
                          }
                          if (currentCardIndex.value < totalCards - 1) {
                            buildCard(currentCardIndex.value + 1);
                          }

                          final currentCard = buildCard(currentCardIndex.value);

                          return AnimatedBuilder(
                            animation: animationController,
                            builder: (context, _) {
                              if (isAnimating.value) {
                                final progress = animationController.value;
                                final oldIndex = previousCardIndex.value;
                                final newIndex = currentCardIndex.value;
                                // Multi-card swipes (e.g. jumping straight to
                                // the next/previous topic cover) skip over
                                // several cards at once. Represent each
                                // skipped card (max 5, since topics are a
                                // fixed 5 cards) as its own real, stacked
                                // layer instead of a single generic
                                // transition. Layer 0 is always [oldIndex] and
                                // the last layer is always [newIndex] exactly
                                // -- middle layers are sampled proportionally
                                // when the real distance is larger than the
                                // number of layer slots, so the animation
                                // never lands anywhere but the true target.
                                final totalDistance = (newIndex - oldIndex)
                                    .abs();
                                final skipCount = totalDistance.clamp(1, 5);
                                final sign = newIndex >= oldIndex ? 1 : -1;
                                final layers = <Widget>[
                                  for (var d = 0; d <= skipCount; d++)
                                    buildCard(
                                      (d == skipCount
                                              ? newIndex
                                              : oldIndex +
                                                    sign *
                                                        ((d * totalDistance) ~/
                                                            skipCount))
                                          .clamp(0, totalCards - 1),
                                    ),
                                ];

                                if (isGoingForward.value) {
                                  // Only the final destination layer grows in
                                  // from underneath; the cards flying past on
                                  // top of it all stay the same size as each
                                  // other (only their position/rotation
                                  // changes) so the stack doesn't look like it
                                  // shrinks as it goes deeper.
                                  final finalRestScale = 1.0 - 0.08 * skipCount;
                                  return Stack(
                                    children: [
                                      Positioned.fill(
                                        child: Transform.scale(
                                          scale:
                                              finalRestScale +
                                              (1.0 - finalRestScale) * progress,
                                          child: Opacity(
                                            opacity: 0.5 + (0.5 * progress),
                                            child: layers[skipCount],
                                          ),
                                        ),
                                      ),
                                      for (var d = skipCount - 1; d >= 0; d--)
                                        Positioned.fill(
                                          child: Transform.translate(
                                            offset: Offset(
                                              -_staggeredLocal(
                                                    progress,
                                                    d,
                                                    skipCount,
                                                  ) *
                                                  screenWidth,
                                              0,
                                            ),
                                            child: Transform.rotate(
                                              angle:
                                                  -_staggeredLocal(
                                                    progress,
                                                    d,
                                                    skipCount,
                                                  ) *
                                                  0.2,
                                              alignment: Alignment.bottomCenter,
                                              child: layers[d],
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
                                            child: layers[0],
                                          ),
                                        ),
                                      ),
                                      for (var d = 1; d <= skipCount; d++)
                                        Positioned.fill(
                                          child: Transform.translate(
                                            offset: Offset(
                                              -(1.0 -
                                                      _staggeredLocal(
                                                        progress,
                                                        d - 1,
                                                        skipCount,
                                                      )) *
                                                  screenWidth,
                                              0,
                                            ),
                                            child: Transform.rotate(
                                              angle:
                                                  -(1.0 -
                                                      _staggeredLocal(
                                                        progress,
                                                        d - 1,
                                                        skipCount,
                                                      )) *
                                                  0.2,
                                              alignment: Alignment.bottomCenter,
                                              child: layers[d],
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                }
                              }
                              return currentCard;
                            },
                          );
                        },
                      ),
                    ),
                        ),
                      ),
                    if (highlightToolbarOpen.value && hasSelection.value)
                      HighlightSubToolbar(
                        color: highlightColor.value,
                        onColorChanged: (c) => highlightColor.value = c,
                        activeMode: highlightMode.value,
                        onModeSelected: (m) {
                          highlightMode.value = m;
                          commitHighlight(m);
                        },
                      ),
                    if (noteToolbarOpen.value)
                      // Noteツールバーの外側をタップしたら保存せずキャンセルする。
                      // NoteSubToolbar自体はこのcatcherより後(=Stack上で手前)に
                      // 置かれているので、ツールバー自身へのタップはこちらまで
                      // 落ちてこない。
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: cancelNote,
                        ),
                      ),
                    if (noteToolbarOpen.value)
                      NoteSubToolbar(onSave: commitNote),
                    if (activeNoteAnnotation.value != null)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: closeActiveNote,
                        ),
                      ),
                    if (activeNoteAnnotation.value != null)
                      NoteSubToolbar(
                        initialText: () {
                          final a = activeNoteAnnotation.value!;
                          if (a.contents is String) return a.contents as String;
                          if (a.contents is Map && (a.contents as Map)['text'] is String) {
                            return (a.contents as Map)['text'] as String;
                          }
                          return a.annotatedWords;
                        }(),
                        isEditing: isEditingNote.value,
                        onEditModeToggle: () {
                          isEditingNote.value = true;
                        },
                        onSave: (newText) async {
                          final card = flatItems[index].card;
                          if (card != null && newText.trim().isNotEmpty) {
                            await widgetRef.read(reviewCardRepositoryDriftProvider).updateAnnotation(
                                  cardId: card.id,
                                  annotationId: activeNoteAnnotation.value!.id,
                                  contents: newText.trim(),
                                );
                            widgetRef.read(lectureControllerProvider.notifier).pushOutboxNow();
                          }
                          closeActiveNote();
                        },
                        onDelete: () async {
                          final card = flatItems[index].card;
                          if (card != null) {
                            await widgetRef.read(reviewCardRepositoryDriftProvider).removeAnnotation(
                                  cardId: card.id,
                                  annotationId: activeNoteAnnotation.value!.id,
                                );
                            widgetRef.read(lectureControllerProvider.notifier).pushOutboxNow();
                          }
                          closeActiveNote();
                        },
                      ),
                  ],
                ),
              ),

              // ── Bottom nav hint ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chevron_left,
                      color: AppColors.paper.textPencil,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Tap left / right  •  Swipe to change topic',
                      style: TextStyle(
                        color: AppColors.paper.textPencil,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      color: AppColors.paper.textPencil,
                      size: 20,
                    ),
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
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
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
                          icon: Icon(
                            Icons.close,
                            color: AppColors.paper.textInk,
                          ),
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
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (context, tileIdx) {
                                  if (tileIdx == 0) {
                                    return GestureDetector(
                                      onTap: () {
                                        Navigator.pop(context);
                                        navigateTo(groupStart);
                                      },
                                      child: SizedBox(
                                        width: 115,
                                        child: _CoverCardTile(
                                          title: group.title,
                                          imageFile: imageFile,
                                        ),
                                      ),
                                    );
                                  }
                                  final card = group.cards[tileIdx - 1];
                                  final preview =
                                      card.title?.trim().isNotEmpty == true
                                      ? card.title!.trim()
                                      : plainTextPreview(
                                          card.cardContent.isNotEmpty
                                              ? (card.cardContent.first.text ??
                                                    '')
                                              : '',
                                        );
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
                                            Color.lerp(
                                              AppColors.paper.surface,
                                              themeColor,
                                              0.1,
                                            )!,
                                            AppColors.paper.surface,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.black.withValues(
                                            alpha: 0.07,
                                          ),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.03,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          if (card.heroEmoji
                                                  ?.trim()
                                                  .isNotEmpty ==
                                              true) ...[
                                            Text(
                                              card.heroEmoji!.trim(),
                                              style: const TextStyle(
                                                fontSize: 26,
                                              ),
                                            ),
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

    return SelectionContainer.disabled(
      child: ClipRRect(
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
    this.selectionListenerNotifier,
    this.temporaryHighlight,
    this.temporaryHighlightBlockIdx,
    this.onAnnotationTap,
  });

  final ReviewCard card;
  final File? imageFile;
  final Color themeColor;
  final SelectionListenerNotifier? selectionListenerNotifier;
  final Annotation? temporaryHighlight;
  final int? temporaryHighlightBlockIdx;
  final ValueChanged<Annotation>? onAnnotationTap;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageFile != null;

    final blocks = Column(
      children: card.cardContent.asMap().entries.map(
        (entry) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ReviewCardBlockView(
            block: entry.value,
            themeColor: themeColor,
            annotations: [
              ...card.annotations.where((a) => a.blockIdx == entry.key),
              if (temporaryHighlight != null && temporaryHighlightBlockIdx == entry.key)
                temporaryHighlight!,
            ],
            onAnnotationTap: onAnnotationTap,
          ),
        ),
      ).toList(),
    );

    final content = SingleChildScrollView(
      padding: EdgeInsets.all(hasImage ? 20 : 28),
      child: Column(
        children: [
          SelectionContainer.disabled(
            child: Text(
              card.heroEmoji?.trim().isNotEmpty == true
                  ? card.heroEmoji!.trim()
                  : '💡',
              style: const TextStyle(fontSize: 56),
            ),
          ),
          const SizedBox(height: 24),
          if (card.title?.trim().isNotEmpty == true) ...[
            SelectionContainer.disabled(
              child: Text(
                card.title!.trim(),
                style: TextStyle(
                  color: AppColors.paper.textInk,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (selectionListenerNotifier != null)
            SelectionListener(selectionNotifier: selectionListenerNotifier!, child: blocks)
          else
            blocks,
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
        image: DecorationImage(image: FileImage(imageFile!), fit: BoxFit.cover),
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
  const _ReviewCardBlockView({
    required this.block,
    required this.themeColor,
    this.annotations = const [],
    this.onAnnotationTap,
  });

  final ReviewCardBlock block;
  final Color themeColor;
  final List<Annotation> annotations;
  final ValueChanged<Annotation>? onAnnotationTap;

  MarkdownStyleSheet _styleSheet(BuildContext context, {bool italic = false}) {
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
        fontFamily: 'monospace',
        backgroundColor: Colors.transparent,
      ),
      listBullet: style.copyWith(color: themeColor),
      textAlign: WrapAlignment.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    final builders = annotationMarkdownBuilders(
      MarkdownAnnotationBuilder(
        annotations: annotations,
        onAnnotationTap: onAnnotationTap,
      ),
    );
    final annotationsKey = ValueKey(annotationsCacheKey(annotations));
    switch (block.type) {
      case 'quote':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: themeColor, width: 3)),
          ),
          child: MarkdownBody(
            key: annotationsKey,
            data: stripSidCitations(block.text ?? ''),
            builders: builders,
            styleSheet: _styleSheet(
              context,
              italic: true,
            ).copyWith(textAlign: WrapAlignment.start),
          ),
        );
      case 'list':
        final items = block.items ?? const <String>[];
        final markdown = items
            .map((item) => '- ${stripSidCitations(item)}')
            .join('\n');
        return MarkdownBody(
          key: annotationsKey,
          data: markdown,
          builders: builders,
          bulletBuilder: annotationBulletBuilder(
            _styleSheet(context).listBullet,
          ),
          styleSheet: _styleSheet(
            context,
          ).copyWith(textAlign: WrapAlignment.start),
        );
      case 'paragraph':
      default:
        return MarkdownBody(
          key: annotationsKey,
          data: stripSidCitations(block.text ?? ''),
          builders: builders,
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
    return SelectionContainer.disabled(
      child: ClipRRect(
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
      ),
    );
  }
}
