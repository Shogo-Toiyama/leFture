// lib/presentation/pages/introduction/widgets/intro_slide_cta.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/introduction/widgets/intro_reveal.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// スライド3「CTA」。回転するポータルと金色の leFture ロゴで
/// 「発進」感を出し、最後の後押しをする。
class IntroCtaSlide extends StatefulWidget {
  const IntroCtaSlide({super.key});

  @override
  State<IntroCtaSlide> createState() => _IntroCtaSlideState();
}

class _IntroCtaSlideState extends State<IntroCtaSlide>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  bool _portal = false;
  bool _wordmark = false;
  bool _lead = false;
  bool _sub = false;
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    _after(100, () => _portal = true);
    _after(500, () => _wordmark = true);
    _after(720, () => _lead = true);
    _after(920, () => _sub = true);
  }

  void _after(int ms, VoidCallback apply) {
    _timers.add(
      Timer(Duration(milliseconds: ms), () {
        if (!mounted) return;
        setState(apply);
      }),
    );
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                30,
                MediaQuery.paddingOf(context).top + 52,
                30,
                190,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  RiseIn(
                    visible: _portal,
                    duration: const Duration(milliseconds: 700),
                    slideFraction: 0,
                    child: AnimatedScale(
                      scale: _portal ? 1 : 0.4,
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.elasticOut,
                      child: const _Portal(),
                    ),
                  ),
                  const SizedBox(height: 22),
                  RiseIn(
                    visible: _wordmark,
                    duration: const Duration(milliseconds: 600),
                    child: ShaderMask(
                      shaderCallback: (rect) => const LinearGradient(
                        colors: [
                          Color(0xFFFFD166),
                          AppColors.starGold,
                          Color(0xFFCC8D00),
                        ],
                      ).createShader(rect),
                      child: const Text(
                        'leFture',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Color(0x59FFB300), blurRadius: 26),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  RiseIn(
                    visible: _lead,
                    duration: const Duration(milliseconds: 600),
                    child: Text(
                      l10n.introCtaLead,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        height: 1.42,
                        letterSpacing: -0.2,
                        color: AppColors.universe.textStarlight,
                      ),
                    ),
                  ),
                  const SizedBox(height: 13),
                  RiseIn(
                    visible: _sub,
                    duration: const Duration(milliseconds: 600),
                    child: Text(
                      l10n.introCtaSub,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: AppColors.universe.textComet,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
      },
    );
  }
}

class _Portal extends StatefulWidget {
  const _Portal();
  @override
  State<_Portal> createState() => _PortalState();
}

class _PortalState extends State<_Portal> with TickerProviderStateMixin {
  late final AnimationController _spinCw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 14000),
  )..repeat();
  late final AnimationController _spinCcw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 9600),
  )..repeat();

  @override
  void dispose() {
    _spinCw.dispose();
    _spinCcw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 124,
      height: 124,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 外側リング: 金色 + 濃い茶色 (広めのギャップ)
          RotationTransition(
            turns: _spinCw,
            child: CustomPaint(
              size: const Size(124, 124),
              painter: _OuterArcRingPainter(
                colors: const [AppColors.starGold, Color(0xFF4A3400)],
                strokeWidth: 2.8,
              ),
            ),
          ),
          // 内側リング: 水色:白:緑 (4:2:1 比率) + 広めの空白ギャップ
          RotationTransition(
            turns: _spinCcw,
            child: CustomPaint(
              size: const Size(92, 92),
              painter: _ColorfulInnerArcRingPainter(strokeWidth: 2.2),
            ),
          ),
          // 中心の輝くコア
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Colors.white, AppColors.starGold, Color(0xFF4A3400)],
                stops: [0, 0.55, 1],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.starGold.withValues(alpha: 0.55),
                  blurRadius: 30,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 外側リング (金色 ＆ 濃い茶色)
class _OuterArcRingPainter extends CustomPainter {
  _OuterArcRingPainter({required this.colors, required this.strokeWidth});
  final List<Color> colors;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - strokeWidth,
    );
    const gap = 0.55; // 広めの空白ギャップ
    final sweep = math.pi - gap;
    for (var i = 0; i < 2; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = colors[i % colors.length];
      canvas.drawArc(rect, i * math.pi + gap / 2, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OuterArcRingPainter oldDelegate) => false;
}

/// 内側リング (水色 : 白 : 緑 = 4 : 2 : 1 比率 ＋ 広めの空白ギャップ)
class _ColorfulInnerArcRingPainter extends CustomPainter {
  _ColorfulInnerArcRingPainter({required this.strokeWidth});
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - strokeWidth,
    );

    // 水色 (4), 白 (2), 緑 (1) の比率
    final segments = [
      _ColorSegment(const Color(0xFF4AA8FF), 4),
      _ColorSegment(Colors.white, 2),
      _ColorSegment(const Color(0xFF4EBE73), 1),
    ];

    const totalRatio = 7.0;
    // 全周 2π (約 6.28) のうち、半分の 3.2 程度を描画用に使用し、残り(約 3.08)を広い空白スペースにする
    const activeCoverage = math.pi * 1.05; // 描画弧の合計アーク長
    const gapBetweenSegments = 0.35; // セグメント間の余白

    var currentAngle = -math.pi / 2;

    for (final seg in segments) {
      final sweepAngle = (seg.ratio / totalRatio) * activeCoverage;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = seg.color;

      canvas.drawArc(rect, currentAngle, sweepAngle, false, paint);
      currentAngle += sweepAngle + gapBetweenSegments;
    }
  }

  @override
  bool shouldRepaint(covariant _ColorfulInnerArcRingPainter oldDelegate) =>
      false;
}

class _ColorSegment {
  const _ColorSegment(this.color, this.ratio);
  final Color color;
  final double ratio;
}
