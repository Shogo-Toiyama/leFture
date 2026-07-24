// lib/presentation/widgets/audio_player_bar.dart

import 'package:flutter/material.dart';
import 'package:lefture/core/utils/moment_display_utils.dart';
import 'package:lefture/core/utils/topic_color_utils.dart';
import 'package:lefture/domain/entities/lecture_moment.dart';
import 'package:lefture/domain/entities/lecture_topic.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

class TopicProgressRange {
  const TopicProgressRange({
    required this.startRatio,
    required this.endRatio,
  });
  final double startRatio;
  final double endRatio;
}

/// トランスクリプト画面およびボトムシート等で共通して利用する音声再生操作バー。
/// トピックセグメント化プログレスバー、左右対称コントロールレイアウト、
/// および上向き（スライドアップ）のトピック目次メニューを統合。
class AudioPlayerBar extends StatefulWidget {
  const AudioPlayerBar({
    super.key,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.playbackSpeed,
    required this.isAudioLoaded,
    this.isLoading = false,
    this.errorMessage,
    required this.onPlayPause,
    required this.onSeek,
    required this.onRewind10,
    required this.onForward10,
    required this.onChangeSpeed,
    this.topics,
    this.currentTopic,
    this.moments,
    this.topicProgresses,
    this.topicRanges,
    this.topicColors,
    this.onPreviousTopic,
    this.onNextTopic,
    this.onTopicSelected,
  });

  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final double playbackSpeed;
  final bool isAudioLoaded;
  final bool isLoading;
  final String? errorMessage;

  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onRewind10;
  final VoidCallback onForward10;
  final VoidCallback onChangeSpeed;

  final List<LectureTopic>? topics;
  final LectureTopic? currentTopic;
  final List<LectureMoment>? moments;
  final List<double>? topicProgresses;
  final List<TopicProgressRange>? topicRanges;
  final List<Color>? topicColors;
  final VoidCallback? onPreviousTopic;
  final VoidCallback? onNextTopic;
  final ValueChanged<LectureTopic>? onTopicSelected;

