// lib/presentation/pages/introduction/widgets/intro_particle_field.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// Introductionスライドの背景で常時漂う星屑に加えて、スライドごとに
/// 「弾ける(burst)」「中心へ収束する(converge)」演出を出し分けるための
/// 常駐パーティクルフィールド。[IntroParticleFieldState.spawnBurst]を
/// [GlobalKey]経由で呼ぶことで、任意のタイミング・任意の位置から
/// 星を弾けさせられる。
enum IntroParticleMode { ambient, converge }

class IntroParticleField extends StatefulWidget {
  const IntroParticleField({super.key, required this.mode});
  final IntroParticleMode mode;

  @override
  State<IntroParticleField> createState() => IntroParticleFieldState();
}

class IntroParticleFieldState extends State<IntroParticleField>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  final List<_Star> _stars = [];
  final List<_Burst> _bursts = [];
  final List<_Converge> _converge = [];

  Size _size = Size.zero;
  final _rand = math.Random();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant IntroParticleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mode == IntroParticleMode.converge &&
        oldWidget.mode != IntroParticleMode.converge) {
      _seedConverge();
    } else if (widget.mode != IntroParticleMode.converge) {
      _converge.clear();
    }
  }

  @override
  void dispose() {
    _convergeStopTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dtMs = (elapsed - _lastTick).inMilliseconds.clamp(0, 48);
    _lastTick = elapsed;
    if (_size == Size.zero) return;
    setState(() => _step(dtMs / 16.0)); // 16ms(≈60fps)を1ステップとして正規化
  }

  void _ensureStars() {
    if (_stars.isNotEmpty || _size == Size.zero) return;
    final count = (_size.width * _size.height / 2600).round();
    for (var i = 0; i < count; i++) {
      _stars.add(_Star(
        x: _rand.nextDouble() * _size.width,
        y: _rand.nextDouble() * _size.height,
        r: _rand.nextDouble() * 1.6 + 0.5,
        baseAlpha: _rand.nextDouble() * 0.55 + 0.35,
        twinkle: _rand.nextDouble() * 0.05 + 0.01,
        phase: _rand.nextDouble() * math.pi * 2,
        fallSpeed: _rand.nextDouble() * 0.16 + 0.06,
      ));
    }
  }

  Timer? _convergeStopTimer;

  void _seedConverge() {
    _convergeStopTimer?.cancel();
    _converge
      ..clear()
      ..addAll(List.generate(70, (_) => _newConverge()));

    // 最初のアニメーション期間(1400ms)だけクルッと回転・収束し、その後は星が静止して定着する
    _convergeStopTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() {
        for (final c in _converge) {
          c.spin = 0;
          c.pull = 0;
        }
      });
    });
  }

  _Converge _newConverge() {
    return _Converge(
      angle: _rand.nextDouble() * math.pi * 2,
      radius: math.max(_size.width, _size.height) * (0.5 + _rand.nextDouble() * 0.4),
      spin: (_rand.nextDouble() * 0.018 + 0.01) * (_rand.nextBool() ? 1 : -1),
      pull: _rand.nextDouble() * 0.7 + 0.45,
      r: _rand.nextDouble() * 1.8 + 0.6,
      color: _randomColor(),
      alpha: _rand.nextDouble() * 0.5 + 0.3,
    );
  }

  Color _randomColor() {
    const palette = [
      AppColors.starGold,
      Color(0xFFFFD166),
      Colors.white,
      Color(0xFF4AA8FF),
      Color(0xFFB98BFF),
    ];
    return palette[_rand.nextInt(palette.length)];
  }

  /// [originFraction]（0..1、このフィールドのサイズに対する割合）を起点に
  /// 星を四方へ弾けさせる。Hero スライドの「退屈な波形→賑やかな銀河」の
  /// 瞬間に呼ぶ想定。
  void spawnBurst(Offset originFraction, {int count = 90}) {
    if (_size == Size.zero) return;
    final origin = Offset(
      originFraction.dx * _size.width,
      originFraction.dy * _size.height,
    );
    for (var i = 0; i < count; i++) {
      final angle = -math.pi / 2 + (_rand.nextDouble() - 0.5) * math.pi * 1.5;
      final speed = _rand.nextDouble() * 3.4 + 1.2;
      _bursts.add(_Burst(
        x: origin.dx + (_rand.nextDouble() - 0.5) * 60,
        y: origin.dy,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed - 0.8,
        life: 1,
        decay: _rand.nextDouble() * 0.012 + 0.007,
        r: _rand.nextDouble() * 2.2 + 0.8,
        color: _randomColor(),
      ));
    }
  }

  void _step(double dt) {
    for (final s in _stars) {
      s.phase += s.twinkle * dt;
      s.y -= s.fallSpeed * dt;
      if (s.y < 0) s.y = _size.height;
    }

    for (final b in _bursts) {
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      b.vy += 0.045 * dt;
      b.vx *= math.pow(0.99, dt).toDouble();
      b.life -= b.decay * dt;
    }
    _bursts.removeWhere((b) => b.life <= 0);

    if (widget.mode == IntroParticleMode.converge) {
      final cx = _size.width / 2;
      final cy = _size.height / 2 - _size.height * 0.08;
      for (var i = 0; i < _converge.length; i++) {
        final c = _converge[i];
        c.angle += c.spin * dt;
        c.radius -= c.pull * dt;
        if (c.radius < 6) _converge[i] = _newConverge();
        c.cx = cx;
        c.cy = cy;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size != _size && size.width > 0 && size.height > 0) {
          _size = size;
          _stars.clear();
          _ensureStars();
          if (widget.mode == IntroParticleMode.converge) _seedConverge();
        }
        return CustomPaint(
          size: size,
          painter: _FieldPainter(
            stars: _stars,
            bursts: _bursts,
            converge: widget.mode == IntroParticleMode.converge ? _converge : const [],
          ),
        );
      },
    );
  }
}

