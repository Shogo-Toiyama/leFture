// lib/presentation/pages/onboarding/widgets/onboarding_done_step.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/introduction/widgets/intro_reveal.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// Final onboarding step. Leads straight into the Profile → Course →
/// Lecture checklist on the empty home screen, where the profile is
/// actually filled in.
///
/// The success mark lands with the same "impact" beat as the WelcomePage
/// wordmark animation (`_BurstPainter` in welcome_page.dart) — a flash,
/// a couple of shockwave rings, and a scatter of particles — just recolored
/// green and played once, rather than that page's endless gold pulse/glow.
class OnboardingDoneStep extends StatefulWidget {
  const OnboardingDoneStep({super.key, required this.onFinish});

  final VoidCallback onFinish;

  @override
  State<OnboardingDoneStep> createState() => _OnboardingDoneStepState();
}

class _OnboardingDoneStepState extends State<OnboardingDoneStep> {
  bool _mark = false;
  bool _title = false;
  bool _subtitle = false;
  bool _button = false;
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    _after(120, () => _mark = true);
    _after(520, () => _title = true);
    _after(660, () => _subtitle = true);
    _after(860, () => _button = true);
  }

  void _after(int ms, VoidCallback apply) {
    _timers.add(Timer(Duration(milliseconds: ms), () {
      if (mounted) setState(apply);
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
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        const Spacer(),
        _CheckmarkImpact(visible: _mark),
        const SizedBox(height: 24),
        RiseIn(
          visible: _title,
          duration: const Duration(milliseconds: 600),
          child: Text(
            l10n.onboardingDoneTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.universe.textStarlight,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        RiseIn(
          visible: _subtitle,
          duration: const Duration(milliseconds: 600),
          child: Text(
            l10n.onboardingDoneSubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.universe.textComet, fontSize: 14, height: 1.4),
          ),
        ),
        const Spacer(),
        RiseIn(
          visible: _button,
          duration: const Duration(milliseconds: 650),
          child: _PulsingGoldButton(
            label: l10n.onboardingGetStartedButton,
            onPressed: widget.onFinish,
          ),
        ),
      ],
    );
  }
}

/// 成功マーク本体 + その周りで一度だけ弾ける緑の衝撃波・フラッシュ・粒子。
/// [visible]が最初にtrueになった瞬間、マーク自体の`elasticOut`バウンドと
/// バーストを同時に開始する — 別々のタイマーで駆動すると、バーストだけ
/// マークがまだ透明なうちに再生し終わってしまい、見た目上何も起きて
/// いないように見えるので、必ず同じトリガーで揃える。
class _CheckmarkImpact extends StatefulWidget {
  const _CheckmarkImpact({required this.visible});

  final bool visible;

  @override
  State<_CheckmarkImpact> createState() => _CheckmarkImpactState();
}

class _CheckmarkImpactState extends State<_CheckmarkImpact>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burstController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final List<_BurstParticle> _particles = _generateParticles();
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _maybeFire();
  }

  @override
  void didUpdateWidget(covariant _CheckmarkImpact oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeFire();
  }

  void _maybeFire() {
    if (widget.visible && !_fired) {
      _fired = true;
      _burstController.forward();
    }
  }

  @override
  void dispose() {
    _burstController.dispose();
    super.dispose();
  }

  List<_BurstParticle> _generateParticles() {
    final rand = math.Random();
    return List.generate(30, (i) {
      return _BurstParticle(
        angle: rand.nextDouble() * math.pi * 2,
        distance: 55 + rand.nextDouble() * 95,
        size: 2.2 + rand.nextDouble() * 3.4,
        delay: rand.nextDouble() * 0.12,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _burstController,
      builder: (context, child) {
        return SizedBox(
          width: 260,
          height: 260,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(260, 260),
                painter: _GreenBurstPainter(
                  progress: _burstController.value,
                  particles: _particles,
                ),
              ),
              child!,
            ],
          ),
        );
      },
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        child: AnimatedScale(
          scale: widget.visible ? 1 : 0.4,
          duration: const Duration(milliseconds: 700),
          curve: Curves.elasticOut,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.growthGreen.withValues(alpha: 0.15),
              border: Border.all(color: AppColors.growthGreen.withValues(alpha: 0.4)),
            ),
            child: const Icon(Icons.check_rounded, color: AppColors.growthGreen, size: 36),
          ),
        ),
      ),
    );
  }
}

class _BurstParticle {
  const _BurstParticle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.delay,
  });
  final double angle;
  final double distance;
  final double size;
  final double delay; // 0..1、バースト全体に対する開始遅延
}

/// WelcomePageの`_BurstPainter`と同じ「フラッシュ→衝撃波→粒子」の三段構成を、
/// 緑基調・一発限りの短い尺で再現する。
class _GreenBurstPainter extends CustomPainter {
  _GreenBurstPainter({required this.progress, required this.particles});
  final double progress; // 0..1
  final List<_BurstParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    _paintFlash(canvas, center);
    _paintShockwaves(canvas, center);
    _paintParticles(canvas, center);
  }

  void _paintFlash(Canvas canvas, Offset center) {
    final t = (progress / 0.32).clamp(0.0, 1.0);
    if (t >= 1.0) return;
    final opacity = t < 0.3 ? t / 0.3 : 1 - ((t - 0.3) / 0.7);
    final radius = ui.lerpDouble(10, 95, Curves.easeOut.transform(t))!;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.9 * opacity.clamp(0.0, 1.0)),
          AppColors.growthGreen.withValues(alpha: 0.5 * opacity.clamp(0.0, 1.0)),
          AppColors.growthGreen.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.38, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  void _paintShockwaves(Canvas canvas, Offset center) {
    for (final delay in [0.0, 0.1]) {
      final t = ((progress - delay) / 0.58).clamp(0.0, 1.0);
      if (progress < delay || t >= 1.0) continue;
      final eased = Curves.easeOut.transform(t);
      final radius = ui.lerpDouble(34, 128, eased)!;
      final opacity = 1 - eased;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ui.lerpDouble(3.2, 0.5, eased)!
        ..color = AppColors.growthGreen.withValues(alpha: 0.85 * opacity);
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _paintParticles(Canvas canvas, Offset center) {
    for (final p in particles) {
      final local = ((progress - p.delay) / 0.62).clamp(0.0, 1.0);
      if (progress < p.delay) continue;
      final eased = Curves.easeOut.transform(local);
      final dist = p.distance * eased;
      final opacity = local < 0.15 ? local / 0.15 : 1 - ((local - 0.15) / 0.85);
      if (opacity <= 0) continue;
      final offset = center + Offset(math.cos(p.angle) * dist, math.sin(p.angle) * dist);
      final color = eased < 0.45 ? Colors.white : AppColors.growthGreen;
      final paint = Paint()
        ..color = color.withValues(alpha: opacity.clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 0.5);
      canvas.drawCircle(offset, (p.size * (1 - local * 0.3)) / 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GreenBurstPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Introduction CTAスライドの`_PrimaryButton`と同じ、じわっと脈打つ
/// グロー付きゴールドボタン。オンボーディングの締めくくりに使う。
class _PulsingGoldButton extends StatefulWidget {
  const _PulsingGoldButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_PulsingGoldButton> createState() => _PulsingGoldButtonState();
}

class _PulsingGoldButtonState extends State<_PulsingGoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        final glow = Curves.easeInOut.transform(_glowController.value);
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.starGold.withValues(alpha: 0.5 + glow * 0.35),
                blurRadius: 20 + glow * 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        );
      },
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.starGold,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          onPressed: widget.onPressed,
          child: Text(widget.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ),
    );
  }
}
