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

class _AudioWaveformVisualizerState extends State<AudioWaveformVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  final List<double> _waveformHistory = List.generate(25, (_) => 0.05);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant AudioWaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !widget.isPaused) {
      // 最新の音量レベルをキューに追加
      _waveformHistory.removeAt(0);
      // 小さな教授の声でもしっかり視覚化されるよう感度ブースト
      final boostedLevel = math.pow(widget.audioLevel, 0.65) * 1.25;
      final clampedLevel = math.max(0.08, boostedLevel.clamp(0.0, 1.0));
      _waveformHistory.add(clampedLevel);
    } else {
      // 静止時の低水準レベル
      for (int i = 0; i < _waveformHistory.length; i++) {
        _waveformHistory[i] = 0.05;
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return SizedBox(
          height: 44,
          width: double.infinity,
          child: CustomPaint(
            painter: _WaveformPainter(
              levels: _waveformHistory,
              isRecording: widget.isRecording && !widget.isPaused,
              animValue: _animController.value,
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> levels;
  final bool isRecording;
  final double animValue;

  _WaveformPainter({
    required this.levels,
    required this.isRecording,
    required this.animValue,
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

    for (int i = 0; i < count; i++) {
      final x = i * (barWidth + spacing) + (barWidth / 2);
      
      // 中央に向かって滑らかなエンベロープ形状にするための係数
      final normalizedIndex = (i - count / 2).abs() / (count / 2);
      final envelope = math.sin((1.0 - normalizedIndex) * math.pi / 2);

      double level = levels[i];
      if (isRecording) {
        // 微小なサイン波揺らぎを加えて活き活きとした動きを演出
        final waveModifier = math.sin(animValue * 2 * math.pi + i * 0.4) * 0.12;
        level = (level + waveModifier).clamp(0.06, 1.0);
      }

      final barHeight = math.max(6.0, size.height * level * envelope);

      // 色とグラデーションの設定
      Color barColor;
      if (isRecording) {
        final hue = 42.0 + (level * 10); // ゴールド〜ウォームイエロー
        barColor = HSLColor.fromAHSL(
          (0.4 + level * 0.6).clamp(0.0, 1.0),
          hue,
          0.9,
          0.6,
        ).toColor();
      } else {
        barColor = AppColors.universe.textComet.withValues(alpha: 0.3);
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