class _Star {
  _Star({
    required this.x,
    required this.y,
    required this.r,
    required this.baseAlpha,
    required this.twinkle,
    required this.phase,
    required this.fallSpeed,
  });
  double x, y;
  final double r;
  final double baseAlpha;
  final double twinkle;
  double phase;
  final double fallSpeed;
}

class _Burst {
  _Burst({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.decay,
    required this.r,
    required this.color,
  });
  double x, y, vx, vy, life;
  final double decay;
  final double r;
  final Color color;
}

class _Converge {
  _Converge({
    required this.angle,
    required this.radius,
    required this.spin,
    required this.pull,
    required this.r,
    required this.color,
    required this.alpha,
  });
  double angle, radius, spin, pull, cx = 0, cy = 0;
  final double r;
  final Color color;
  final double alpha;
}

class _FieldPainter extends CustomPainter {
  _FieldPainter({required this.stars, required this.bursts, required this.converge});
  final List<_Star> stars;
  final List<_Burst> bursts;
  final List<_Converge> converge;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in stars) {
      final a = s.baseAlpha * (0.55 + 0.45 * math.sin(s.phase));
      canvas.drawCircle(
        Offset(s.x, s.y),
        s.r,
        Paint()..color = AppColors.universe.textStarlight.withValues(alpha: a.clamp(0, 1)),
      );
    }

    for (final b in bursts) {
      if (b.life <= 0) continue;
      final paint = Paint()
        ..color = b.color.withValues(alpha: b.life.clamp(0, 1))
        ..maskFilter = const MaskFilter.blur(ui.BlurStyle.normal, 1.4);
      canvas.drawCircle(Offset(b.x, b.y), b.r * b.life + 0.3, paint);
    }

    if (converge.isNotEmpty) {
      final center = Offset(converge.first.cx, converge.first.cy);
      final glow = Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.starGold.withValues(alpha: 0.22),
            AppColors.starGold.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: 92));
      canvas.drawRect(Offset.zero & size, glow);

      for (final c in converge) {
        final x = c.cx + math.cos(c.angle) * c.radius;
        final y = c.cy + math.sin(c.angle) * c.radius;
        canvas.drawCircle(
          Offset(x, y),
          c.r,
          Paint()
            ..color = c.color.withValues(alpha: c.alpha)
            ..maskFilter = const MaskFilter.blur(ui.BlurStyle.normal, 1.2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FieldPainter oldDelegate) => true;
}
