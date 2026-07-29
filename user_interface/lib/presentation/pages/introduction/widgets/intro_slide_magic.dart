// lib/presentation/pages/introduction/widgets/intro_slide_magic.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/introduction/widgets/intro_reveal.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

const _violet = Color(0xFFB98BFF);

/// スライド2「Magic」。録音するだけで得られる3つの価値
/// (Review Cards / Deep Notes / Fun Facts)を、アイコンとともに1枚ずつ紹介する。
class IntroMagicSlide extends StatefulWidget {
  const IntroMagicSlide({super.key});

  @override
  State<IntroMagicSlide> createState() => _IntroMagicSlideState();
}

class _IntroMagicSlideState extends State<IntroMagicSlide>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  bool _eyebrow = false;
  bool _headline = false;
  bool _cards = false;
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    _after(100, () => _eyebrow = true);
    _after(240, () => _headline = true);
    _after(150, () => _cards = true);
  }

  void _after(int ms, VoidCallback apply) {
    _timers.add(Timer(Duration(milliseconds: ms), () {
      if (!mounted) return;
      setState(apply);
    }));
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
    final starlight = AppColors.universe.textStarlight;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // --- 背景に浮かび上がり揺らめく斜めのオーロラ虹グラデーション ---
            const Positioned.fill(
              child: _RainbowAuroraBackground(),
            ),

            // --- メインコンテンツ ---
            Positioned.fill(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(26, 8, 26, 176),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RiseIn(
                          visible: _eyebrow,
                          duration: const Duration(milliseconds: 550),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 20, height: 1.5, color: AppColors.starGold),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  l10n.introMagicEyebrow.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.6,
                                    color: AppColors.starGold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 13),
                        RiseIn(
                          visible: _headline,
                          duration: const Duration(milliseconds: 600),
                          child: Text(
                            l10n.introMagicHeadline,
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                              letterSpacing: -0.4,
                              color: starlight,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _ValueCard(
                          visible: _cards,
                          delayMs: 150,
                          accent: AppColors.starGold,
                          tag: l10n.introMagicCard1Tag,
                          title: l10n.introMagicCard1Title,
                          desc: l10n.introMagicCard1Desc,
                          iconBuilder: (play) => _ReviewCardsIcon(play: play),
                        ),
                        const SizedBox(height: 13),
                        _ValueCard(
                          visible: _cards,
                          delayMs: 350,
                          accent: AppColors.cosmicBlue,
                          tag: l10n.introMagicCard2Tag,
                          title: l10n.introMagicCard2Title,
                          desc: l10n.introMagicCard2Desc,
                          iconBuilder: (play) => _DeepNotesIcon(play: play),
                        ),
                        const SizedBox(height: 13),
                        _ValueCard(
                          visible: _cards,
                          delayMs: 550,
                          accent: _violet,
                          tag: l10n.introMagicCard3Tag,
                          title: l10n.introMagicCard3Title,
                          desc: l10n.introMagicCard3Desc,
                          iconBuilder: (play) => _FunFactsIcon(play: play),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // --- 手前にふわふわ浮遊する激薄レンズフレア・ボケオーブ（魔法感演出） ---
            const Positioned.fill(
              child: IgnorePointer(
                child: _LensFlareOrbsOverlay(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ValueCard extends StatefulWidget {
  const _ValueCard({
    required this.visible,
    required this.delayMs,
    required this.accent,
    required this.tag,
    required this.title,
    required this.desc,
    required this.iconBuilder,
  });

  final bool visible;
  final int delayMs;
  final Color accent;
  final String tag;
  final String title;
  final String desc;
  final Widget Function(bool play) iconBuilder;

  @override
  State<_ValueCard> createState() => _ValueCardState();
}

class _ValueCardState extends State<_ValueCard> {
  bool _shown = false;
  Timer? _timer;

  @override
  void didUpdateWidget(covariant _ValueCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _timer?.cancel();
      _timer = Timer(Duration(milliseconds: widget.delayMs), () {
        if (mounted) setState(() => _shown = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _shown ? Offset.zero : const Offset(0.13, 0),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: const Duration(milliseconds: 650),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.07),
                Colors.white.withValues(alpha: 0.02),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 22, offset: Offset(0, 10)),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(width: 3, height: 44, color: widget.accent.withValues(alpha: 0.85)),
              const SizedBox(width: 13),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: widget.accent.withValues(alpha: 0.13),
                  border: Border.all(color: widget.accent.withValues(alpha: 0.34)),
                ),
                alignment: Alignment.center,
                child: widget.iconBuilder(_shown),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: widget.accent.withValues(alpha: 0.13),
                        border: Border.all(color: widget.accent.withValues(alpha: 0.34)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.tag.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: widget.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: AppColors.universe.textStarlight,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.desc,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: AppColors.universe.textComet,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card 1: カードアイコン
class _ReviewCardsIcon extends StatelessWidget {
  const _ReviewCardsIcon({required this.play});
  final bool play;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.style_rounded, color: AppColors.starGold, size: 28);
  }
}

/// Card 2: ノートアイコン
class _DeepNotesIcon extends StatelessWidget {
  const _DeepNotesIcon({required this.play});
  final bool play;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.article_outlined, color: AppColors.cosmicBlue, size: 28);
  }
}

/// Card 3: 雑学・ライトバルブアイコン
class _FunFactsIcon extends StatelessWidget {
  const _FunFactsIcon({required this.play});
  final bool play;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.lightbulb_outline_rounded, color: _violet, size: 28);
  }
}

// ---------------------------------------------------------------------------
// 2枚目背景: 斜めにうっすら浮かび上がり揺らめくオーロラ虹グラデーション
// ---------------------------------------------------------------------------
class _RainbowAuroraBackground extends StatefulWidget {
  const _RainbowAuroraBackground();

  @override
  State<_RainbowAuroraBackground> createState() =>
      __RainbowAuroraBackgroundState();
}

class __RainbowAuroraBackgroundState extends State<_RainbowAuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat();

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
        final t = _controller.value * 2 * math.pi;
        // サイン波でグラデーションの位置と角度を100%シームレスに揺らめかせる
        final dx = math.sin(t) * 0.16;
        final dy = math.cos(t) * 0.12;

        return IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 長く引き伸ばした斜めのオーロラ虹グラデーション帯
              Transform.scale(
                scale: 2.2,
                child: Transform.rotate(
                  angle: -0.38 + math.sin(t * 2.0) * 0.03,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-1.0 + dx, -0.6 + dy),
                        end: Alignment(1.0 + dx, 0.6 + dy),
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          const Color(0xFFFF5252).withValues(alpha: 0.1),
                          const Color(0xFFFF9800).withValues(alpha: 0.1),
                          AppColors.starGold.withValues(alpha: 0.15),
                          const Color(0xFF00E676).withValues(alpha: 0.1),
                          AppColors.cosmicBlue.withValues(alpha: 0.15),
                          const Color(0xFFB98BFF).withValues(alpha: 0.15),
                          Colors.transparent,
                          Colors.transparent,
                        ],
                        stops: const [
                          0.0,
                          0.32,
                          0.37,
                          0.42,
                          0.47,
                          0.52,
                          0.57,
                          0.62,
                          0.68,
                          1.0
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 全体を程よくぼかして背景の宇宙空間へ溶け込ませる
              Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 2枚目手前: カメラのレンズフレアのような激薄で優雅な光のボケバブル（魔法感）
// ---------------------------------------------------------------------------
class _LensFlareOrbsOverlay extends StatefulWidget {
  const _LensFlareOrbsOverlay();

  @override
  State<_LensFlareOrbsOverlay> createState() => _LensFlareOrbsOverlayState();
}

class _OrbSpec {
  const _OrbSpec({
    required this.rx,
    required this.ry,
    required this.radius,
    required this.color,
    required this.baseAlpha,
    required this.driftX,
    required this.driftY,
    required this.phase,
  });

  final double rx;
  final double ry;
  final double radius;
  final Color color;
  final double baseAlpha;
  final double driftX;
  final double driftY;
  final double phase;
}

const _orbs = [
  _OrbSpec(
    rx: 0.18,
    ry: 0.22,
    radius: 40.0,
    color: Color(0xFFFFF9E6), // ウォームホワイト
    baseAlpha: 0.13,
    driftX: 24.0,
    driftY: 28.0,
    phase: 0.0,
  ),
  _OrbSpec(
    rx: 0.82,
    ry: 0.32,
    radius: 48.0,
    color: Color(0xFFE6F3FF), // アイスホワイト
    baseAlpha: 0.11,
    driftX: 20.0,
    driftY: 34.0,
    phase: 1.2,
  ),
  _OrbSpec(
    rx: 0.22,
    ry: 0.58,
    radius: 33.0,
    color: Color(0xFFF3E6FF), // ラベンダーホワイト
    baseAlpha: 0.14,
    driftX: 18.0,
    driftY: 22.0,
    phase: 2.5,
  ),
  _OrbSpec(
    rx: 0.78,
    ry: 0.70,
    radius: 42.0,
    color: Colors.white, // ピュアホワイト
    baseAlpha: 0.10,
    driftX: 26.0,
    driftY: 20.0,
    phase: 3.8,
  ),
  _OrbSpec(
    rx: 0.48,
    ry: 0.82,
    radius: 55.0,
    color: Color(0xFFFFF9E6), // ウォームホワイト
    baseAlpha: 0.10,
    driftX: 30.0,
    driftY: 25.0,
    phase: 4.6,
  ),
  _OrbSpec(
    rx: 0.88,
    ry: 0.15,
    radius: 29.0,
    color: Color(0xFFE6F3FF), // アイスホワイト
    baseAlpha: 0.15,
    driftX: 15.0,
    driftY: 18.0,
    phase: 5.2,
  ),
];

class _LensFlareOrbsOverlayState extends State<_LensFlareOrbsOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  )..repeat();

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
        return CustomPaint(
          size: Size.infinite,
          painter: _LensFlarePainter(
            progress: _controller.value,
          ),
        );
      },
    );
  }
}

class _LensFlarePainter extends CustomPainter {
  _LensFlarePainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * 2 * math.pi;

    for (final orb in _orbs) {
      // 完全シームレスな1.0周期サイン波浮遊
      final dx = math.sin(t + orb.phase) * orb.driftX;
      final dy = math.cos(t + orb.phase) * orb.driftY;
      final pulseAlpha = orb.baseAlpha * (0.75 + 0.25 * math.sin(t + orb.phase * 1.5));

      final center = Offset(
        orb.rx * size.width + dx,
        orb.ry * size.height + dy,
      );

      // 「中心が透明で、外側のフチに向けて光り、境界で消える」リング状バブルグラデーション
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            orb.color.withValues(alpha: 0.0),                            // 中心: 完全に透明
            orb.color.withValues(alpha: (pulseAlpha * 0.15).clamp(0.0, 1.0)), // 内側
            orb.color.withValues(alpha: pulseAlpha.clamp(0.0, 1.0)),     // フチの明るい輪郭
            orb.color.withValues(alpha: 0.0),                            // 外側境界: 消える
          ],
          stops: const [0.0, 0.62, 0.88, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: orb.radius));

      canvas.drawCircle(center, orb.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LensFlarePainter oldDelegate) => true;
}

