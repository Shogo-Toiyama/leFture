import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;

class GalaxyView extends StatefulWidget {
  const GalaxyView({super.key});

  @override
  State<GalaxyView> createState() => _GalaxyViewState();
}

class _GalaxyViewState extends State<GalaxyView> with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;

  // Camera / controls
  double zoom = 2.0;    // 0.5..3.0 recommended
  v.Quaternion camRot = v.Quaternion.identity();

  // Stars
  late final List<_Star> stars;
  // Cache projected points for picking
  List<_ProjectedStar> projected = [];

  // Auto rotation
  bool userInteracting = false;

  @override
  void initState() {
    super.initState();

    stars = _generateSpiralGalaxy(
      seed: 42,
      count: 20000, // <- まず固定（引きで銀河っぽくするなら 10k〜30k 推奨）
      arms: 3,
      radius: 1.5,
      thickness: 0.07,
    );

    _ticker = AnimationController(vsync: this, duration: const Duration(days: 99))
      ..addListener(() {
        if (!userInteracting) {
        const spin = 0.001; // 好みで
        final worldUp = v.Vector3(0, 1, 0);
        final q = v.Quaternion.axisAngle(worldUp, spin);
        camRot = q * camRot;
        camRot.normalize();
      }
        setState(() {});
      })
      ..forward();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails d, Size size) {
    // ズームがある程度近い時だけピック
    if (zoom < 6.0) return;

    const double pickPx = 16; // タップ許容半径
    final Offset p = d.localPosition;

    _ProjectedStar? best;
    double bestDist = double.infinity;

    for (final ps in projected) {
      final dx = ps.screen.dx - p.dx;
      final dy = ps.screen.dy - p.dy;
      final dist2 = dx * dx + dy * dy;
      if (dist2 < pickPx * pickPx && dist2 < bestDist) {
        bestDist = dist2;
        best = ps;
      }
    }

    if (best == null) return;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyMedium!,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("⭐️ Star info", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Text("id: ${best?.star.id}"),
              Text("type: ${best?.star.type}"),
              Text("brightness: ${best?.star.bright.toStringAsFixed(3)}"),
              Text("size: ${best?.star.size.toStringAsFixed(3)}"),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);

        return GestureDetector(
          onTapDown: (d) => _onTapDown(d, size),
          onScaleStart: (_) => setState(() => userInteracting = true),
          onScaleEnd: (_) => setState(() => userInteracting = false),
          onScaleUpdate: (d) {
            setState(() {
              // zoom
              const zoomSensitivity = 0.05; // 0.15〜0.35くらいで調整
              final s = math.pow(d.scale, zoomSensitivity).toDouble();
              zoom *= s;
              zoom = zoom.clamp(0.6, 8.0);

              // rotation (camera-relative)
              final dx = d.focalPointDelta.dx;
              final dy = d.focalPointDelta.dy;

              const rotSpeed = 0.005;

              // ① yaw: world up around screen-x drag
              final worldUp = v.Vector3(0, 1, 0);
              final qYaw = v.Quaternion.axisAngle(worldUp, -dx * rotSpeed);

              // ② pitch: camera right around screen-y drag
              // camera right = camRot applied to (1,0,0)
              final camRight = v.Vector3(1, 0, 0);
              camRot.rotate(camRight); // camRight becomes rotated in-place
              final qPitch = v.Quaternion.axisAngle(camRight, -dy * rotSpeed);

              // Apply: pitch then yaw (feel-good order)
              camRot = (qPitch * qYaw) * camRot;
              camRot.normalize();
            });
          },

          child: CustomPaint(
            painter: _GalaxyPainter(
              stars: stars,
              camRot: camRot,
              zoom: zoom,
              onProjected: (list) => projected = list,
            ),
            isComplex: true,
            willChange: true,
          ),
        );
      },
    );
  }
}

class _Star {
  _Star({
    required this.id,
    required this.pos,
    required this.size,
    required this.bright,
    required this.type,
  });

