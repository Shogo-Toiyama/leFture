import 'dart:math' as math;
import 'package:flutter/material.dart';

class GlowingRainbowBorder extends StatefulWidget {
  const GlowingRainbowBorder({
    super.key,
    required this.child,
    this.borderRadius = 20.0,
    this.borderWidth = 2.0,
    this.glowRadius = 8.0,
    this.animate = false,
    this.duration = const Duration(seconds: 10),
    this.innerGlow = true,
    this.glowOpacity = 0.4,
    this.softEdges = false,
  });

  final Widget child;
  final double borderRadius;
  final double borderWidth;
  final double glowRadius;
  final bool animate;
  final Duration duration;
  final bool innerGlow;
  final double glowOpacity;
  final bool softEdges;

  @override
  State<GlowingRainbowBorder> createState() => _GlowingRainbowBorderState();
}

class _GlowingRainbowBorderState extends State<GlowingRainbowBorder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant GlowingRainbowBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
      if (widget.animate) {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final animationValue = widget.animate ? _controller.value : 0.0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Glow layer
            if (widget.glowRadius > 0)
              Positioned.fill(
                child: CustomPaint(
                  painter: _RainbowGlowPainter(
                    animationValue: animationValue,
                    borderRadius: widget.borderRadius,
                    borderWidth: widget.innerGlow
                        ? (widget.borderWidth + widget.glowRadius) * 2
                        : widget.borderWidth + widget.glowRadius,
                    isGlow: true,
                    blurSigma: widget.glowRadius,
                    innerGlow: widget.innerGlow,
                    opacity: widget.glowOpacity,
                    softEdges: widget.softEdges,
                  ),
                ),
              ),
            // Sharp border layer (Only painted when NOT in innerGlow mode AND NOT in softEdges mode)
            if (!widget.innerGlow && !widget.softEdges)
              Positioned.fill(
                child: CustomPaint(
                  painter: _RainbowGlowPainter(
                    animationValue: animationValue,
                    borderRadius: widget.borderRadius,
                    borderWidth: widget.borderWidth,
                    isGlow: false,
                    innerGlow: false,
                    opacity: 1.0,
                    softEdges: false,
                  ),
                ),
              ),
            // Child content
            widget.child,
          ],
        );
      },
    );
  }
}

class _RainbowGlowPainter extends CustomPainter {
  _RainbowGlowPainter({
    required this.animationValue,
    required this.borderRadius,
    required this.borderWidth,
    required this.isGlow,
    this.blurSigma = 0.0,
    required this.innerGlow,
    required this.opacity,
    this.softEdges = false,
  });

  final double animationValue;
  final double borderRadius;
  final double borderWidth;
  final bool isGlow;
  final double blurSigma;
  final bool innerGlow;
  final double opacity;
  final bool softEdges;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Red-based glowing palette
    final colors = [
      Color(0xFFFF2D55).withValues(alpha: opacity),
      Color(0xFF9B51E0).withValues(alpha: opacity),
      Color(0xFF2D9CDB).withValues(alpha: opacity),
      Color(0xFF27AE60).withValues(alpha: opacity),
      Color(0xFFF2C94C).withValues(alpha: opacity),
      Color(0xFFFF2D55).withValues(alpha: opacity),
    ];

    final angle = animationValue * 2 * math.pi;

    final gradient = SweepGradient(
      center: Alignment.center,
      colors: colors,
      transform: GradientRotation(angle),
    );

    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    if (isGlow && blurSigma > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma);
    }

    final shouldClip = innerGlow && !softEdges;

    if (borderRadius <= 0) {
      if (shouldClip) {
        canvas.save();
        canvas.clipRect(rect);
      }
      canvas.drawRect(rect, paint);
      if (shouldClip) {
        canvas.restore();
      }
    } else {
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));
      if (shouldClip) {
        canvas.save();
        canvas.clipRRect(rrect);
      }
      canvas.drawRRect(rrect, paint);
      if (shouldClip) {
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RainbowGlowPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.isGlow != isGlow ||
        oldDelegate.blurSigma != blurSigma ||
        oldDelegate.innerGlow != innerGlow ||
        oldDelegate.opacity != opacity ||
        oldDelegate.softEdges != softEdges;
  }
}
