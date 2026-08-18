import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lefture/application/asr/live_asr_controller.dart';
import 'package:lefture/application/recording/recording_controller.dart';
import 'package:lefture/application/recording/recording_state.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// Liveタブの「今ちゃんと聞こえてるよ」表示。
///
/// オンデバイスの文字起こしは、文脈を確保するために数秒分の音声を溜めてから
/// まとめて認識する。その間テキストは1文字も増えないため、これだけだと
/// ユーザーには録音・認識が生きているのかどうか分からない。マイク入力レベル
/// (常に動く)とVADの発話検知状態を出して、文字が出ていない時間も
/// 「動いている」ことが一目で分かるようにする。
class LiveListeningIndicator extends ConsumerWidget {
  const LiveListeningIndicator({super.key, required this.phase});

  final RecordingPhase phase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    // 音量だけをselectで購読する。RecordingStateをまるごとwatchすると、
    // 音声フレームが届くたびに親(文字起こしリスト全体)まで再構築されてしまう。
    final audioLevel = ref.watch(
      recordingControllerProvider.select((s) => s.audioLevel),
    );
    final status = ref.watch(liveAsrStatusProvider);

    final isPaused = phase == RecordingPhase.paused;
    final isRecording = phase == RecordingPhase.recording;

    final String label;
    final bool active;
    if (isPaused) {
      label = l10n.recordingLivePausedLabel;
      active = false;
    } else if (!status.engineRunning) {
      label = l10n.recordingLivePreparingLabel;
      active = false;
    } else if (status.speechDetected) {
      label = l10n.recordingLiveListeningLabel;
      active = true;
    } else {
      label = l10n.recordingLiveWaitingForSpeechLabel;
      active = false;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _LevelMeter(
                level: audioLevel,
                // 一時停止中はマイク自体が止まっているので、メーターも寝かせる。
                enabled: isRecording,
                highlighted: active,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active
                        ? AppColors.starGold
                        : AppColors.universe.textComet,
                    fontSize: 11,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (status.decoding) ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.universe.textComet,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.recordingLiveTranscribingLabel,
                  style: TextStyle(
                    color: AppColors.universe.textComet,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
          // 端末の処理が追いつかず確定チャンクを捨てた場合。その区間は
          // オンデバイスの字幕からは永久に欠けるので、黙っておかずに知らせる
          // (サーバー版の完全な文字起こしは後から届く)。
          if (status.droppedFinalCount > 0) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 12,
                  color: AppColors.correctionRed,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.recordingLiveDroppedNotice,
                    style: const TextStyle(
                      color: AppColors.correctionRed,
                      fontSize: 10,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// マイク入力レベルの簡易メーター。実際のマイク入力だけで動かす
/// (見た目のための擬似的な揺らぎは足さない ——「本当に聞こえているか」を
/// 示すための表示なので、入力が無いときは止まっていないと意味がない)。
class _LevelMeter extends StatelessWidget {
  const _LevelMeter({
    required this.level,
    required this.enabled,
    required this.highlighted,
  });

  final double level;
  final bool enabled;
  final bool highlighted;

  static const _barCount = 5;

  @override
  Widget build(BuildContext context) {
    // 小さな声でも動きが見えるよう、AudioWaveformVisualizerと同じ感度カーブを
    // かける。値は毎フレーム更新されるので、暗黙アニメーションは使わない
    // (実際のマイク入力そのままの動きにする)。
    final boosted = enabled
        ? (math.pow(level.clamp(0.0, 1.0), 0.6) * 1.1).toDouble()
        : 0.0;
    final litBars = (boosted * _barCount).clamp(0.0, _barCount * 1.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_barCount, (i) {
        final lit = i < litBars;
        // 右にいくほど背が高い、よくあるレベルメーター形状。
        final height = 5.0 + i * 2.5;
        return Padding(
          padding: EdgeInsets.only(right: i == _barCount - 1 ? 0 : 2),
          child: Container(
            width: 3,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(1.5),
              color: lit
                  ? (highlighted
                        ? AppColors.starGold
                        : AppColors.starGold.withValues(alpha: 0.7))
                  : AppColors.universe.textComet.withValues(alpha: 0.25),
            ),
          ),
        );
      }),
    );
  }
}