  final String id;
  final v.Vector3 pos;
  final double size;   // base radius in screen pixels after scaling
  final double bright; // 0..1
  final int type;      // color category
}

class _ProjectedStar {
  _ProjectedStar({required this.star, required this.screen, required this.depth});
  final _Star star;
  final Offset screen;
  final double depth; // smaller = closer
}

typedef _ProjectedCallback = void Function(List<_ProjectedStar> list);

class _GalaxyPainter extends CustomPainter {
  _GalaxyPainter({
    required this.stars,
    required this.camRot,
    required this.zoom,
    required this.onProjected,
  });

  final List<_Star> stars;
  final v.Quaternion camRot;
  final double zoom;
  final _ProjectedCallback onProjected;

  @override
  void paint(Canvas canvas, Size size) {
    // background
    final bg = Paint()..color = const Color(0xFF060913);
    canvas.drawRect(Offset.zero & size, bg);

    // center glow (cheap, effective)
    final center = Offset(size.width * 0.5, size.height * 0.52);
    final zoomT = ((zoom - 0.6) / (3.0 - 0.6)).clamp(0.0, 1.0);
    final haze = 1.35 - 0.55 * zoomT; // 引きほど大きく、寄りほど小さく
    final coreRadius = math.min(size.width, size.height) * 0.18 * zoom * haze;

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xE6D8F3FF), // core (強)
          const Color(0x7A6BCBFF), // mid
          const Color(0x001E1B2E), // out
        ],
        stops: const [0.0, 0.18, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius));

    canvas.drawCircle(center, coreRadius, glowPaint);

    // Build rotation matrix from yaw/pitch
    final rot = v.Matrix4.identity()..setRotation(camRot.asRotationMatrix());

    // Simple perspective projection params
    final double fov = 1.2; // smaller = more zoomed perspective
    final double scale = math.min(size.width, size.height) * 0.38 * zoom;

    // Project + depth sort (optional)
    final List<_ProjectedStar> proj = [];
    proj.length = 0;

    for (final s in stars) {
      final p = v.Vector3.copy(s.pos);
      final v4 = rot.transform(v.Vector4(p.x, p.y, p.z, 1.0));

      // camera distance (push galaxy away a bit)
      final z = v4.z + 2.5; // must stay > 0
      if (z <= 0.2) continue;

      // screen projection
      final x2 = (v4.x / (z * fov)) * scale + center.dx;
      final y2 = (v4.y / (z * fov)) * scale + center.dy;

      // screen bounds culling (+margin)
      if (x2 < -40 || x2 > size.width + 40 || y2 < -40 || y2 > size.height + 40) continue;

      proj.add(_ProjectedStar(
        star: s,
        screen: Offset(x2, y2),
        depth: z,
      ));
    }

    // Far to near: draw far first
    proj.sort((a, b) => b.depth.compareTo(a.depth));
    onProjected(proj);

    // Draw stars (use a few paints only)
    final paints = <int, Paint>{
      0: Paint()..color = const Color(0xCCFFFFFF),
      1: Paint()..color = const Color(0xCCB7D8FF),
      2: Paint()..color = const Color(0xCCFFE7B0),
      3: Paint()..color = const Color(0xCCFFB7B7),
    };

    // A tiny trick: far stars smaller/dimmer
    for (final ps in proj) {
      final s = ps.star;
      final depth = ps.depth;

      final zoomT = ((zoom - 0.6) / (3.0 - 0.6)).clamp(0.0, 1.0); // 0..1
      final zoomBoost = 0.55 + 0.95 * math.pow(zoomT, 2.2);       // ズームアウトは抑える
      final sizePx = (s.size / depth) * zoomBoost;

      if (sizePx < 0.25) continue;

      final alpha = (s.bright / math.pow(depth, 0.8)).clamp(0.03, 0.9);
      final base = paints[s.type] ?? paints[0]!;

      final paint = Paint()
        ..color = base.color.withValues(alpha: alpha)
        ..blendMode = base.blendMode
        ..isAntiAlias = base.isAntiAlias;

      canvas.drawCircle(ps.screen, sizePx, paint);
    }

    // optional: subtle dust band (cheap “density feels thicker”)
    final dustPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: const [
          Color(0x001A2C58),
          Color(0x221A2C58),
          Color(0x001A2C58),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCenter(center: center, width: size.width, height: size.height * 0.35));
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(0.0);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawRect(
      Rect.fromCenter(center: center, width: size.width, height: size.height * 0.35),
      dustPaint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GalaxyPainter oldDelegate) {
    return oldDelegate.camRot != camRot || oldDelegate.zoom != zoom || oldDelegate.stars != stars;
  }
}

