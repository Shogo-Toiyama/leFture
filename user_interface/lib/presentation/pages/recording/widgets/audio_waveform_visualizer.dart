import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// 録音中のマイク入力音量を動的波形（イコライザー）として可視化するウィジェット
class AudioWaveformVisualizer extends StatefulWidget {
  const AudioWaveformVisualizer({
    super.key,
    required this.audioLevel,
    required this.isRecording,
    required this.isPaused,
  });

  /// 現在の音量レベル (0.0 〜 1.0)
  final double audioLevel;
  final bool isRecording;
  final bool isPaused;

  @override
  State<AudioWaveformVisualizer> createState() => _AudioWaveformVisualizerState();
}

class _AudioWaveformVisualizerState extends State<AudioWaveformVisualizer> {
  final List<double> _waveformHistory = List.generate(25, (_) => 0.0);

  @override
  void didUpdateWidget(covariant AudioWaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !widget.isPaused) {
      // 最新の音量レベルをキューに追加
      _waveformHistory.removeAt(0);
      
      // 小さな声でも自然に見やすく立ち上がる適度な感度カーブ（直前の約1.3倍）
      final boostedLevel = (math.pow(widget.audioLevel, 0.6) * 1.1).toDouble();
      _waveformHistory.add(boostedLevel.clamp(0.0, 1.0));
      setState(() {});
    } else {
      // 静止・停止時は完全フラット
      bool needsUpdate = false;
      for (int i = 0; i < _waveformHistory.length; i++) {
        if (_waveformHistory[i] != 0.0) {
          _waveformHistory[i] = 0.0;
          needsUpdate = true;
        }
      }
      if (needsUpdate) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      width: double.infinity,
      child: CustomPaint(
        painter: _WaveformPainter(
          levels: _waveformHistory,
          isRecording: widget.isRecording && !widget.isPaused,
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> levels;
  final bool isRecording;

  _WaveformPainter({
    required this.levels,
    required this.isRecording,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;

    final count = levels.length;
    final totalSpacing = size.width * 0.4;
    final barWidth = (size.width - totalSpacing) / count;
    final spacing = totalSpacing / (count - 1);
    final centerY = size.height / 2;

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    // マイクActive(録音中)時はベースの高さを少し上げて(7.0px)待機状態を明示、
    // 非Active(停止/Pause)時は細いドット(3.5px)にする
    final minBarHeight = isRecording ? 7.0 : 3.5;

    for (int i = 0; i < count; i++) {
      final x = i * (barWidth + spacing) + (barWidth / 2);
      
      // 中央に向かって滑らかなエンベロープ形状にするための係数
      final normalizedIndex = (i - count / 2).abs() / (count / 2);
      final envelope = math.sin((1.0 - normalizedIndex) * math.pi / 2);

      final level = levels[i];

      // 音量に応じた高さの計算（擬似的な揺らぎは一切足さず、本物のマイク入力のみで動く）
      final barHeight = minBarHeight + (size.height - minBarHeight) * level * envelope;

      // 色とグラデーションの設定
      final Color barColor;
      if (isRecording) {
        if (level > 0.04) {
          final hue = 42.0 + (level * 10); // ゴールド〜ウォームイエロー
          barColor = HSLColor.fromAHSL(
            (0.5 + level * 0.5).clamp(0.0, 1.0),
            hue,
            0.9,
            0.6,
          ).toColor();
        } else {
          // マイクON・静音時はベースのゴールド待機色
          barColor = AppColors.starGold.withValues(alpha: 0.35);
        }
      } else {
        // マイクOFF・一時停止時は静かなスレートグレー
        barColor = AppColors.universe.textComet.withValues(alpha: 0.25);
      }

      paint.color = barColor;

      // ガウスグロー効果（大きな音の時）
      if (isRecording && level > 0.3) {
        final glowPaint = Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = barWidth * 1.5
          ..color = AppColors.starGold.withValues(alpha: (level * 0.25).clamp(0.0, 0.4))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        
        canvas.drawLine(
          Offset(x, centerY - (barHeight / 2)),
          Offset(x, centerY + (barHeight / 2)),
          glowPaint,
        );
      }

      canvas.drawLine(
        Offset(x, centerY - (barHeight / 2)),
        Offset(x, centerY + (barHeight / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return true;
  }
}
