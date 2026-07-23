// lib/presentation/widgets/announcement_transcript_modal.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';

import 'package:lecture_companion_ui/application/lecture/lecture_providers.dart';
import 'package:lecture_companion_ui/application/lecture_viewer/lecture_viewer_data_provider.dart';
import 'package:lecture_companion_ui/application/recording/lecture_moments_provider.dart';
import 'package:lecture_companion_ui/core/utils/moment_display_utils.dart';
import 'package:lecture_companion_ui/core/utils/sid_citation.dart';
import 'package:lecture_companion_ui/core/utils/topic_color_utils.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_moment.dart';
import 'package:lecture_companion_ui/domain/entities/lecture_topic.dart';
import 'package:lecture_companion_ui/infrastructure/repositories/lecture_artifact_repository.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/presentation/pages/transcript/transcript_page.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/audio_player_bar.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_scrollbar.dart';

// ── トップレベルの表示用ヘルパー関数 ───────────────────────────────
Future<void> showAnnouncementTranscriptModal(
  BuildContext context, {
  required String lectureId,
  String? courseId,
  String? startSid,
  String? endSid,
  List<String>? highlightSids,
}) {
  return AnnouncementTranscriptModal.show(
    context,
    lectureId: lectureId,
    courseId: courseId,
    startSid: startSid,
    endSid: endSid,
    highlightSids: highlightSids,
  );
}