List<_Star> _generateSpiralGalaxy({
  required int seed,
  required int count,
  required int arms,
  required double radius,
  required double thickness,
}) {
  final rnd = math.Random(seed);

  double randNorm() {
    // Box-Muller
    final u1 = math.max(rnd.nextDouble(), 1e-9);
    final u2 = rnd.nextDouble();
    return math.sqrt(-2.0 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  final stars = <_Star>[];
  stars.reserveCapacity(count);

  for (int i = 0; i < count; i++) {
    // r: bias towards center (more dense core)
    final t = rnd.nextDouble();
    final rNorm = math.pow(t, 0.85).toDouble();
    final r = radius * rNorm;

    // pick arm and angle
    final arm = rnd.nextInt(arms);
    final baseAngle = (arm / arms) * 2 * math.pi;

    // spiral winding: angle increases with radius
    final spiralTightness = 5.0; // bigger = more winding
    final angleNoise = (0.18 + 0.35 * rNorm); // 外側ほど腕が広がる
    final angle = baseAngle + r * spiralTightness + randNorm() * angleNoise;

    // position in disk
    final posNoise = 0.012 + 0.05 * rNorm; // 外側ほど散る
    final x = r * math.cos(angle) + randNorm() * posNoise;
    final y = r * math.sin(angle) + randNorm() * posNoise;

    // thickness (z)
    final z = randNorm() * thickness * (0.6 + 0.8 * (1 - rNorm));

    // star attributes
    final bright = (0.15 + 0.85 * math.pow(1 - rNorm, 1.8) + rnd.nextDouble() * 0.15).clamp(0.0, 1.0);
    final size = (0.6 + bright * 1.8 + rnd.nextDouble() * 0.6);

    // color type distribution
    final p = rnd.nextDouble();
    final type = (p < 0.55) ? 1 : (p < 0.78) ? 0 : (p < 0.93) ? 2 : 3;

    stars.add(_Star(
      id: "s$i",
      pos: v.Vector3(x, z, y), // swap to make disk look nicer in projection
      size: size,
      bright: bright,
      type: type,
    ));
  }

  // Add a few "hero stars" that stand out (for tap interactions)
  for (int i = 0; i < 0; i++) {
    final a = rnd.nextDouble() * 2 * math.pi;

    // 0..1 の正規化半径（外側ほど 1）
    final rNorm = math.pow(rnd.nextDouble(), 0.9).toDouble(); // 分布は好み
    final r = radius * (0.05 + 0.95 * rNorm);

    final x = r * math.cos(a);
    final y = r * math.sin(a);
    final z = randNorm() * thickness * 0.5;

    // 外側ほど小さく、薄く（明るさも少し落とす）
    final edge = rNorm; // 0 center .. 1 edge
    final size = (4.5 * math.pow(1 - edge, 1.2) + 0.8 + rnd.nextDouble() * 0.6).toDouble();
    final bright = (0.95 * math.pow(1 - edge, 0.9) + 0.15).clamp(0.0, 1.0).toDouble();

    stars.add(_Star(
      id: "hero_$i",
      pos: v.Vector3(x, z * 1.4, y),
      size: size,
      bright: bright,
      type: 0,
    ));
  }

  return stars;
}

extension<T> on List<T> {
  void reserveCapacity(int n) {
    // no-op in Dart, but kept for clarity
  }
}
