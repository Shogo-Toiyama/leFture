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
import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_topic.dart';
import 'package:lecture_companion_ui/domain/entities/deep_note.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/repositories/deep_note_repository_drift.dart';
import 'package:lecture_companion_ui/core/utils/annotation_text_utils.dart';
import 'package:lecture_companion_ui/core/utils/sid_citation.dart';
import 'package:lecture_companion_ui/presentation/pages/course/widgets/course_style_helper.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_scrollbar.dart';
import 'package:lecture_companion_ui/presentation/widgets/card_selection_toolbar.dart';
import 'package:lecture_companion_ui/presentation/widgets/highlight_sub_toolbar.dart';
import 'package:lecture_companion_ui/presentation/widgets/markdown_annotation_builder.dart';
import 'package:lecture_companion_ui/presentation/widgets/note_sub_toolbar.dart';
import 'package:lecture_companion_ui/presentation/widgets/announcement_transcript_modal.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_data.dart';
import 'package:lecture_companion_ui/domain/entities/annotation.dart';
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
          annotations: note?.annotations ?? const [],
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
    // 現在選択されているプレーンテキスト。Highlight/Note確定時に、ノート本文の
    // どの範囲かを逆引きするために使う。
    final selectedText = useState<String?>(null);
    // Review Cardsと同様、ノートが切り替わるたびに作り直してSelectableRegionの
    // 内部状態をリセットする(save後のclearSelection()にも使う)。
    final selectionAreaKey = useMemoized(
      () => GlobalKey<SelectionAreaState>(),
      [currentIndex.value],
    );
    // ノート本文(MarkdownBody)専用のSelectionListener。SelectableRegionは
    // 選択範囲の絶対文字位置(SelectedContentRange)を公開するpublicなAPIを
    // 持たないため、範囲を正確に取得するにはこれ経由で取得する必要がある。
    final selectionListenerNotifier = useMemoized(
      () => SelectionListenerNotifier(),
      [currentIndex.value],
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
    final temporaryHighlight = useState<Annotation?>(null);
    final activeNoteAnnotation = useState<Annotation?>(null);
    final isEditingNote = useState<bool>(false);
    // ノートを切り替えたら、開いたままのサブツールバーとキャッシュ済み選択範囲を
    // 破棄する。NoteSubToolbarはノート切り替え後も選択解除だけでは閉じなく
    // なったため、切り替え自体をトリガーに明示的に閉じる必要がある(放置すると
    // 別ノート宛のcachedNoteLocationで保存してしまう)。
    useEffect(() {
      highlightToolbarOpen.value = false;
      noteToolbarOpen.value = false;
      cachedNoteLocation.value = null;
      temporaryHighlight.value = null;
      activeNoteAnnotation.value = null;
      isEditingNote.value = false;
      return null;
    }, [currentIndex.value]);
    // 注: テキスト選択ハンドルはFlutter内部で常にOverlayの一番上に新規追加される
    // ため(SelectionOverlay.showHandles)、OverlayPortal経由でサブツールバーを
    // 前面に出す手段は無い(ホストのOverlayEntryスロット固定で、show()呼び出し
    // 順は無関係)。ハンドルとサブツールバーが重なることは許容する。

    // topicsAsync/notesAsyncはDrift(ローカルDB)のStreamベースのプロバイダなので、
    // ハイライト保存などのDB書き込みのたびにresolvedTopicsは新しいリスト参照として
    // 再生成される。この初期化は「まだデータが無くて0件だった状態から、
    // ルートのtopicIndexが指すページを初めて表示する」ための一度きりの処理であり、
    // 以降のDB更新のたびにユーザーがNext/Prevでローカルに移動したページ位置を
    // 巻き戻してしまわないよう、一度同期したら二度と実行しないようにする。
    final hasSyncedInitialIndex = useRef(false);
    useEffect(() {
      if (!hasSyncedInitialIndex.value && resolvedTopics.isNotEmpty) {
        currentIndex.value = topicIndex.clamp(0, resolvedTopics.length - 1);
        hasSyncedInitialIndex.value = true;
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
                _buildAppBar(context, ref, 'Deep Notes', currentIndex.value, 0, () => _showNotesListSheet(context, resolvedTopics, currentIndex, navigationDirection, textThemeColor), hasSelection.value, textThemeColor, null, false, () {}, false, () {}, null, null),
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

    // 現在選択中の範囲が、ノート本文の何文字目〜何文字目にあたるかを求める。
    TextLocation? locateSelection() {
      if (!selectionListenerNotifier.registered) return null;
      final range = selectionListenerNotifier.selection.range;
      if (range == null) return null;
      return locateFromNoteRange(range);
    }

    Future<void> commitHighlight(String mode) async {
      final noteId = topic.noteId;
      final located = locateSelection();
      if (noteId == null || located == null) return;
      final repo = ref.read(deepNoteRepositoryDriftProvider);
      if (mode == 'eraser') {
        await repo.eraseHighlightRange(
          noteId: noteId,
          startIdx: located.startIdx,
          endIdx: located.endIdx,
          noteText: flattenMarkdownText(stripSidCitations(topic.content)),
        );
      } else {
        await repo.addAnnotation(
          noteId: noteId,
          startIdx: located.startIdx,
          endIdx: located.endIdx,
          annotationType: 'highlight',
          annotatedWords: selectedText.value!,
          contents: {'type': mode, 'color': colorToHex(highlightColor.value)},
        );
      }
      ref.read(lectureControllerProvider.notifier).pushOutboxNow();
      selectionAreaKey.currentState?.selectableRegion.clearSelection();
      highlightToolbarOpen.value = false;
    }

    Future<void> commitNote(String text) async {
      final noteId = topic.noteId;
      // TextFieldにフォーカスが移った時点で選択は解除済みのため、Noteツールバーを
      // 開いた時点でキャッシュしておいた選択範囲を使う(locateSelection()の
      // 生の値はこの時点では既にnullになっている)。
      final located = cachedNoteLocation.value;
      if (noteId == null || located == null || text.trim().isEmpty) return;
      await ref.read(deepNoteRepositoryDriftProvider).addAnnotation(
            noteId: noteId,
            startIdx: located.startIdx,
            endIdx: located.endIdx,
            annotationType: 'notes',
            annotatedWords: selectedText.value!,
            contents: text.trim(),
          );
      ref.read(lectureControllerProvider.notifier).pushOutboxNow();
      selectionAreaKey.currentState?.selectableRegion.clearSelection();
      noteToolbarOpen.value = false;
      cachedNoteLocation.value = null;
      temporaryHighlight.value = null;
    }

    // ノート編集をキャンセルする(保存せずに閉じる)。外側タップ時に呼ばれる。
    void cancelNote() {
      if (!noteToolbarOpen.value) return;
      noteToolbarOpen.value = false;
      cachedNoteLocation.value = null;
      temporaryHighlight.value = null;
      selectionAreaKey.currentState?.selectableRegion.clearSelection();
    }

    void closeActiveNote() {
      activeNoteAnnotation.value = null;
      isEditingNote.value = false;
      temporaryHighlight.value = null;
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
              _buildAppBar(
                context,
                ref,
                topic.title,
                currentIndex.value,
                totalTopics,
                () => _showNotesListSheet(context, resolvedTopics, currentIndex, navigationDirection, textThemeColor),
                hasSelection.value,
                textThemeColor,
                topic,
                highlightToolbarOpen.value,
                () {
                  highlightToolbarOpen.value = !highlightToolbarOpen.value;
                  if (highlightToolbarOpen.value) cancelNote();
                },
                noteToolbarOpen.value,
                () {
                  if (noteToolbarOpen.value) {
                    // 既に開いている場合の再タップはキャンセル扱い(保存しない)。
                    cancelNote();
                    return;
                  }
                  // 開く瞬間の選択範囲をキャッシュする。TextFieldにフォーカスが
                  // 移った後は選択が解除されており、この時点でしか読み取れない。
                  final located = locateSelection();
                  if (located == null) return;
                  cachedNoteLocation.value = located;
                  highlightToolbarOpen.value = false;
                  noteToolbarOpen.value = true;

                  // 選択をダミーでハイライトしたまま維持する(Source機能と同じ
                  // パターン)。clearSelection()と同じフレーム内でMarkdownBodyの
                  // Keyを変えるとSelectionAreaが再入アサーションを起こすことが
                  // あるため、次フレームまで遅延させる。
                  selectionAreaKey.currentState?.selectableRegion.clearSelection();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    temporaryHighlight.value = Annotation(
                      id: '-1',
                      startIdx: located.startIdx,
                      endIdx: located.endIdx,
                      annotationType: 'highlight',
                      annotatedWords: '',
                      contents: const {'type': 'marker', 'color': '#FFE082'},
                    );
                  });
                },
                () async {
                  final located = locateSelection();
                  if (located == null) return;

                  try {
                    final rawText = topic.content;

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
                        final sentences = await ref.read(transcriptProvider(uid: uid, lectureId: lectureId).future);
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

                          debugPrint("=== Source Navigation Debug Log (Deep Note) ===");
                          debugPrint("1. Selected Text: '${selectedText.value}'");
                          debugPrint("2. Text until citation: '$textUntilCitation'");
                          debugPrint("3. Resolved SID: '$targetSid'");
                          debugPrint("4. Transcript Sentence: '${targetSentence?.text}'");
                          debugPrint("===============================================");
                        }
                      } catch (e) {
                        debugPrint("Failed to output debug log: $e");
                      }
                    }

                    // 選択状態をクリア
                    selectionAreaKey.currentState?.selectableRegion.clearSelection();

                    // 一時的ハイライトを設定 (メモリ内アノテーション)
                    // NOTE: この代入はMarkdownBodyのKeyを変え、選択中のSelectableを
                    // 即座に破棄・再生成させる。clearSelection()が同一フレーム内で
                    // ScrollableのSelection状態をリセットし切る前にこれを行うと、
                    // SelectionAreaがScrollable内で '_selectionStartsInScrollable'
                    // の再入アサーションを起こすことがあるため、次フレームまで遅延させる。
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      temporaryHighlight.value = Annotation(
                        id: '-1', // Dummy ID
                        startIdx: result.startIdx,
                        endIdx: result.endIdx,
                        annotationType: 'highlight',
                        annotatedWords: '',
                        contents: const {'type': 'marker', 'color': '#FFE082'}, // 琥珀色のマーカー
                      );
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
                    });

                  } on SelectionTooBroadException catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.message)),
                    );
                  }
                },
                () async {
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
              ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _NoteDetailContent(
                  topic: topic,
                  topicIndex: currentIndex.value,
                  totalTopics: totalTopics,
                  arrivalDirection: navigationDirection.value,
                  textThemeColor: textThemeColor,
                  selectionAreaKey: selectionAreaKey,
                  selectionListenerNotifier: selectionListenerNotifier,
                  onSelectionChanged: (text) {
                    hasSelection.value = text != null;
                    if (text != null) {
                      selectedText.value = text;
                    } else {
                      highlightToolbarOpen.value = false;
                      // NoteSubToolbar内のTextFieldにフォーカスが移る際にも
                      // ここを通るが、Noteツールバーは選択解除では閉じない
                      // (保存/再タップで明示的に閉じるまで開いたままにする)。
                    }
                  },
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
                  temporaryHighlight: temporaryHighlight.value,
                  onAnnotationTap: (a) {
                    if (a.annotationType == 'notes') {
                      cancelNote();
                      activeNoteAnnotation.value = a;
                      isEditingNote.value = false;
                      temporaryHighlight.value = a;
                    }
                  },
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
                          final noteId = topic.noteId;
                          if (noteId != null && newText.trim().isNotEmpty) {
                            await ref.read(deepNoteRepositoryDriftProvider).updateAnnotation(
                                  noteId: noteId,
                                  annotationId: activeNoteAnnotation.value!.id,
                                  contents: newText.trim(),
                                );
                            ref.read(lectureControllerProvider.notifier).pushOutboxNow();
                          }
                          closeActiveNote();
                        },
                        onDelete: () async {
                          final noteId = topic.noteId;
                          if (noteId != null) {
                            await ref.read(deepNoteRepositoryDriftProvider).removeAnnotation(
                                  noteId: noteId,
                                  annotationId: activeNoteAnnotation.value!.id,
                                );
                            ref.read(lectureControllerProvider.notifier).pushOutboxNow();
                          }
                          closeActiveNote();
                        },
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
    bool highlightToolbarOpen,
    VoidCallback onHighlightTap,
    bool noteToolbarOpen,
    VoidCallback onNoteTap,
    VoidCallback? onSourceTap,
    VoidCallback? onCopyTap,
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
                  isHighlightActive: highlightToolbarOpen,
                  onHighlightTap: onHighlightTap,
                  isNoteActive: noteToolbarOpen,
                  onNoteTap: onNoteTap,
                  onSourceTap: onSourceTap,
                  onCopyTap: onCopyTap,
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

// SelectableRegionは選択範囲の絶対文字位置(SelectedContentRange)を公開する
// publicなAPIを持たないため、正確な範囲取得にはSelectionListenerが必要。
Widget _maybeWrapWithSelectionListener(
  SelectionListenerNotifier? notifier,
  Widget child,
) {
  if (notifier == null) return child;
  return SelectionListener(selectionNotifier: notifier, child: child);
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
    this.selectionAreaKey,
    this.selectionListenerNotifier,
    this.temporaryHighlight,
    this.onAnnotationTap,
  });

  final DeepNoteTopic topic;
  final int topicIndex;
  final int totalTopics;
  final int arrivalDirection;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final Color textThemeColor;
  final ValueChanged<String?> onSelectionChanged;
  final GlobalKey<SelectionAreaState>? selectionAreaKey;
  final SelectionListenerNotifier? selectionListenerNotifier;
  final Annotation? temporaryHighlight;
  final ValueChanged<Annotation>? onAnnotationTap;

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
        key: selectionAreaKey,
        contextMenuBuilder: (context, selectableRegionState) =>
            const SizedBox.shrink(),
        onSelectionChanged: (content) => onSelectionChanged(
          content != null && content.plainText.isNotEmpty ? content.plainText : null,
        ),
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
                SelectionContainer.disabled(
                  child: Text(
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
                ),

                // ── Summary ────────────────────────────────────────────────
                if (topic.summary.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SelectionContainer.disabled(
                    child: MarkdownBody(
                      data: stripSidCitations(topic.summary),
                      selectable: false,
                      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                        p: TextStyle(
                          color: AppColors.paper.textPencil,
                          fontSize: 15,
                          fontStyle: FontStyle.italic,
                        ),
                        strong: TextStyle(
                          color: AppColors.paper.textPencil,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // ── Markdown content ───────────────────────────────────────
                _maybeWrapWithSelectionListener(
                  selectionListenerNotifier,
                  MarkdownBody(
                  key: ValueKey(annotationsCacheKey([
                    ...topic.annotations,
                    if (temporaryHighlight != null) temporaryHighlight!,
                  ])),
                  data: topic.content.isNotEmpty
                      ? stripSidCitations(topic.content)
                      : 'Deep notes for this topic are still being generated…',
                  selectable: false,
                  builders: topic.content.isNotEmpty
                      ? annotationMarkdownBuilders(
                          MarkdownAnnotationBuilder(
                            annotations: [
                              ...topic.annotations,
                              if (temporaryHighlight != null) temporaryHighlight!,
                            ],
                            onAnnotationTap: onAnnotationTap,
                          ),
                        )
                      : const {},
                  bulletBuilder: annotationBulletBuilder(
                    TextStyle(color: textThemeColor, fontSize: 16),
                  ),
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