  static String formatDuration(Duration d) {
    final totalSeconds = d.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  State<AudioPlayerBar> createState() => _AudioPlayerBarState();
}

class _AudioPlayerBarState extends State<AudioPlayerBar> {
  bool _isMenuExpanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasTopics = widget.topics != null && widget.topics!.isNotEmpty;
    final currentTopic = widget.currentTopic;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.paper.surface,
        border: Border(
          top: BorderSide(color: AppColors.paper.line, width: 1.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 上向き（ポップアップ）トピック目次メニュー ────────────
          if (hasTopics)
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 250),
              crossFadeState: _isMenuExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: Container(
                constraints: const BoxConstraints(maxHeight: 240),
                color: AppColors.paper.background,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      color: AppColors.paper.surface,
                      child: Row(
                        children: [
                          Icon(
                            Icons.format_list_bulleted_rounded,
                            size: 16,
                            color: AppColors.deepGold,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.audioPlayerBarTopicIndexTitle,
                            style: TextStyle(
                              color: AppColors.paper.textInk,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: AppColors.paper.textPencil,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              setState(() {
                                _isMenuExpanded = false;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: AppColors.paper.line),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: widget.topics!.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          thickness: 0.5,
                          indent: 16,
                          endIndent: 16,
                          color: AppColors.paper.line,
                        ),
                        itemBuilder: (context, index) {
                          final topic = widget.topics![index];
                          final isSelected =
                              currentTopic != null && topic.id == currentTopic.id;
                          final topicColor = TopicColorUtils.getTopicColor(
                            index,
                            widget.topics!.length,
                          );

                          return InkWell(
                            onTap: () {
                              setState(() {
                                _isMenuExpanded = false;
                              });
                              if (widget.onTopicSelected != null) {
                                widget.onTopicSelected!(topic);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 9,
                              ),
                              color: isSelected
                                  ? topicColor.withValues(alpha: 0.12)
                                  : Colors.transparent,
                              child: Row(
                                children: [
                                  Container(
                                    width: 3.5,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: topicColor,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    l10n.audioPlayerBarTopicLabel(topic.index),
                                    style: TextStyle(
                                      color: isSelected
                                          ? topicColor
                                          : AppColors.paper.textPencil,
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      topic.displayTitle,
                                      style: TextStyle(
                                        color: AppColors.paper.textInk,
                                        fontSize: 13,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      Icons.check_circle_rounded,
                                      color: topicColor,
                                      size: 16,
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
              ),
            ),

          // ── プレイヤー組み込み型トピックヘッダーバー ──────────────
          if (hasTopics && currentTopic != null) ...[
            InkWell(
              onTap: () {
                setState(() {
                  _isMenuExpanded = !_isMenuExpanded;
                });
              },
              child: Builder(builder: (context) {
                final currentIndex = widget.topics!.indexOf(currentTopic);
                final safeIndex = currentIndex >= 0 ? currentIndex : 0;
                final topicColor = TopicColorUtils.getTopicColor(
                  safeIndex,
                  widget.topics!.length,
                );
                final topicBgColor = TopicColorUtils.getTopicBackgroundColor(
                  safeIndex,
                  widget.topics!.length,
                  alpha: 0.10,
                );

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  color: topicBgColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: topicColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          l10n.audioPlayerBarTopicLabel(currentTopic.index),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          currentTopic.displayTitle,
                          style: TextStyle(
                            color: AppColors.paper.textInk,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        _isMenuExpanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_up_rounded,
                        color: AppColors.paper.textPencil,
                        size: 18,
                      ),
                    ],
                  ),
                );
              }),
            ),
            Divider(height: 1, thickness: 1, color: AppColors.paper.line),
          ],

          // ── 音声プレイヤーのメイン領域 ───────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _buildPlayerContent(context, hasTopics),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerContent(BuildContext context, bool hasTopics) {
    final l10n = AppLocalizations.of(context);

    if (widget.isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: AppColors.deepGold,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              l10n.audioPlayerBarDownloadingMessage,
              style: TextStyle(
                color: AppColors.paper.textPencil,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            l10n.audioPlayerBarLoadErrorMessage(widget.errorMessage!),
            style: TextStyle(color: AppColors.paper.textPencil, fontSize: 13),
          ),
        ),
      );
    }

    if (!widget.isAudioLoaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            l10n.audioPlayerBarPreparingMessage,
            style: TextStyle(
              color: AppColors.paper.textPencil,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── セグメント化プログレスバー ＆ 時間情報 ─────────────────
        Row(
          children: [
            Text(
              AudioPlayerBar.formatDuration(widget.position),
              style: TextStyle(
                color: AppColors.paper.textPencil,
                fontSize: 11.5,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: CustomAudioProgressBar(
                  position: widget.position,
                  duration: widget.duration,
                  onSeek: widget.onSeek,
                  moments: widget.moments,
                  topicProgresses: widget.topicProgresses,
                  topicRanges: widget.topicRanges,
                  topicColors: widget.topicColors,
                ),
              ),
            ),
            Text(
              AudioPlayerBar.formatDuration(widget.duration),
              style: TextStyle(
                color: AppColors.paper.textPencil,
                fontSize: 11.5,
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),

        // ── コントロール群 (完璧な左右対称レイアウト) ─────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 左端: 再生速度ボタン (固定幅 44px)
            SizedBox(
              width: 44,
              child: TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 36),
                  padding: EdgeInsets.zero,
                ),
                onPressed: widget.onChangeSpeed,
                child: Text(
                  '${widget.playbackSpeed}x',
                  style: const TextStyle(
                    color: AppColors.deepGold,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),

            // 左側アクション: 前トピック ＆ 10秒戻る
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.skip_previous_rounded,
                    color: AppColors.deepGold,
                    size: 26,
                  ),
                  onPressed: widget.onPreviousTopic,
                  tooltip: l10n.audioPlayerBarPreviousTopicTooltip,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(
                    Icons.replay_10_outlined,
                    color: AppColors.deepGold,
                    size: 25,
                  ),
                  onPressed: widget.onRewind10,
                  tooltip: l10n.audioPlayerBarRewindTooltip,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),

            // 中央: 再生 / 一時停止ボタン (52x52)
            GestureDetector(
              onTap: widget.onPlayPause,
              child: Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: AppColors.deepGold,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),

            // 右側アクション: 10秒進む ＆ 次トピック
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.forward_10_outlined,
                    color: AppColors.deepGold,
                    size: 25,
                  ),
                  onPressed: widget.onForward10,
                  tooltip: l10n.audioPlayerBarForwardTooltip,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(
                    Icons.skip_next_rounded,
                    color: AppColors.deepGold,
                    size: 26,
                  ),
                  onPressed: widget.onNextTopic,
                  tooltip: l10n.audioPlayerBarNextTopicTooltip,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),

            // 右端: トピック目次アイコン / バランスSpacer (固定幅 44px)
            SizedBox(
              width: 44,
              child: hasTopics
                  ? IconButton(
                      icon: Icon(
                        _isMenuExpanded
                            ? Icons.format_list_bulleted_rounded
                            : Icons.list_rounded,
                        color: AppColors.deepGold,
                        size: 22,
                      ),
                      onPressed: () {
                        setState(() {
                          _isMenuExpanded = !_isMenuExpanded;
                        });
                      },
                      tooltip: l10n.audioPlayerBarTopicIndexMenuTooltip,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    );
  }
}

/// カスタムシークバーコンポーネント (トピックのセグメント化分割バーに対応)
class CustomAudioProgressBar extends StatelessWidget {
  const CustomAudioProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.moments,
    this.topicProgresses,
    this.topicRanges,
    this.topicColors,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final List<LectureMoment>? moments;
  final List<double>? topicProgresses;
  final List<TopicProgressRange>? topicRanges;
  final List<Color>? topicColors;

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
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: SizedBox(
              height: 20,
              width: double.infinity,
              child: CustomPaint(
                painter: _ProgressBarPainter(
                  percent: percent,
                  activeColor: AppColors.deepGold,
                  inactiveColor: AppColors.paper.line,
                  durationInSeconds: duration.inSeconds,
                  moments: moments,
                  topicProgresses: topicProgresses,
                  topicRanges: topicRanges,
                  topicColors: topicColors,
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
    required this.durationInSeconds,
    this.moments,
    this.topicProgresses,
    this.topicRanges,
    this.topicColors,
  });

  final double percent;
  final Color activeColor;
  final Color inactiveColor;
  final int durationInSeconds;
  final List<LectureMoment>? moments;
  final List<double>? topicProgresses;
  final List<TopicProgressRange>? topicRanges;
  final List<Color>? topicColors;

  @override
  void paint(Canvas canvas, Size size) {
    const double trackHeight = 4.5;
    final double centerY = size.height / 2;
    final double totalWidth = size.width;

    final ranges = topicRanges;
    final progresses = topicProgresses;
    final colors = topicColors;

    // トピックセグメント情報を構築
    final List<_SegmentRange> segments = [];

    if (ranges != null && ranges.isNotEmpty) {
      double lastPos = 0.0;
      for (int i = 0; i < ranges.length; i++) {
        final range = ranges[i];
        final double start = range.startRatio.clamp(0.0, 1.0);
        final double end = range.endRatio.clamp(0.0, 1.0);

        if (start > lastPos + 0.001) {
          segments.add(_SegmentRange(
            startRatio: lastPos,
            endRatio: start,
            color: null,
          ));
        }

        if (end > start) {
          final Color topicColor =
              (colors != null && i < colors.length) ? colors[i] : activeColor;
          segments.add(_SegmentRange(
            startRatio: start,
            endRatio: end,
            color: topicColor,
          ));
          lastPos = end;
        }
      }

      if (lastPos < 0.999) {
        segments.add(_SegmentRange(
          startRatio: lastPos,
          endRatio: 1.0,
          color: null,
        ));
      }
    } else if (progresses != null && progresses.isNotEmpty) {
      final int topicCount = progresses.length;

      if (progresses.first > 0.001) {
        segments.add(_SegmentRange(
          startRatio: 0.0,
          endRatio: progresses.first.clamp(0.0, 1.0),
          color: null,
        ));
      }

      for (int i = 0; i < topicCount; i++) {
        final double start = progresses[i].clamp(0.0, 1.0);
        final double nextStart = (i + 1 < topicCount)
            ? progresses[i + 1].clamp(0.0, 1.0)
            : 1.0;

        if (nextStart > start) {
          final Color topicColor =
              (colors != null && i < colors.length) ? colors[i] : activeColor;
          segments.add(_SegmentRange(
            startRatio: start,
            endRatio: nextStart,
            color: topicColor,
          ));
        }
      }

      if (segments.isNotEmpty && segments.last.endRatio < 0.999) {
        segments.add(_SegmentRange(
          startRatio: segments.last.endRatio,
          endRatio: 1.0,
          color: null,
        ));
      }
    } else {
      segments.add(const _SegmentRange(
        startRatio: 0.0,
        endRatio: 1.0,
        color: null,
      ));
    }

    const double gap = 4.0; // セグメント間の視覚的な隙間
    const double capRadius = trackHeight / 2; // 端点の丸み半径

    final double currentX = totalWidth * percent;

    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final double rawStartX = totalWidth * seg.startRatio;
      final double rawEndX = totalWidth * seg.endRatio;

      if (rawEndX <= rawStartX) continue;

      final double drawStartX = (i == 0)
          ? rawStartX + capRadius
          : rawStartX + gap / 2 + capRadius;
      final double drawEndX = (i == segments.length - 1)
          ? rawEndX - capRadius
          : rawEndX - gap / 2 - capRadius;

      if (drawEndX < drawStartX) continue;

      final bool isTopic = seg.color != null;
      final Color segInactiveColor = isTopic
          ? seg.color!.withValues(alpha: 0.28)
          : AppColors.paper.line;
      final Color segActiveColor = isTopic
          ? seg.color!
          : AppColors.paper.textPencil;

      // 未再生セグメントの描画
      final Paint inactivePaint = Paint()
        ..color = segInactiveColor
        ..strokeWidth = trackHeight
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(drawStartX, centerY),
        Offset(drawEndX, centerY),
        inactivePaint,
      );

      // 再生済みセグメントの描画
      if (currentX > rawStartX) {
        final double activeRawEndX = currentX < rawEndX ? currentX : rawEndX;
        final double drawActiveEndX = (activeRawEndX - capRadius).clamp(
          drawStartX,
          drawEndX,
        );

        if (drawActiveEndX >= drawStartX) {
          final Paint activePaint = Paint()
            ..color = segActiveColor
            ..strokeWidth = trackHeight
            ..strokeCap = StrokeCap.round;

          canvas.drawLine(
            Offset(drawStartX, centerY),
            Offset(drawActiveEndX, centerY),
            activePaint,
          );
        }
      }
    }

    // ── モーメントアイコンの描画 (ピンではなくアイコンそのまま) ──────────────
    if (moments != null && moments!.isNotEmpty && durationInSeconds > 0) {
      for (final m in moments!) {
        final double ratio = (m.timestampSec / durationInSeconds).clamp(0.0, 1.0);
        final double x = totalWidth * ratio;

        final (iconData, color, _) = MomentDisplayUtils.getMomentDisplay(m.momentType);

        const double momentRadius = 7.5;
        final Paint bgPaint = Paint()
          ..color = AppColors.paper.surface
          ..style = PaintingStyle.fill;
        final Paint borderPaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3;

        canvas.drawCircle(Offset(x, centerY), momentRadius, bgPaint);
        canvas.drawCircle(Offset(x, centerY), momentRadius, borderPaint);

        final TextPainter iconPainter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(iconData.codePoint),
            style: TextStyle(
              fontSize: 9.5,
              fontFamily: iconData.fontFamily,
              package: iconData.fontPackage,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        iconPainter.paint(
          canvas,
          Offset(x - iconPainter.width / 2, centerY - iconPainter.height / 2),
        );
      }
    }

    // ── つまみ (Thumb) の描画 (大きめの径 9.0px) ──────────────────────
    const double thumbRadius = 9.0;
    final double thumbX =
        (totalWidth - thumbRadius * 2) * percent + thumbRadius;

    // シャドウ
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(Offset(thumbX, centerY + 1), thumbRadius + 1, shadowPaint);

    // 白枠
    final Paint thumbOuterPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(thumbX, centerY), thumbRadius, thumbOuterPaint);

    // メインカラー
    final Paint thumbInnerPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(thumbX, centerY), thumbRadius - 2.0, thumbInnerPaint);
  }

  @override
  bool shouldRepaint(covariant _ProgressBarPainter oldDelegate) {
    return oldDelegate.percent != percent ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.durationInSeconds != durationInSeconds ||
        oldDelegate.moments != moments ||
        oldDelegate.topicProgresses != topicProgresses ||
        oldDelegate.topicRanges != topicRanges ||
        oldDelegate.topicColors != topicColors;
  }
}

class _SegmentRange {
  const _SegmentRange({
    required this.startRatio,
    required this.endRatio,
    this.color,
  });

  final double startRatio;
  final double endRatio;
  final Color? color;
}
