// lib/presentation/widgets/announcement_transcript_modal.dart
//
// アナウンスのstart_sid〜end_sidの範囲をハイライトしたトランスクリプトを
// ポップアップモーダルで表示するウィジェット。
// TranscriptPageと同じスタイルを共有する。

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lecture_companion_ui/application/lecture/lecture_providers.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/core/utils/sid_citation.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_data.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/presentation/pages/transcript/transcript_page.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_scrollbar.dart';

// SIDを整数に変換するユーティリティ (例: "s000042" -> 42)
int? _sidToInt(String? sid) {
  if (sid == null) return null;
  final match = RegExp(r'[sS](\d+)').firstMatch(sid);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// アナウンスに紐付いたトランスクリプトをモーダルで表示する。
///
/// [lectureId] - 対象の講義ID
/// [startSid] - ハイライト開始SID (例: "s000042")
/// [endSid]   - ハイライト終了SID (例: "s000060")
/// [courseId]  - "Go to this lecture" ボタン用のコースID
void showAnnouncementTranscriptModal(
  BuildContext context, {
  required String lectureId,
  required String? startSid,
  required String? endSid,
  required String? courseId,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (sheetContext) {
      return _AnnouncementTranscriptModal(
        lectureId: lectureId,
        startSid: startSid,
        endSid: endSid,
        courseId: courseId,
      );
    },
  );
}

class _AnnouncementTranscriptModal extends HookConsumerWidget {
  const _AnnouncementTranscriptModal({
    required this.lectureId,
    required this.startSid,
    required this.endSid,
    required this.courseId,
  });

  final String lectureId;
  final String? startSid;
  final String? endSid;
  final String? courseId;

  static String _formatMs(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = supabase.auth.currentUser?.id;
    final lectureAsync = ref.watch(lectureProvider(lectureId));
    final transcriptAsync = uid != null
        ? ref.watch(transcriptProvider(uid: uid, lectureId: lectureId))
        : const AsyncValue<List<TranscriptSentence>?>.data(null);

    final lecture = lectureAsync.asData?.value;
    final resolvedCourseId = lecture?.courseId ?? courseId;

    final scrollController = useScrollController();
    final hasScrolled = useState(false);

    final sentences = transcriptAsync.value ?? const <TranscriptSentence>[];

    // ハイライト対象のSIDインデックス範囲を計算
    final startNum = _sidToInt(startSid);
    final endNum = _sidToInt(endSid);

    // 各センテンスのSID番号を事前計算
    final sentenceNums = useMemoized(() {
      return sentences.map((s) => _sidToInt(s.sid)).toList();
    }, [sentences]);

    // ハイライト対象のインデックスセット
    final highlightedIndices = useMemoized(() {
      if (startNum == null || endNum == null) return <int>{};
      final Set<int> result = {};
      for (var i = 0; i < sentenceNums.length; i++) {
        final n = sentenceNums[i];
        if (n != null && n >= startNum && n <= endNum) {
          result.add(i);
        }
      }
      return result;
    }, [sentenceNums, startNum, endNum]);

    // 最初のハイライト行インデックス
    final firstHighlightIndex = useMemoized(() {
      if (highlightedIndices.isEmpty) return -1;
      return highlightedIndices.reduce((a, b) => a < b ? a : b);
    }, [highlightedIndices]);

    // 行の高さ計算 (TranscriptPageと同じロジック)
    final screenWidth = MediaQuery.of(context).size.width;
    final textScaler = MediaQuery.textScalerOf(context);
    final screenHeight = MediaQuery.of(context).size.height;

    final rowHeights = useMemoized(
      () => computeRowHeights(sentences, screenWidth, textScaler),
      [sentences, screenWidth, textScaler],
    );

    final rowOffsets = useMemoized(() {
      final offsets = List<double>.filled(rowHeights.length, 0);
      var cumulative = 0.0;
      for (var i = 0; i < rowHeights.length; i++) {
        offsets[i] = cumulative;
        cumulative += rowHeights[i];
      }
      return offsets;
    }, [rowHeights]);

    final totalContentExtent = useMemoized(() {
      if (rowHeights.isEmpty) return 0.0;
      final sum = rowOffsets.last + rowHeights.last;
      return sum + kListVerticalPadding * 2;
    }, [rowHeights, rowOffsets]);

    // 初回ロード時に最初のハイライト位置へ自動スクロール
    useEffect(() {
      if (hasScrolled.value) return null;
      if (rowOffsets.isEmpty || firstHighlightIndex < 0) return null;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) return;
        final targetOffset =
            rowOffsets[firstHighlightIndex] - (screenHeight * 0.25);
        final viewportHeight = scrollController.position.viewportDimension;
        final maxScroll = (totalContentExtent - viewportHeight).clamp(
          0.0,
          double.infinity,
        );
        final safeOffset = targetOffset.clamp(0.0, maxScroll);
        scrollController.animateTo(
          safeOffset,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
        hasScrolled.value = true;
      });

      return null;
    }, [rowOffsets, firstHighlightIndex]);

    final lectureName = lectureAsync.asData?.value?.title ??
        lectureAsync.asData?.value?.titleGenerated ??
        'Transcript';

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, sheetScrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.paper.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // ── ドラッグハンドル ──────────────────────────────────
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                decoration: BoxDecoration(
                  color: AppColors.paper.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // ── ヘッダー (タイトル + "Go to this lecture"ボタン) ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                child: Row(
                  children: [
                    // 閉じるボタン
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: AppColors.paper.textPencil,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    // 講義タイトル
                    Expanded(
                      child: Text(
                        lectureName,
                        style: TextStyle(
                          color: AppColors.paper.textInk,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // "Go to this lecture" ボタン
                    if (resolvedCourseId != null)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          final queryParams = <String, String>{
                            if (startSid != null) 'start_sid': startSid!,
                            if (endSid != null) 'end_sid': endSid!,
                          };
                          final uri = Uri(
                            path: '${AppRoutes.coursesRootPath}/c/$resolvedCourseId/v/$lectureId/transcript',
                            queryParameters: queryParams.isNotEmpty ? queryParams : null,
                          );
                          context.go(uri.toString());
                        },
                        icon: const Icon(
                          Icons.open_in_new,
                          size: 14,
                          color: AppColors.deepGold,
                        ),
                        label: const Text(
                          'Go to this lecture',
                          style: TextStyle(
                            color: AppColors.deepGold,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // 区切り線
              Divider(
                height: 1,
                thickness: 1,
                color: AppColors.paper.line,
              ),

              // ── トランスクリプトリスト ─────────────────────────────
              Expanded(
                child: transcriptAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.deepGold),
                  ),
                  error: (err, _) => Center(
                    child: Text(
                      'Transcript unavailable: $err',
                      style: TextStyle(color: AppColors.paper.textPencil),
                    ),
                  ),
                  data: (sentences) {
                    if (sentences == null || sentences.isEmpty) {
                      return Center(
                        child: Text(
                          'Transcript is being generated…',
                          style: TextStyle(
                            color: AppColors.paper.textPencil,
                            fontSize: 15,
                          ),
                        ),
                      );
                    }

                    return CustomScrollbar(
                      controller: scrollController,
                      totalExtent: totalContentExtent,
                      child: ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: kHorizontalPagePadding,
                          vertical: kListVerticalPadding,
                        ),
                        itemCount: sentences.length,
                        itemExtentBuilder: rowHeights.isNotEmpty
                            ? (index, dimensions) => rowHeights[index]
                            : null,
                        itemBuilder: (context, idx) {
                          final s = sentences[idx];
                          final roleUpper = s.role.toUpperCase();
                          final isItalic = roleUpper == 'INTERACTION' ||
                              roleUpper == 'OFF_TOPIC';
                          final isHighlighted = highlightedIndices.contains(idx);

                          // ハイライト装飾
                          BoxDecoration? itemDecoration;
                          if (isHighlighted) {
                            final bgColor =
                                AppColors.deepGold.withValues(alpha: 0.14);
                            itemDecoration = BoxDecoration(
                              color: bgColor,
                              border: Border(
                                left: BorderSide(
                                  color: AppColors.deepGold.withValues(
                                    alpha: 0.6,
                                  ),
                                  width: 3,
                                ),
                              ),
                            );
                          }

                          final displayColor = isHighlighted
                              ? AppColors.paper.textInk
                              : isItalic
                                  ? AppColors.paper.textPencil
                                  : AppColors.paper.textInk;

                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: itemDecoration,
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: kRowVerticalPadding,
                                horizontal: kRowHorizontalPadding,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // タイムスタンプ
                                  Text(
                                    _formatMs(s.start),
                                    style: kTimestampTextStyle.copyWith(
                                      color: isHighlighted
                                          ? AppColors.deepGold
                                          : AppColors.paper.textPencil,
                                    ),
                                  ),
                                  const SizedBox(width: kTimestampGap),
                                  // 本文
                                  Expanded(
                                    child: Text(
                                      stripSidCitations(s.text),
                                      style: kSentenceTextStyle.copyWith(
                                        color: displayColor,
                                        fontWeight: isHighlighted
                                            ? FontWeight.w500
                                            : FontWeight.normal,
                                        fontStyle: isItalic && !isHighlighted
                                            ? FontStyle.italic
                                            : FontStyle.normal,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
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
  }
}
