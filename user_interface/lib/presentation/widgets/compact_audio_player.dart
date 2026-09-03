// lib/presentation/widgets/compact_audio_player.dart
//
// カード型UI(復旧画面・Ready to Analyze画面など)向けのコンパクトな音声
// プレイヤー。プレゼンテーション専用ウィジェット — 再生状態そのものは
// 持たず、position/duration等の値とコールバックだけを受け取る。
// 元はrecovered_recording_view.dart内のprivateな_CompactAudioPlayerだった
// ものを、NotStartedViewからも使えるよう切り出したもの。

import 'package:flutter/material.dart';

import 'package:lefture/domain/entities/lecture_moment.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/audio_player_bar.dart';
import 'package:lefture/presentation/widgets/playback_speed_menu.dart';

class CompactAudioPlayer extends StatelessWidget {
  const CompactAudioPlayer({
    super.key,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.playbackSpeed,
    required this.onPlayPause,
    required this.onSeek,
    required this.onRewind10,
    required this.onForward10,
    required this.onSpeedSelected,
    this.moments,
  });

  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final double playbackSpeed;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onRewind10;
  final VoidCallback onForward10;
  final ValueChanged<double> onSpeedSelected;
  final List<LectureMoment>? moments;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── プログレスバー (全幅 & モーメントマーカー対応) ─────────────
          CustomAudioProgressBar(
            position: position,
            duration: duration,
            onSeek: onSeek,
            moments: moments,
            activeColor: AppColors.starGold,
            inactiveColor: AppColors.universe.glassWhiteLow,
          ),

          const SizedBox(height: 2),

          // ── 時間情報 (左右両端) ───────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AudioPlayerBar.formatDuration(position),
                  style: TextStyle(
                    color: AppColors.universe.textComet,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  AudioPlayerBar.formatDuration(duration),
                  style: TextStyle(
                    color: AppColors.universe.textComet,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // ── コントロール群 (FittedBox で極小画面でも Overflow を完全防止) ──
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 左端: 再生速度ドロップダウン
                PlaybackSpeedMenu(
                  speed: playbackSpeed,
                  onSpeedSelected: onSpeedSelected,
                  isDark: true,
                ),
                const SizedBox(width: 14),

                // 中央: 10秒戻る ＆ 再生/一時停止 ＆ 10秒進む
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.replay_10_outlined,
                        color: AppColors.starGold,
                        size: 25,
                      ),
                      onPressed: onRewind10,
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(36, 36),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: onPlayPause,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: AppColors.starGold,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.black,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(
                        Icons.forward_10_outlined,
                        color: AppColors.starGold,
                        size: 25,
                      ),
                      onPressed: onForward10,
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(36, 36),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),

                // 右端: 左右対称バランス用の48pxスペーサー
                const SizedBox(width: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
