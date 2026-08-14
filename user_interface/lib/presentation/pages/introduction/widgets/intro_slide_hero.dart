// lib/presentation/pages/introduction/widgets/intro_slide_hero.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/introduction/widgets/intro_particle_field.dart';
import 'package:lefture/presentation/pages/introduction/widgets/intro_reveal.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/galaxy/galaxy_view.dart';

/// スライド1「Hero」。
/// GalaxyView自体のカメラzoomパラメータで動的にズーム演出を行う。
/// デフォルトの綺麗な斜めアングルで配置し、イコライザーと銀河のアニメーション開始タイミングを早める。
class IntroHeroSlide extends StatefulWidget {
  const IntroHeroSlide({super.key, required this.particleFieldKey});
  final GlobalKey<IntroParticleFieldState> particleFieldKey;

  @override
  State<IntroHeroSlide> createState() => _IntroHeroSlideState();
}

class _IntroHeroSlideState extends State<IntroHeroSlide>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _eyebrow = false;
  bool _title1 = false;
  bool _title2 = false;
  bool _subtitle = false;
  bool _barsGrown = false;
  bool _galaxyGrown = false;
  bool _toyboxVisible = false;

  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    // アニメーションのタイミングを早めてスムーズに連動させる
    _after(100, () => _eyebrow = true);
    _after(250, () => _title1 = true);
    _after(400, () => _title2 = true);
    _after(550, () => _subtitle = true);

    // タイトルと連動して早めのタイミング(250ms)で銀河が出現＆ズーム開始
    _after(250, () => _galaxyGrown = true);

    // 早めのタイミング(350ms)でイコライザーが立ち上がり、優雅に金色へ変化
    _after(350, () => _barsGrown = true);

    // 銀河ズームが始まったタイミングで玩具箱アセットが飛び出す
    _after(600, () => _toyboxVisible = true);
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
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Stack(
              children: [
                // --- 本物の銀河 (GalaxyView) の内部zoomパラメータによる動的ズーム演出 ---
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: _galaxyGrown ? 0.95 : 0.0,
                    duration: const Duration(milliseconds: 1600),
                    curve: Curves.easeOutCubic,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: 1.5,
                        end: _galaxyGrown ? 3.0 : 1.5,
                      ),
                      duration: const Duration(milliseconds: 2200),
                      curve: Curves.easeOutQuart,
                      builder: (context, currentZoom, child) {
                        return IgnorePointer(
                          child: GalaxyView(
                            enableAutoRotate: false, // 自動回転オフ
                            glowScale: 1.5,
                            zoom: currentZoom, // GalaxyViewの内部カメラzoomパラメータで動的に拡大
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // --- 銀河の手前に挟む少し暗めの減光シート (イコライザーの輝きを際立たせる) ---
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: _galaxyGrown ? 0.45 : 0.0,
                    duration: const Duration(milliseconds: 1600),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.38),
                    ),
                  ),
                ),

                // --- 画面横いっぱいに広がる上部背景遮蔽グラデーション ---
                Positioned(
                  top: -8,
                  left: -26,
                  right: -26,
                  height: 320,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.universe.voidBackground,
                          AppColors.universe.voidBackground.withValues(alpha: 0.92),
                          AppColors.universe.voidBackground.withValues(alpha: 0.0),
                        ],
                        stops: const [0.0, 0.72, 1.0],
                      ),
                    ),
                  ),
                ),

                // --- Cosmic Toybox: タイトル文字の背面に配置 ---
                Positioned.fill(
                  child: IgnorePointer(
                    child: _ToyboxPopBurst(visible: _toyboxVisible),
                  ),
                ),

                // --- タイトル文章ブロック ---
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    26,
                    MediaQuery.paddingOf(context).top + 52,
                    26,
                    176,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RiseIn(
                          visible: _eyebrow,
                          duration: const Duration(milliseconds: 600),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 20, height: 1.5, color: AppColors.starGold),
                              const SizedBox(width: 8),
                              Text(
                                l10n.introHeroEyebrow.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2.2,
                                  color: AppColors.starGold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        RiseIn(
                          visible: _title1,
                          duration: const Duration(milliseconds: 700),
                          child: Text(
                            l10n.introHeroTitleLine1,
                            style: TextStyle(
                              fontSize: 35,
                              fontWeight: FontWeight.w800,
                              height: 1.16,
                              letterSpacing: -0.5,
                              color: starlight,
                            ),
                          ),
                        ),
                        RiseIn(
                          visible: _title2,
                          duration: const Duration(milliseconds: 700),
                          child: ShaderMask(
                            shaderCallback: (rect) => const LinearGradient(
                              colors: [Color(0xFFFFD166), AppColors.starGold, Color(0xFFCC8D00)],
                            ).createShader(rect),
                            child: Text(
                              l10n.introHeroTitleLine2,
                              style: const TextStyle(
                                fontSize: 35,
                                fontWeight: FontWeight.w800,
                                height: 1.16,
                                letterSpacing: -0.5,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        RiseIn(
                          visible: _subtitle,
                          duration: const Duration(milliseconds: 700),
                          child: Text(
                            l10n.introHeroSubtitle,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                              color: starlight,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

                // --- 全端末・OS（iOS/Android）で完全同一パーセンテージ（77-80%位置）に固定配置されるイコライザー ---
                Positioned(
                  top: constraints.maxHeight * 0.67 - 32,
                  left: 26,
                  right: 26,
                  height: 64,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: _RecordingStyleWaveform(grown: _barsGrown),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// RecordingPage の AudioWaveformVisualizer とデザイン・描画アルゴリズムを共有し、
/// 灰色から輝くウォームゴールドへとゆったり優雅に立ち上がるイコライザー
class _RecordingStyleWaveform extends StatefulWidget {
  const _RecordingStyleWaveform({required this.grown});
  final bool grown;

  @override
  State<_RecordingStyleWaveform> createState() => _RecordingStyleWaveformState();
}

class _RecordingStyleWaveformState extends State<_RecordingStyleWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  static const _count = 25;
  late final List<double> _baseLevels;

  @override
  void initState() {
    super.initState();
    final rand = math.Random(12);
    _baseLevels = List.generate(_count, (i) {
      final center = 1.0 - (i - _count / 2).abs() / (_count / 2);
      return (0.2 + center * 0.65 + rand.nextDouble() * 0.15).clamp(0.1, 1.0);
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: widget.grown ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 1600),
      curve: Curves.easeInOutCubic,
      builder: (context, grownFactor, child) {
        return AnimatedBuilder(
          animation: _animController,
          builder: (context, child) {
            return CustomPaint(
              size: Size.infinite,
              painter: _RecordingWavePainter(
                baseLevels: _baseLevels,
                grownFactor: grownFactor,
                animValue: _animController.value,
              ),
            );
          },
        );
      },
    );
  }
}

class _RecordingWavePainter extends CustomPainter {
  _RecordingWavePainter({
    required this.baseLevels,
    required this.grownFactor,
    required this.animValue,
  });

  final List<double> baseLevels;
  final double grownFactor; // 0.0(灰色・静止) ➔ 1.0(金色・波打ち)
  final double animValue;

  @override
  void paint(Canvas canvas, Size size) {
    if (baseLevels.isEmpty) return;

    final count = baseLevels.length;
    final totalSpacing = size.width * 0.35;
    final barWidth = (size.width - totalSpacing) / count;
    final spacing = totalSpacing / (count - 1);
    final centerY = size.height / 2;

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    for (int i = 0; i < count; i++) {
      final x = i * (barWidth + spacing) + (barWidth / 2);
      final normalizedIndex = (i - count / 2).abs() / (count / 2);
      final envelope = math.sin((1.0 - normalizedIndex) * math.pi / 2);

      final baseLevel = baseLevels[i];
      final waveModifier = math.sin(animValue * 2 * math.pi + i * 0.4) * 0.15;
      final activeLevel = (baseLevel + waveModifier).clamp(0.08, 1.0);

      // 灰色(0.05)から活発な音量レベル(activeLevel)へ滑らかに補間
      final currentLevel = ui.lerpDouble(0.05, activeLevel, grownFactor)!;
      final barHeight = math.max(6.0, size.height * currentLevel * envelope);

      // 色: シックな灰色 ➔ 輝くウォームゴールドへ優雅に補間
      final dullColor = AppColors.universe.textComet.withValues(alpha: 0.35);
      final hue = 42.0 + (activeLevel * 10);
      final goldColor = HSLColor.fromAHSL(
        (0.5 + activeLevel * 0.5).clamp(0.0, 1.0),
        hue,
        0.9,
        0.6,
      ).toColor();

      final barColor = Color.lerp(dullColor, goldColor, grownFactor)!;
      paint.color = barColor;

      // 金色化が進んだ(grownFactor > 0.3)場合に発光グロー効果を追加
      if (grownFactor > 0.3 && currentLevel > 0.3) {
        final glowPaint = Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = barWidth * 1.5
          ..color = AppColors.starGold.withValues(alpha: (grownFactor * currentLevel * 0.3).clamp(0.0, 0.4))
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
  bool shouldRepaint(covariant _RecordingWavePainter oldDelegate) => true;
}

// ---------------------------------------------------------------------------
// Cosmic Toybox: 3Dクレイアセット 玩具箱から飛び出し浮遊演出
// ---------------------------------------------------------------------------

/// 銀河の中心から 6つの 3D クレイアセットが弾け飛び出し、
/// 宇宙無重力空間でゆらゆらと優雅に漂うアニメーションウィジェット。
class _ToyboxPopBurst extends StatefulWidget {
  const _ToyboxPopBurst({required this.visible});
  final bool visible;

  @override
  State<_ToyboxPopBurst> createState() => _ToyboxPopBurstState();
}

/// 各オブジェクトの配置パラメーター
class _ToyItem {
  const _ToyItem({
    required this.asset,
    required this.size,
    required this.angle,      // 放射方向 (radians)
    required this.distance,   // 中心からの距離 (fraction of screen height)
    required this.floatAmp,   // 上下浮遊幅 (px)
    required this.floatSpeed, // 浮遊周期の比率
    required this.floatPhase, // 位相オフセット (radians)
    required this.tiltAngle,  // 軽いZ軸傾き (radians)
    required this.glowColor,  // ソフトグロー色
    required this.popDelay,   // 飛び出し遅延 (ms)
  });

  final String asset;
  final double size;
  final double angle;
  final double distance;
  final double floatAmp;
  final double floatSpeed;
  final double floatPhase;
  final double tiltAngle;
  final Color glowColor;
  final int popDelay;
}

const _toys = [
  _ToyItem(
    asset: 'assets/images/intro/clay_rocket.png',
    size: 102,  // ロケット: 上左方向（位置を上に上げる）
    angle: -0.60 * math.pi,
    distance: 0.2,
    floatAmp: 12,
    floatSpeed: 1.0,
    floatPhase: 0.0,
    tiltAngle: -0.3,
    glowColor: Color(0xFFFF8C42),
    popDelay: 0,
  ),
  _ToyItem(
    asset: 'assets/images/intro/clay_headphones.png',
    size: 92,  // ヘッドフォン: 右上
    angle: -0.08 * math.pi,
    distance: 0.18,
    floatAmp: 10,
    floatSpeed: 1.0,
    floatPhase: 1.1,
    tiltAngle: 0.25,
    glowColor: Color(0xFFB388FF),
    popDelay: 80,
  ),
  _ToyItem(
    asset: 'assets/images/intro/clay_suitcase.png',
    size: 94,  // スーツケース: 右下
    angle: 0.30 * math.pi,
    distance: 0.21,
    floatAmp: 11,
    floatSpeed: 1.0,
    floatPhase: 2.0,
    tiltAngle: 0.18,
    glowColor: Color(0xFF80CBC4),
    popDelay: 140,
  ),
  _ToyItem(
    asset: 'assets/images/intro/clay_dog.png',
    size: 98,  // 犬: 下中央
    angle: 0.75 * math.pi,
    distance: 0.23,
    floatAmp: 9,
    floatSpeed: 1.0,
    floatPhase: 0.7,
    tiltAngle: -0.12,
    glowColor: Color(0xFFFFCC80),
    popDelay: 200,
  ),
  _ToyItem(
    asset: 'assets/images/intro/clay_coffee.png',
    size: 84,  // コーヒー: 左下方向（位置を下に下げる）
    angle: -0.85 * math.pi,
    distance: 0.20,
    floatAmp: 13,
    floatSpeed: 1.0,
    floatPhase: 3.2,
    tiltAngle: 0.35,
    glowColor: Color(0xFFBCAAA4),
    popDelay: 260,
  ),
  _ToyItem(
    asset: 'assets/images/intro/clay_camera.png',
    size: 90,  // カメラ: 中央上
    angle: -0.30 * math.pi,
    distance: 0.20,
    floatAmp: 10,
    floatSpeed: 1.0,
    floatPhase: 1.8,
    tiltAngle: -0.22,
    glowColor: Color(0xFF4DD0E1),
    popDelay: 320,
  ),
];

class _ToyboxPopBurstState extends State<_ToyboxPopBurst>
    with SingleTickerProviderStateMixin {
  // 浮遊アニメーション用の連続ティッカー
  late final AnimationController _floatController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  // 各アイテムの「飛び出し完了」フラグ (popDelay 後に true になる)
  final List<bool> _popped = List.filled(_toys.length, false);
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _ToyboxPopBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _startPops();
    }
  }

  void _startPops() {
    for (int i = 0; i < _toys.length; i++) {
      final idx = i;
      _timers.add(Timer(Duration(milliseconds: _toys[idx].popDelay), () {
        if (mounted) setState(() => _popped[idx] = true);
      }));
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _floatController,
      builder: (context, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final cx = constraints.maxWidth / 2;
            final cy = constraints.maxHeight / 2;

            return Stack(
              children: [
                for (int i = 0; i < _toys.length; i++)
                  _buildToy(i, cx, cy, constraints.maxHeight, constraints.maxWidth),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildToy(int i, double cx, double cy, double screenH, double screenW) {
    final toy = _toys[i];
    final popped = _popped[i];

    // スマホ標準幅（390px）を基準にし、iPad等の大画面でアセットサイズ・配置半径をスケールさせる
    final scale = (math.min(screenW, screenH * 0.8) / 390.0).clamp(1.0, 1.45);
    final toySize = toy.size * scale;

    // サイン波で上下にゆらゆら浮遊
    final floatY = math.sin(
          _floatController.value * 2 * math.pi * toy.floatSpeed + toy.floatPhase,
        ) *
        (toy.floatAmp * scale);

    // バースト原点をタイトルの真下（画面中央より少し下）へシフト
    // → 上から約62%の高さを中心にオブジェクトが散らばる
    final originY = cy + screenH * 0.12;

    // 最終的な配置座標（中心から放射状）
    final dist = screenH * toy.distance * scale;
    final dx = math.cos(toy.angle) * dist;
    final dy = math.sin(toy.angle) * dist;

    final left = cx + dx - toySize / 2;
    final top = originY + dy - toySize / 2 + floatY;

    return Positioned(
      left: left,
      top: top,
      width: toySize,
      height: toySize,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: popped ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 700),
        curve: Curves.elasticOut,
        builder: (context, popScale, child) {
          return Opacity(
            opacity: popScale.clamp(0.0, 1.0),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..rotateZ(toy.tiltAngle +
                    math.sin(_floatController.value * 2 * math.pi * 1.0 + toy.floatPhase) * 0.10)
                ..scaleByDouble(popScale, popScale, 1.0, 1.0),
              child: child,
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: toy.glowColor.withValues(alpha: 0.4),
                blurRadius: 28,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Image.asset(
            toy.asset,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
