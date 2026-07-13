// lib/presentation/pages/transcript/transcript_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';


import 'package:lecture_companion_ui/application/lecture/lecture_providers.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_app_bar.dart';

import 'package:lecture_companion_ui/core/utils/sid_citation.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_scrollbar.dart';

// レイアウトに使う定数 (ListViewのpadding、行のpadding、テキストスタイル)。
// 行の高さの事前計算(_computeRowHeights)と、実際の行描画(itemBuilder)の
// 両方で同じ値を使い、ズレが出ないようにする。
const double _kHorizontalPagePadding = 24; // ListView自体の左右padding
const double _kListVerticalPadding = 16; // ListView自体の上下padding(片側)
const double _kRowHorizontalPadding = 8; // 各行内のPaddingの左右
const double _kTimestampGap = 16; // タイムスタンプと本文の間隔
const double _kRowVerticalPadding = 12; // 各行内のPaddingの上下(片側)
const _kSentenceTextStyle = TextStyle(fontSize: 14, height: 1.5);
const _kTimestampTextStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.bold,
);

/// 各文章行の高さを実際にWidgetを組み立てずに事前計算する。
/// 文字起こし全体は不変(録音済みの文字起こしが後から変わることはない)ので、
/// 一度だけ計算しておけば、以降はListView.builderのitemExtentBuilderに
/// そのまま渡して正確な位置・スクロール総量を保ちながら遅延描画できる。
List<double> _computeRowHeights(
  List<dynamic> sentences,
  double screenWidth,
  TextScaler textScaler,
) {
  if (sentences.isEmpty) return const [];

  // タイムスタンプ列の幅は、最後(最大)の時刻表記を基準に安全側で確保する。
  final lastMs = (sentences.last as dynamic).start as int;
  final timestampPainter = TextPainter(
    text: TextSpan(
      text: TranscriptPage._formatMs(lastMs),
      style: _kTimestampTextStyle,
    ),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();
  final timestampWidth = timestampPainter.width;

  final availableTextWidth =
      screenWidth -
      _kHorizontalPagePadding * 2 -
      _kRowHorizontalPadding * 2 -
      timestampWidth -
      _kTimestampGap;

  return sentences.map((s) {
    final text = stripSidCitations((s as dynamic).text as String);
    final painter = TextPainter(
      text: TextSpan(text: text, style: _kSentenceTextStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: availableTextWidth);
    return painter.height + _kRowVerticalPadding * 2;
  }).toList();
}

class TranscriptPage extends HookConsumerWidget {
  const TranscriptPage({super.key, required this.lectureId});

  final String lectureId;

  static String _formatMs(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  static String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lectureAsync = ref.watch(lectureProvider(lectureId));

    return lectureAsync.when(
      loading: () => Scaffold(
        backgroundColor: AppColors.paper.background,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.deepGold),
        ),
      ),
      error: (err, _) => Scaffold(
        backgroundColor: AppColors.paper.background,
        body: SafeArea(
          child: Column(
            children: [
              const CustomAppBar(
                showHomeButton: true,
                isLightBg: true,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Error loading lecture: $err',
                    style: TextStyle(color: AppColors.correctionRed),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      data: (lecture) {
        if (lecture == null) {
          return Scaffold(
            backgroundColor: AppColors.paper.background,
            body: SafeArea(
              child: Column(
                children: [
                  const CustomAppBar(
                    showHomeButton: true,
                    isLightBg: true,
                  ),
                  const Expanded(
                    child: Center(child: Text('Lecture not found')),
                  ),
                ],
              ),
            ),
          );
        }

        return _TranscriptPageContent(lecture: lecture, ref: ref);
      },
    );
  }
}

class _TranscriptPageContent extends HookConsumerWidget {
  const _TranscriptPageContent({required this.lecture, required this.ref});

  final Lecture lecture;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final transcriptAsync = ref.watch(
      transcriptProvider(uid: lecture.userId, lectureId: lecture.id),
    );

    // Audio Player setup
    final player = useMemoized(() => AudioPlayer());
    final duration = useState<Duration>(Duration.zero);
    final position = useState<Duration>(Duration.zero);
    final playerState = useState<PlayerState>(PlayerState.stopped);
    final playbackSpeed = useState<double>(1.0);
    final isAudioLoaded = useState<bool>(false);
    final audioFileVal = useState<File?>(null);

    // Scroll & Highlight setup
    final scrollController = useScrollController();
    final autoScrollEnabled = useState<bool>(true);

    final sentences = transcriptAsync.value ?? const [];
    final activeIndex = useMemoized(() {
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

    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final textScaler = MediaQuery.textScalerOf(context);

    // 各行の高さを一度だけ事前計算する。文字起こしは録音済みで内容が
    // 変わらないので、sentences/画面幅/文字スケールが変わらない限り
    // 再計算しない(useMemoized)。これをListView.builderのitemExtentBuilderに
    // 渡すことで、実際に画面に映る行だけを遅延描画しつつ、スクロール総量は
    // 常に正確(推定に頼らない)に保てる。
    final rowHeights = useMemoized(
      () => _computeRowHeights(sentences, screenWidth, textScaler),
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

    // コンテンツ全体の本当の高さ(全行の合計+ListView自体の上下padding)。
    // Flutterの見積もり(maxScrollExtent)を待たずに、これをそのまま
    // CustomScrollbarへ渡すことで、スクロールバーが常に正確・安定する。
    final totalContentExtent = useMemoized(() {
      if (rowHeights.isEmpty) return 0.0;
      final sum = rowOffsets.last + rowHeights.last;
      return sum + _kListVerticalPadding * 2;
    }, [rowHeights, rowOffsets]);

    final syncScrollPosition = useCallback(() {
      if (scrollController.hasClients &&
          activeIndex >= 0 &&
          activeIndex < rowOffsets.length) {
        final targetOffset = rowOffsets[activeIndex] - (screenHeight / 3);
        final viewportHeight = scrollController.position.viewportDimension;
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
    }, [activeIndex, scrollController, screenHeight, rowOffsets]);

    useEffect(() {
      if (autoScrollEnabled.value &&
          activeIndex >= 0 &&
          scrollController.hasClients) {
        syncScrollPosition();
      }
      return null;
    }, [activeIndex, autoScrollEnabled.value]);

    // Watch R2 cached file if audioPath exists
    final hasAudioPath =
        lecture.audioPath != null && lecture.audioPath!.isNotEmpty;
    final r2FileAsync = hasAudioPath
        ? ref.watch(artifactFileProvider(lecture.audioPath!))
        : const AsyncValue<File?>.data(null);

    // Initialize player when R2 file is downloaded
    useEffect(() {
      if (r2FileAsync.hasValue && r2FileAsync.value != null) {
        final file = r2FileAsync.value!;
        audioFileVal.value = file;
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
    }, [r2FileAsync.value]);

    // Handle audioplayer state listeners
    useEffect(() {
      final dSub = player.onDurationChanged.listen((d) => duration.value = d);
      final pSub = player.onPositionChanged.listen((p) => position.value = p);
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

    // Fast seek callback when user taps a timestamp
    final seekToMs = useCallback((int ms) async {
      if (!isAudioLoaded.value) return;
      final target = Duration(milliseconds: ms);
      position.value = target;
      await player.seek(target);
      if (playerState.value != PlayerState.playing) {
        await player.resume();
      }
    }, [player, isAudioLoaded.value, playerState.value]);

    final isPlaying = playerState.value == PlayerState.playing;

    return Scaffold(
      backgroundColor: AppColors.paper.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Custom AppBar ──────────────────────────────────────────
            CustomAppBar(
              showHomeButton: true,
              title: 'Transcript',
              isLightBg: true,
              actions: [
                if (hasAudioPath)
                  IconButton(
                    icon: Icon(
                      autoScrollEnabled.value
                          ? Icons.sync
                          : Icons.sync_disabled,
                      color: autoScrollEnabled.value
                          ? AppColors.deepGold
                          : AppColors.paper.textPencil,
                    ),
                    tooltip: autoScrollEnabled.value
                        ? 'Auto-scroll Enabled'
                        : 'Auto-scroll Disabled',
                    onPressed: () {
                      autoScrollEnabled.value = !autoScrollEnabled.value;
                      if (autoScrollEnabled.value) {
                        syncScrollPosition();
                      }
                    },
                  ),
              ],
            ),

            // ── Transcript Text List ───────────────────────────────────────
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

                  return NotificationListener<UserScrollNotification>(
                    onNotification: (notification) {
                      if (notification.direction != ScrollDirection.idle) {
                        autoScrollEnabled.value = false;
                      }
                      return false;
                    },
                    child: CustomScrollbar(
                      controller: scrollController,
                      // 各行の高さはrowHeightsで事前計算済み(内容は不変なので
                      // 一度だけ計算)。itemExtentBuilderにそれを渡すことで、
                      // 画面に映る行だけを遅延描画(パフォーマンス確保)する。
                      // totalExtentも同じ事前計算から渡し、Flutter側の
                      // maxScrollExtentの見積もりを一切使わないようにする。
                      totalExtent: totalContentExtent,
                      child: ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: _kHorizontalPagePadding,
                          vertical: _kListVerticalPadding,
                        ),
                        itemCount: sentences.length,
                        itemExtentBuilder: (index, dimensions) =>
                            rowHeights[index],
                        itemBuilder: (context, idx) {
                          final s = sentences[idx];
                          final roleUpper = s.role.toUpperCase();
                          final isItalic =
                              roleUpper == 'INTERACTION' ||
                              roleUpper == 'OFF_TOPIC';
                          final displayColor = isItalic
                              ? AppColors.paper.textPencil
                              : AppColors.paper.textInk;

                          final isPlayingActive = idx == activeIndex;
                          const isWeakHighlighted = false;
                          final isHighlighted = isPlayingActive || isWeakHighlighted;

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
                            } else {
                              itemDecoration = BoxDecoration(color: bgColor);
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
                                  vertical: _kRowVerticalPadding,
                                  horizontal: _kRowHorizontalPadding,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Timestamp label
                                    Text(
                                      TranscriptPage._formatMs(s.start),
                                      style: _kTimestampTextStyle.copyWith(
                                        color: AppColors.deepGold,
                                        decoration: isAudioLoaded.value
                                            ? TextDecoration.underline
                                            : TextDecoration.none,
                                      ),
                                    ),
                                    const SizedBox(width: _kTimestampGap),
                                    // Sentence text
                                    Expanded(
                                      child: Text(
                                        stripSidCitations(s.text),
                                        style: _kSentenceTextStyle.copyWith(
                                          color: displayColor,
                                          fontWeight: displayWeight,
                                          fontStyle: isItalic
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

            // ── Audio Player UI (Shown only if audio exists) ────────────────
            if (hasAudioPath) ...[
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                decoration: BoxDecoration(
                  color: AppColors.paper.surface,
                  border: Border(
                    top: BorderSide(color: AppColors.paper.line, width: 1.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: r2FileAsync.when(
                  loading: () => Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: AppColors.deepGold,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Downloading audio from storage…',
                            style: TextStyle(
                              color: AppColors.paper.textPencil,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  error: (err, _) => Center(
                    child: Text(
                      'Failed to load audio: $err',
                      style: TextStyle(color: AppColors.paper.textPencil),
                    ),
                  ),
                  data: (file) {
                    if (file == null || !isAudioLoaded.value) {
                      return Center(
                        child: Text(
                          'Preparing audio player…',
                          style: TextStyle(
                            color: AppColors.paper.textPencil,
                            fontSize: 13,
                          ),
                        ),
                      );
                    }

                    final currentPos = position.value;
                    final totalDur = duration.value;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Progress Slider & Timing Info
                        Row(
                          children: [
                            Text(
                              TranscriptPage._formatDuration(currentPos),
                              style: TextStyle(
                                color: AppColors.paper.textPencil,
                                fontSize: 12,
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                ),
                                child: _CustomAudioProgressBar(
                                  position: currentPos,
                                  duration: totalDur,
                                  onSeek: (value) async {
                                    position.value = value;
                                    await player.seek(value);
                                  },
                                ),
                              ),
                            ),
                            Text(
                              TranscriptPage._formatDuration(totalDur),
                              style: TextStyle(
                                color: AppColors.paper.textPencil,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),

                        // Player Controls
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Playback Speed Button (1.0x -> 1.25x -> 1.5x -> 2.0x)
                            TextButton(
                              onPressed: () async {
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
                              child: Text(
                                '${playbackSpeed.value}x',
                                style: const TextStyle(
                                  color: AppColors.deepGold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),

                            // Rewind 10s
                            IconButton(
                              icon: const Icon(
                                Icons.replay_10_outlined,
                                color: AppColors.deepGold,
                                size: 28,
                              ),
                              onPressed: () async {
                                final target =
                                    currentPos - const Duration(seconds: 10);
                                final actualTarget = target < Duration.zero
                                    ? Duration.zero
                                    : target;
                                position.value = actualTarget;
                                await player.seek(actualTarget);
                              },
                            ),

                            // Play / Pause Circle Button
                            GestureDetector(
                              onTap: () async {
                                if (isPlaying) {
                                  await player.pause();
                                } else {
                                  await player.resume();
                                }
                              },
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: const BoxDecoration(
                                  color: AppColors.deepGold,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: Colors.white,
                                  size: 36,
                                ),
                              ),
                            ),

                            // Forward 10s
                            IconButton(
                              icon: const Icon(
                                Icons.forward_10_outlined,
                                color: AppColors.deepGold,
                                size: 28,
                              ),
                              onPressed: () async {
                                final target =
                                    currentPos + const Duration(seconds: 10);
                                final actualTarget = target > totalDur
                                    ? totalDur
                                    : target;
                                position.value = actualTarget;
                                await player.seek(actualTarget);
                              },
                            ),

                            // Spacer to balance layout
                            const SizedBox(width: 48),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 自作のカスタムシークバーコンポーネント (YouTubeライクなセグメントや微調整の土台)
// ---------------------------------------------------------------------------
class _CustomAudioProgressBar extends StatelessWidget {
  const _CustomAudioProgressBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final double percent = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;

        void seekToPosition(double localX) {
          final double ratio = (localX / width).clamp(0.0, 1.0);
          final int targetMs = (ratio * duration.inMilliseconds).round();
          onSeek(Duration(milliseconds: targetMs));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            seekToPosition(details.localPosition.dx);
          },
          onHorizontalDragUpdate: (details) {
            seekToPosition(details.localPosition.dx);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: SizedBox(
              height: 12,
              width: double.infinity,
              child: CustomPaint(
                painter: _ProgressBarPainter(
                  percent: percent,
                  activeColor: AppColors.deepGold,
                  inactiveColor: AppColors.paper.line,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  _ProgressBarPainter({
    required this.percent,
    required this.activeColor,
    required this.inactiveColor,
  });

  final double percent;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    const double trackHeight = 4.0;
    final double centerY = size.height / 2;

    // トラック全体の描画
    final Paint trackPaint = Paint()
      ..color = inactiveColor
      ..strokeWidth = trackHeight
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(trackHeight / 2, centerY),
      Offset(size.width - trackHeight / 2, centerY),
      trackPaint,
    );

    // 再生中トラックの描画
    final double activeWidth =
        (size.width - trackHeight) * percent + trackHeight / 2;
    if (activeWidth > trackHeight / 2) {
      final Paint activePaint = Paint()
        ..color = activeColor
        ..strokeWidth = trackHeight
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(trackHeight / 2, centerY),
        Offset(activeWidth, centerY),
        activePaint,
      );
    }

    // つまみ (Thumb) の描画
    const double thumbRadius = 6.0;
    final double thumbX =
        (size.width - thumbRadius * 2) * percent + thumbRadius;
    final Paint thumbPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(thumbX, centerY), thumbRadius, thumbPaint);
  }

  @override
  bool shouldRepaint(covariant _ProgressBarPainter oldDelegate) {
    return oldDelegate.percent != percent ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}