// SIDを整数に変換するユーティリティ (例: "s000042" -> 42)
int? _sidToInt(String? sid) {
  if (sid == null) return null;
  final match = RegExp(r'[sS](\d+)').firstMatch(sid);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

// 時間（ミリ秒）を文字列にフォーマット
String _formatMs(int ms) {
  final totalSeconds = ms ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

/// お知らせモーダル内でトランスクリプトおよび音声を再生するためのボトムシート。
class AnnouncementTranscriptModal extends HookConsumerWidget {
  const AnnouncementTranscriptModal({
    super.key,
    required this.lectureId,
    this.startSid,
    this.endSid,
    this.highlightSids,
  });

  final String lectureId;
  final String? startSid;
  final String? endSid;
  final List<String>? highlightSids;

  static Future<void> show(
    BuildContext context, {
    required String lectureId,
    String? courseId,
    String? startSid,
    String? endSid,
    List<String>? highlightSids,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AnnouncementTranscriptModal(
        lectureId: lectureId,
        startSid: startSid,
        endSid: endSid,
        highlightSids: highlightSids,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lectureAsync = ref.watch(lectureProvider(lectureId));
    final topicsAsync = ref.watch(lectureTopicsProvider(lectureId));
    final topics = topicsAsync.value ?? const <LectureTopic>[];

    final momentsAsync = ref.watch(lectureMomentsProvider(lectureId));
    final moments = momentsAsync.value ?? const <LectureMoment>[];

    final currentUserId = supabase.auth.currentUser?.id ?? '';

    final player = useMemoized(() => AudioPlayer());
    final duration = useState<Duration>(Duration.zero);
    final position = useState<Duration>(Duration.zero);
    final playerState = useState<PlayerState>(PlayerState.stopped);
    final playbackSpeed = useState<double>(1.0);
    final isAudioLoaded = useState<bool>(false);

    // Scroll & Auto-scroll setup (5s Idle Resume)
    final scrollController = useScrollController();
    final isAutoModeEnabled = useState<bool>(true);
    final isUserInteracting = useState<bool>(false);
    final idleTimer = useRef<Timer?>(null);
    final hasScrolledToHighlight = useState<bool>(false);
    final hasSeekedToHighlight = useState<bool>(false);

    useEffect(() {
      return () {
        idleTimer.value?.cancel();
      };
    }, []);

    return lectureAsync.when(
      loading: () => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: AppColors.paper.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.deepGold),
        ),
      ),
      error: (err, _) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: AppColors.paper.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Center(
          child: Text(
            'Error: $err',
            style: const TextStyle(color: AppColors.correctionRed),
          ),
        ),
      ),
      data: (lecture) {
        if (lecture == null) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: AppColors.paper.background,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: const Center(child: Text('Lecture not found')),
          );
        }

        final transcriptAsync = ref.watch(
          transcriptProvider(uid: currentUserId, lectureId: lecture.id),
        );
        final sentences = transcriptAsync.value ?? const [];

        // ── 表示アイテム配列 (独立タイル) の作成 ─────────────────────────
        final displayItems = useMemoized(() {
          final List<TranscriptDisplayItem> items = [];
          if (sentences.isEmpty && moments.isEmpty) return items;

          final Map<int, LectureTopic> startSentenceIndexToTopic = {};
          for (int tIdx = 0; tIdx < topics.length; tIdx++) {
            final topic = topics[tIdx];
            final startNum = _sidToInt(topic.startSid);
            if (startNum == null) continue;

            for (int sIdx = 0; sIdx < sentences.length; sIdx++) {
              final n = _sidToInt(sentences[sIdx].sid);
              if (n != null && n >= startNum) {
                startSentenceIndexToTopic[sIdx] = topic;
                break;
              }
            }
          }

          final Map<int, List<LectureMoment>> sentenceIndexToMoments = {};
          for (final m in moments) {
            final mMs = m.timestampSec * 1000;
            int targetSentenceIdx = 0;
            for (int sIdx = 0; sIdx < sentences.length; sIdx++) {
              if (sentences[sIdx].start <= mMs) {
                targetSentenceIdx = sIdx;
              } else {
                break;
              }
            }
            sentenceIndexToMoments.putIfAbsent(targetSentenceIdx, () => []).add(m);
          }

          for (int sIdx = 0; sIdx < sentences.length; sIdx++) {
            if (startSentenceIndexToTopic.containsKey(sIdx)) {
              final topic = startSentenceIndexToTopic[sIdx]!;
              final topicIndexInList = topics.indexOf(topic);
              final safeIdx = topicIndexInList >= 0 ? topicIndexInList : 0;
              final topicColor = TopicColorUtils.getTopicColor(
                safeIdx,
                topics.length,
              );
              final topicBgColor = TopicColorUtils.getTopicBackgroundColor(
                safeIdx,
                topics.length,
                alpha: 0.12,
              );

              items.add(TopicHeaderDisplayItem(
                topic: topic,
                color: topicColor,
                bgColor: topicBgColor,
              ));
            }

            items.add(SentenceDisplayItem(
              sentence: sentences[sIdx],
              sentenceIndex: sIdx,
            ));

            if (sentenceIndexToMoments.containsKey(sIdx)) {
              for (final m in sentenceIndexToMoments[sIdx]!) {
                items.add(MomentDisplayItem(moment: m));
              }
            }
          }

          return items;
        }, [sentences, topics, moments]);

        // トピック開始時間のミリ秒リスト
        final topicStartMsList = useMemoized(() {
          final List<int> msList = [];
          for (final topic in topics) {
            final startNum = _sidToInt(topic.startSid);
            if (startNum == null) continue;
            for (final s in sentences) {
              final n = _sidToInt(s.sid);
              if (n != null && n >= startNum) {
                msList.add(s.start);
                break;
              }
            }
          }
          return msList;
        }, [topics, sentences]);

        final activeSentenceIndex = useMemoized(() {
          final ms = position.value.inMilliseconds;
          int idx = -1;
          for (int i = 0; i < sentences.length; i++) {
            if (ms >= sentences[i].start) {
              idx = i;
            } else {
              break;
            }
          }
          return idx;
        }, [position.value, sentences]);

        final activeDisplayIndex = useMemoized(() {
          if (activeSentenceIndex < 0) return -1;
          for (int i = 0; i < displayItems.length; i++) {
            final item = displayItems[i];
            if (item is SentenceDisplayItem &&
                item.sentenceIndex == activeSentenceIndex) {
              return i;
            }
          }
          return -1;
        }, [displayItems, activeSentenceIndex]);

        final currentTopic = useMemoized(() {
          if (topics.isEmpty) return null;
          final ms = position.value.inMilliseconds;

          for (int i = 0; i < topics.length; i++) {
            final topic = topics[i];
            final startNum = _sidToInt(topic.startSid);
            final endNum = _sidToInt(topic.endSid);

            if (startNum == null) continue;

            int topicStartMs = -1;
            int topicEndMs = -1;

            for (final s in sentences) {
              final n = _sidToInt(s.sid);
              if (n != null) {
                if (n == startNum) topicStartMs = s.start;
                if (endNum != null && n == endNum) topicEndMs = s.start + 5000;
              }
            }

            if (topicStartMs < 0) continue;

            if (topicEndMs < 0) {
              if (i + 1 < topics.length) {
                final nextStartNum = _sidToInt(topics[i + 1].startSid);
                for (final s in sentences) {
                  final n = _sidToInt(s.sid);
                  if (n != null && nextStartNum != null && n >= nextStartNum) {
                    topicEndMs = s.start - 1;
                    break;
                  }
                }
              }
              if (topicEndMs < 0) {
                topicEndMs = double.maxFinite.toInt();
              }
            }

            if (ms >= topicStartMs && ms <= topicEndMs) {
              return topic;
            }
          }

          return null;
        }, [position.value, topics, sentences]);

        final startNumRaw = useMemoized(() => _sidToInt(startSid), [startSid]);
        final endNumRaw = useMemoized(() => _sidToInt(endSid), [endSid]);

        final startNum = useMemoized(() {
          if (startNumRaw == null || endNumRaw == null) return startNumRaw;
          return startNumRaw < endNumRaw ? startNumRaw : endNumRaw;
        }, [startNumRaw, endNumRaw]);

        final endNum = useMemoized(() {
          if (startNumRaw == null || endNumRaw == null) return endNumRaw;
          return startNumRaw > endNumRaw ? startNumRaw : endNumRaw;
        }, [startNumRaw, endNumRaw]);

        final sentenceNums = useMemoized(() {
          return sentences.map((s) => _sidToInt(s.sid)).toList();
        }, [sentences]);

        final highlightedIndices = useMemoized(() {
          final Set<int> result = {};
          if (highlightSids != null && highlightSids!.isNotEmpty) {
            final targetSids = highlightSids!.map((s) => _sidToInt(s)).toSet();
            for (var i = 0; i < sentenceNums.length; i++) {
              final n = sentenceNums[i];
              if (n != null && targetSids.contains(n)) {
                result.add(i);
              }
            }
          } else {
            if (startNum == null || endNum == null) return <int>{};
            for (var i = 0; i < sentenceNums.length; i++) {
              final n = sentenceNums[i];
              if (n != null && n >= startNum && n <= endNum) {
                result.add(i);
              }
            }
          }
          return result;
        }, [sentenceNums, startNum, endNum, highlightSids]);

        final firstHighlightSentenceIndex = useMemoized(() {
          if (highlightedIndices.isEmpty) return -1;
          return highlightedIndices.reduce((a, b) => a < b ? a : b);
        }, [highlightedIndices]);

        final firstHighlightDisplayIndex = useMemoized(() {
          if (firstHighlightSentenceIndex < 0) return -1;
          for (int i = 0; i < displayItems.length; i++) {
            final item = displayItems[i];
            if (item is SentenceDisplayItem &&
                item.sentenceIndex == firstHighlightSentenceIndex) {
              return i;
            }
          }
          return -1;
        }, [displayItems, firstHighlightSentenceIndex]);

        final screenWidth = MediaQuery.of(context).size.width;
        final textScaler = MediaQuery.textScalerOf(context);
        final screenHeight = MediaQuery.of(context).size.height;

        final maxTimestampText = useMemoized(() {
          if (sentences.isEmpty) return '00:00';
          return _formatMs(sentences.last.start);
        }, [sentences]);

        final rowHeights = useMemoized(
          () => computeDisplayItemHeights(
            displayItems,
            screenWidth,
            textScaler,
            maxTimestampText,
          ),
          [displayItems, screenWidth, textScaler, maxTimestampText],
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

        final syncScrollPosition = useCallback(() {
          if (scrollController.hasClients &&
              activeDisplayIndex >= 0 &&
              activeDisplayIndex < rowOffsets.length) {
            final targetOffset =
                rowOffsets[activeDisplayIndex] - (screenHeight / 3);
            final viewportHeight =
                scrollController.position.viewportDimension;
            final maxScroll = (totalContentExtent - viewportHeight).clamp(
              0.0,
              double.infinity,
            );
            final safeOffset = targetOffset.clamp(0.0, maxScroll);
            scrollController.animateTo(
              safeOffset,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        }, [activeDisplayIndex, scrollController, screenHeight, rowOffsets, totalContentExtent]);

        useEffect(() {
          if (hasScrolledToHighlight.value) return null;
          if (rowOffsets.isEmpty || firstHighlightDisplayIndex < 0) return null;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!scrollController.hasClients) return;
            final targetOffset =
                rowOffsets[firstHighlightDisplayIndex] - (screenHeight * 0.2);
            final viewportHeight =
                scrollController.position.viewportDimension;
            final maxScroll = (totalContentExtent - viewportHeight).clamp(
              0.0,
              double.infinity,
            );
            final safeOffset = targetOffset.clamp(0.0, maxScroll);

            idleTimer.value?.cancel();
            isUserInteracting.value = true;

            scrollController.animateTo(
              safeOffset,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
            );
            hasScrolledToHighlight.value = true;

            idleTimer.value = Timer(const Duration(seconds: 5), () {
              isUserInteracting.value = false;
              if (isAutoModeEnabled.value) {
                syncScrollPosition();
              }
            });
          });

          return null;
        }, [rowOffsets, firstHighlightDisplayIndex, totalContentExtent, screenHeight, syncScrollPosition]);

        final hasAudioPath =
            lecture.audioPath != null && lecture.audioPath!.isNotEmpty;
        final r2FileAsync = hasAudioPath
            ? ref.watch(artifactFileProvider(lecture.audioPath!))
            : const AsyncValue<File?>.data(null);

        useEffect(() {
          if (r2FileAsync.hasValue && r2FileAsync.value != null) {
            final file = r2FileAsync.value!;
            player
                .setReleaseMode(ReleaseMode.stop)
                .then((_) {
                  return player.setSource(DeviceFileSource(file.path));
                })
                .then((_) {
                  isAudioLoaded.value = true;
                });
          }
          return null;
        }, [r2FileAsync.value, player]);

        useEffect(() {
          if (hasSeekedToHighlight.value) return null;
          if (!isAudioLoaded.value ||
              firstHighlightSentenceIndex < 0 ||
              firstHighlightSentenceIndex >= sentences.length) {
            return null;
          }

          final startMs = sentences[firstHighlightSentenceIndex].start;
          final target = Duration(milliseconds: startMs);

          position.value = target;
          player.seek(target);

          hasSeekedToHighlight.value = true;
          return null;
        }, [isAudioLoaded.value, firstHighlightSentenceIndex, sentences, player]);

        useEffect(() {
          final dSub =
              player.onDurationChanged.listen((d) => duration.value = d);
          final pSub =
              player.onPositionChanged.listen((p) => position.value = p);
          final sSub = player.onPlayerStateChanged.listen((s) {
            playerState.value = s;
            if (s == PlayerState.completed) {
              player.stop();
              position.value = Duration.zero;
            }
          });

          return () {
            dSub.cancel();
            pSub.cancel();
            sSub.cancel();
            player.dispose();
          };
        }, [player]);

        // Autoモード ON ＆ アイドル状態の時のみ自動追従スクロールを実行
        useEffect(() {
          if (isAutoModeEnabled.value &&
              !isUserInteracting.value &&
              activeDisplayIndex >= 0 &&
              scrollController.hasClients) {
            syncScrollPosition();
          }
          return null;
        }, [activeDisplayIndex, isAutoModeEnabled.value, isUserInteracting.value, syncScrollPosition]);

        final seekToMs = useCallback((int ms) async {
          if (!isAudioLoaded.value) return;
          final target = Duration(milliseconds: ms);
          position.value = target;
          await player.seek(target);
          if (playerState.value != PlayerState.playing) {
            await player.resume();
          }
          idleTimer.value?.cancel();
          isUserInteracting.value = false;
        }, [player, isAudioLoaded.value, playerState.value]);

        final jumpToTopic = useCallback((LectureTopic topic) {
          final startNum = _sidToInt(topic.startSid);
          if (startNum == null) return;

          int matchedSentenceIdx = -1;
          for (int i = 0; i < sentences.length; i++) {
            final n = _sidToInt(sentences[i].sid);
            if (n != null && n >= startNum) {
              matchedSentenceIdx = i;
              break;
            }
          }

          if (matchedSentenceIdx >= 0) {
            if (isAudioLoaded.value) {
              seekToMs(sentences[matchedSentenceIdx].start);
            }

            int targetDisplayIdx = -1;
            for (int i = 0; i < displayItems.length; i++) {
              final item = displayItems[i];
              if (item is TopicHeaderDisplayItem && item.topic.id == topic.id) {
                targetDisplayIdx = i;
                break;
              }
            }

            if (targetDisplayIdx < 0) {
              for (int i = 0; i < displayItems.length; i++) {
                final item = displayItems[i];
                if (item is SentenceDisplayItem &&
                    item.sentenceIndex == matchedSentenceIdx) {
                  targetDisplayIdx = i;
                  break;
                }
              }
            }

            if (scrollController.hasClients &&
                targetDisplayIdx >= 0 &&
                targetDisplayIdx < rowOffsets.length) {
              final targetOffset =
                  rowOffsets[targetDisplayIdx] - (screenHeight * 0.2);
              final viewportHeight =
                  scrollController.position.viewportDimension;
              final maxScroll = (totalContentExtent - viewportHeight).clamp(
                0.0,
                double.infinity,
              );
              final safeOffset = targetOffset.clamp(0.0, maxScroll);
              
              idleTimer.value?.cancel();
              isUserInteracting.value = false;

              scrollController.animateTo(
                safeOffset,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
              );
            }
          }
        }, [sentences, displayItems, isAudioLoaded.value, seekToMs, scrollController, rowOffsets, screenHeight, totalContentExtent]);

        final handlePreviousTopic = useCallback(() {
          if (topics.isEmpty) return;
          final currentMs = position.value.inMilliseconds;

          if (topicStartMsList.isEmpty) return;

          int currentTopicIdx = -1;
          for (int i = 0; i < topicStartMsList.length; i++) {
            if (currentMs >= topicStartMsList[i]) {
              currentTopicIdx = i;
            } else {
              break;
            }
          }

          if (currentTopicIdx < 0) {
            jumpToTopic(topics.first);
            return;
          }

          final topicStartMs = topicStartMsList[currentTopicIdx];
          final elapsedSinceTopicStart = currentMs - topicStartMs;

          if (elapsedSinceTopicStart >= 3000) {
            jumpToTopic(topics[currentTopicIdx]);
          } else {
            if (currentTopicIdx > 0) {
              jumpToTopic(topics[currentTopicIdx - 1]);
            } else {
              jumpToTopic(topics.first);
            }
          }
        }, [topics, topicStartMsList, position.value, jumpToTopic]);

        final handleNextTopic = useCallback(() {
          if (topics.isEmpty) return;
          final currentMs = position.value.inMilliseconds;

          int nextTopicIdx = -1;
          for (int i = 0; i < topicStartMsList.length; i++) {
            if (topicStartMsList[i] > currentMs + 500) {
              nextTopicIdx = i;
              break;
            }
          }

          if (nextTopicIdx >= 0 && nextTopicIdx < topics.length) {
            jumpToTopic(topics[nextTopicIdx]);
          }
        }, [topics, topicStartMsList, position.value, jumpToTopic]);

        final topicProgresses = useMemoized(() {
          final totalMs = duration.value.inMilliseconds;
          if (totalMs <= 0 || topicStartMsList.isEmpty) return <double>[];
          return topicStartMsList.map((ms) => ms / totalMs).toList();
        }, [duration.value, topicStartMsList]);

        final topicRanges = useMemoized(() {
          final totalMs = duration.value.inMilliseconds;
          if (totalMs <= 0 || topics.isEmpty) return <TopicProgressRange>[];

          final List<TopicProgressRange> ranges = [];
          for (int i = 0; i < topics.length; i++) {
            final topic = topics[i];
            final startNum = _sidToInt(topic.startSid);
            final endNum = _sidToInt(topic.endSid);

            if (startNum == null) continue;

            int topicStartMs = -1;
            int topicEndMs = -1;

            for (final s in sentences) {
              final n = _sidToInt(s.sid);
              if (n != null) {
                if (n == startNum) topicStartMs = s.start;
                if (endNum != null && n == endNum) topicEndMs = s.start + 5000;
              }
            }

            if (topicStartMs < 0) continue;

            if (topicEndMs < 0) {
              if (i + 1 < topics.length) {
                final nextStartNum = _sidToInt(topics[i + 1].startSid);
                for (final s in sentences) {
                  final n = _sidToInt(s.sid);
                  if (n != null && nextStartNum != null && n >= nextStartNum) {
                    topicEndMs = s.start - 1;
                    break;
                  }
                }
              }
              if (topicEndMs < 0) {
                topicEndMs = totalMs;
              }
            }

            final double startRatio = (topicStartMs / totalMs).clamp(0.0, 1.0);
            final double endRatio = (topicEndMs / totalMs).clamp(0.0, 1.0);

            if (endRatio > startRatio) {
              ranges.add(TopicProgressRange(
                startRatio: startRatio,
                endRatio: endRatio,
              ));
            }
          }
          return ranges;
        }, [duration.value, topics, sentences]);

        final topicColors = useMemoized(() {
          return List.generate(
            topics.length,
            (i) => TopicColorUtils.getTopicColor(i, topics.length),
          );
        }, [topics]);

        final isPlaying = playerState.value == PlayerState.playing;

        final displayTitle =
            lecture.title ?? lecture.titleGenerated ?? 'Lecture';
        final displayDate =
            lecture.lectureDatetime.toIso8601String().split('T').first;

        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: AppColors.paper.background,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // ドラッグハンドル
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.paper.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),

              // ヘッダー領域
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayTitle,
                            style: TextStyle(
                              color: AppColors.paper.textInk,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            displayDate,
                            style: TextStyle(
                              color: AppColors.paper.textPencil,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasAudioPath)
                      IconButton(
                        icon: Icon(
                          isAutoModeEnabled.value
                              ? Icons.sync
                              : Icons.sync_disabled,
                          color: isAutoModeEnabled.value
                              ? AppColors.deepGold
                              : AppColors.paper.textPencil,
                        ),
                        tooltip: isAutoModeEnabled.value
                            ? 'Auto-scroll Mode (5s Resume)'
                            : 'Auto-scroll Disabled (OFF)',
                        onPressed: () {
                          isAutoModeEnabled.value = !isAutoModeEnabled.value;
                          if (isAutoModeEnabled.value) {
                            idleTimer.value?.cancel();
                            isUserInteracting.value = false;
                            syncScrollPosition();
                          } else {
                            idleTimer.value?.cancel();
                          }
                        },
                      ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: AppColors.paper.textPencil,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // ── トランスクリプトリスト ─────────────────────────────
              Expanded(
                child: transcriptAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.deepGold),
                  ),
                  error: (err, _) => Center(
                    child: Text(
                      err is ArtifactOfflineException
                          ? "You're offline. Transcript will load once you're back online."
                          : 'Transcript unavailable: $err',
                      style: TextStyle(color: AppColors.paper.textPencil),
                    ),
                  ),
                  data: (sentencesData) {
                    if (sentencesData == null || sentencesData.isEmpty) {
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

                    return NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (!isAutoModeEnabled.value) return false;

                        if (notification is ScrollStartNotification &&
                            notification.dragDetails != null) {
                          idleTimer.value?.cancel();
                          isUserInteracting.value = true;
                        } else if (notification is ScrollUpdateNotification &&
                            notification.dragDetails != null) {
                          idleTimer.value?.cancel();
                          isUserInteracting.value = true;
                        } else if (notification is ScrollEndNotification) {
                          if (isUserInteracting.value) {
                            idleTimer.value?.cancel();
                            idleTimer.value = Timer(const Duration(seconds: 5), () {
                              isUserInteracting.value = false;
                              if (isAutoModeEnabled.value) {
                                syncScrollPosition();
                              }
                            });
                          }
                        }
                        return false;
                      },
                      child: CustomScrollbar(
                        controller: scrollController,
                        totalExtent: totalContentExtent,
                        child: ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: kHorizontalPagePadding,
                            vertical: kListVerticalPadding,
                          ),
                          itemCount: displayItems.length,
                          itemExtentBuilder: (index, dimensions) =>
                              rowHeights[index],
                          itemBuilder: (context, idx) {
                            final item = displayItems[idx];

                            // ── A. 独立トピックヘッダータイルの描画 ───────────────
                            if (item is TopicHeaderDisplayItem) {
                              return Container(
                                margin: const EdgeInsets.only(
                                  top: 10,
                                  bottom: 4,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: item.bgColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: item.color.withValues(alpha: 0.35),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 3.5,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: item.color,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Topic ${item.topic.index}',
                                      style: TextStyle(
                                        color: item.color,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item.topic.displayTitle,
                                        style: TextStyle(
                                          color: AppColors.paper.textInk,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            // ── B. インラインモーメントタイルの描画 ──────────────
                            if (item is MomentDisplayItem) {
                              final m = item.moment;
                              final (icon, color, label) =
                                  MomentDisplayUtils.getMomentDisplay(
                                m.momentType,
                              );
                              final isNoteWithText =
                                  m.momentType == 'note' &&
                                  m.noteText != null &&
                                  m.noteText!.trim().isNotEmpty;

                              if (isNoteWithText) {
                                return Container(
                                  margin: const EdgeInsets.only(
                                    top: 6,
                                    bottom: 4,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: color.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(icon, size: 18, color: color),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          m.noteText!,
                                          style: TextStyle(
                                            color: AppColors.paper.textInk,
                                            fontSize: 13,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              } else {
                                return Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.only(
                                      top: 6,
                                      bottom: 4,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: color.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(icon, size: 15, color: color),
                                        const SizedBox(width: 6),
                                        Text(
                                          label,
                                          style: TextStyle(
                                            color: color,
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

                            // ── C. 文章タイルの描画 ─────────────────────────────
                            final sentenceItem = item as SentenceDisplayItem;
                            final s = sentenceItem.sentence;
                            final sIdx = sentenceItem.sentenceIndex;

                            final roleUpper = s.role.toUpperCase();
                            final isItalic = roleUpper == 'OFF_TOPIC';
                            final displayColor = isItalic
                                ? AppColors.paper.textPencil
                                : AppColors.paper.textInk;

                            final isPlayingActive = sIdx == activeSentenceIndex;
                            final isRangeHighlighted =
                                highlightedIndices.contains(sIdx);
                            final isHighlighted =
                                isPlayingActive || isRangeHighlighted;

                            BoxDecoration? itemDecoration;
                            if (isHighlighted) {
                              final bgColor = AppColors.deepGold.withValues(
                                alpha: 0.12,
                              );

                              if (isPlayingActive) {
                                itemDecoration = BoxDecoration(
                                  color: bgColor,
                                  border: Border.all(
                                    color: AppColors.deepGold.withValues(
                                      alpha: 0.4,
                                    ),
                                    width: 1.2,
                                  ),
                                );
                              } else if (isRangeHighlighted) {
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
                              } else {
                                itemDecoration =
                                    BoxDecoration(color: bgColor);
                              }
                            }

                            final displayWeight = isPlayingActive
                                ? FontWeight.bold
                                : FontWeight.normal;

                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              decoration: itemDecoration,
                              margin: EdgeInsets.zero,
                              child: InkWell(
                                onTap: isAudioLoaded.value
                                    ? () => seekToMs(s.start)
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: kRowVerticalPadding,
                                    horizontal: kRowHorizontalPadding,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // タイムスタンプ
                                      Text(
                                        _formatMs(s.start),
                                        style: kTimestampTextStyle.copyWith(
                                          color: AppColors.deepGold,
                                          decoration: isAudioLoaded.value
                                              ? TextDecoration.underline
                                              : TextDecoration.none,
                                        ),
                                      ),
                                      const SizedBox(width: kTimestampGap),
                                      // 本文
                                      Expanded(
                                        child: Text(
                                          stripSidCitations(s.text),
                                          style: kSentenceTextStyle.copyWith(
                                            color: displayColor,
                                            fontWeight: displayWeight,
                                            fontStyle:
                                                isItalic && !isPlayingActive
                                                    ? FontStyle.italic
                                                    : FontStyle.normal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),

              // ── Audio Player UI ────────────────────────────────────
              if (hasAudioPath)
                AudioPlayerBar(
                  position: position.value,
                  duration: duration.value,
                  isPlaying: isPlaying,
                  playbackSpeed: playbackSpeed.value,
                  isAudioLoaded: isAudioLoaded.value,
                  isLoading: r2FileAsync.isLoading,
                  errorMessage: r2FileAsync.hasError
                      ? (r2FileAsync.error is ArtifactOfflineException
                          ? "You're offline"
                          : r2FileAsync.error.toString())
                      : null,
                  topics: topics,
                  currentTopic: currentTopic,
                  moments: moments,
                  topicProgresses: topicProgresses,
                  topicRanges: topicRanges,
                  topicColors: topicColors,
                  onPreviousTopic: handlePreviousTopic,
                  onNextTopic: handleNextTopic,
                  onTopicSelected: jumpToTopic,
                  onPlayPause: () async {
                    if (isPlaying) {
                      await player.pause();
                    } else {
                      await player.resume();
                    }
                  },
                  onSeek: (value) async {
                    position.value = value;
                    await player.seek(value);
                  },
                  onRewind10: () async {
                    final target = position.value - const Duration(seconds: 10);
                    final actualTarget =
                        target < Duration.zero ? Duration.zero : target;
                    position.value = actualTarget;
                    await player.seek(actualTarget);
                  },
                  onForward10: () async {
                    final target = position.value + const Duration(seconds: 10);
                    final actualTarget = target > duration.value
                        ? duration.value
                        : target;
                    position.value = actualTarget;
                    await player.seek(actualTarget);
                  },
                  onChangeSpeed: () async {
                    double nextSpeed = 1.0;
                    if (playbackSpeed.value == 1.0) {
                      nextSpeed = 1.25;
                    } else if (playbackSpeed.value == 1.25) {
                      nextSpeed = 1.5;
                    } else if (playbackSpeed.value == 1.5) {
                      nextSpeed = 2.0;
                    } else {
                      nextSpeed = 1.0;
                    }
                    playbackSpeed.value = nextSpeed;
                    await player.setPlaybackRate(nextSpeed);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
