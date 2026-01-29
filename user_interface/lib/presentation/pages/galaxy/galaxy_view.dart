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
  late final List<_NebulaPuff> nebula;
  late final List<_BgStar> bgStars;
  double t = 0.0;


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

    final seed = 42;
    final count = 2000;
    final arms = 3;
    final radius = 1.0;
    final thickness = 0.05;

    stars = _generateSpiralGalaxy(
      seed: seed,
      count: count, // <- まず固定（引きで銀河っぽくするなら 10k〜30k 推奨）
      arms: arms,  
      radius: radius,
      thickness: thickness,
    );

    nebula = _generateNebula(
      seed: seed,
      count: (count/500).toInt(),
      arms: arms,
      radius: radius*0.8,
      thickness: thickness,
    );

    bgStars = _generateBgStars(
      seed: 123,
      count: 3200,
    );


    _ticker = AnimationController(vsync: this, duration: const Duration(days: 99))
      ..addListener(() {
        t += 1 / 60;
        if (!userInteracting) {
        const spin = 0.002; // 好みで
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {

        return GestureDetector(
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
              nebula: nebula,
              bgStars: bgStars,
              time: t,
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

class _NebulaPuff {
  _NebulaPuff({
    required this.pos,
    required this.radius,
    required this.alpha,
    required this.colorIndex,
  });

  final v.Vector3 pos;      // 銀河ローカル座標
  final double radius;      // 画面上の基準半径（あとでdepth/zoomで調整）
  final double alpha;       // 0..1
  final int colorIndex;     // 色選択用
}

class _BgStar {
  _BgStar(this.x01, this.y01, this.r, this.baseA, this.phase, this.speed);
  final double x01;   // 0..1
  final double y01;   // 0..1
  final double r;     // px
  final double baseA; // 0..1
  final double phase; // 0..2pi
  final double speed; // 0..?
}

List<_BgStar> _generateBgStars({required int seed, required int count}) {
  final rnd = math.Random(seed);
  final stars = <_BgStar>[];

  for (int i = 0; i < count; i++) {
    final x = rnd.nextDouble();
    final y = rnd.nextDouble();

    // ✅ ほぼ極小（0.25〜1.2pxくらいに集中）
    final r = (0.25 + math.pow(rnd.nextDouble(), 3.4) * 1.2).toDouble();

    // ✅ ほぼ薄い（たまに少し明るい）
    final baseA = (0.12 + math.pow(rnd.nextDouble(), 2.5) * 0.80).toDouble();

    // ちらつき用
    final phase = rnd.nextDouble() * 2 * math.pi;
    final speed = 0.6 + rnd.nextDouble() * 1.4; // 0.6..2.0

    stars.add(_BgStar(x, y, r, baseA, phase, speed));
  }
  return stars;
}



class _GalaxyPainter extends CustomPainter {
  _GalaxyPainter({
    required this.stars,
    required this.nebula,
    required this.bgStars,
    required this.time,
    required this.camRot,
    required this.zoom,
    required this.onProjected,
  });

  final List<_Star> stars;
  final List<_NebulaPuff> nebula;
  final List<_BgStar> bgStars;
  final double time;
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
    const minZoom = 0.6;
    const maxZoom = 8.0;
    final z01 = ((zoom - minZoom) / (maxZoom - minZoom)).clamp(0.0, 1.0).toDouble();

    // --- Background stars (dense + tiny + twinkle) ---
    final bgPaint = Paint()..blendMode = BlendMode.srcOver;

    final avoidR = math.min(size.width, size.height) * 0.14; // 0.22→0.14（抑制範囲を狭く）


    for (final s in bgStars) {
      final x = s.x01 * size.width;
      final y = s.y01 * size.height;

      // avoid center (don’t fight the galaxy)
      final dx = x - center.dx;
      final dy = y - center.dy;
      final dist2 = dx * dx + dy * dy;
      final avoid = (dist2 / (avoidR * avoidR)).clamp(0.55, 1.0).toDouble(); // 0.25→0.55

      // ✅ ここ重要：s.a じゃなく s.baseA
      final a = (s.baseA * avoid).clamp(0.01, 0.28);
      bgPaint.color = const Color(0xFFFFFFFF).withValues(alpha: a);
      canvas.drawCircle(Offset(x, y), s.r, bgPaint);

    }

    // --- center glow (cheap, effective) ---
    final haze = 1.35 - 0.55 * z01;
    final coreRadius = math.min(size.width, size.height) * 0.18 * zoom * haze;

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0xE6D8F3FF),
          Color(0x7A6BCBFF),
          Color(0x001E1B2E),
        ],
        stops: const [0.0, 0.15, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius));

    canvas.drawCircle(center, coreRadius, glowPaint);


    final warmCore = Paint()
      ..blendMode = BlendMode.screen
      ..shader = RadialGradient(
        colors: [
          const Color(0x66FFB26B),
          const Color(0x33FF4FA2),
          const Color(0x00FF4FA2),
        ],
        stops: const [0.0, 0.3, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius * 0.55));

    canvas.drawCircle(center, coreRadius * 0.55, warmCore);

    // Build rotation matrix from yaw/pitch
    final rot = v.Matrix4.identity()..setRotation(camRot.asRotationMatrix());

    // Simple perspective projection params
    final double fov = 1.2; // smaller = more zoomed perspective
    final double scale = math.min(size.width, size.height) * 0.38 * zoom;

    // Project + depth sort (optional)
    final List<_ProjectedStar> proj = [];
    proj.length = 0;

    // --- Nebula layer ---
    final nebulaColors = <Color>[
      const Color(0xFFFF5FA2), // pink
      const Color(0xFFFF9A3D), // orange
      const Color(0xFFB86BFF), // purple
      const Color(0xFF4FA8FF), // blue
    ];

    // ズームアウトは薄く・減らす
    final zoomFade = (0.55 + 0.65 * math.pow(z01, 1.2)).toDouble(); // 引きでかなり薄い
    // final stride = (z01 < 0.5) ? (1/(z01+0.05)).toInt().clamp(1, 12) : 1;          // 引きは描画数も減らす

    for (int i = 0; i < nebula.length; i += 1) {
      final puff = nebula[i];

      final p = puff.pos;
      final v4 = rot.transform(v.Vector4(p.x, p.y, p.z, 1.0));

      final z = v4.z + 2.5;
      if (z <= 0.2) continue;

      final x2 = (v4.x / (z * fov)) * scale + center.dx;
      final y2 = (v4.y / (z * fov)) * scale + center.dy;

      if (x2 < -120 || x2 > size.width + 120 || y2 < -120 || y2 > size.height + 120) continue;

      // ✅ ズームアウトほど「小さく」する（ポイント）
      final sizeFade = (0.55 + 0.45 * z01).toDouble();
      final rPx = (((puff.radius / z) * 2.4) * sizeFade).clamp(10.0, 120.0);
      if (rPx < 2.0) continue;

      final c = nebulaColors[puff.colorIndex];

      // ✅ ズームアウトほど「薄く」
      final a = (puff.alpha * zoomFade).clamp(0.01, 1);

      final paint = Paint()
        ..blendMode = BlendMode.screen
        ..shader = RadialGradient(
          colors: [
            c.withValues(alpha: a * 0.70), // 中心は薄め
            c.withValues(alpha: a * 0.35),
            c.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(x2, y2), radius: rPx));

      canvas.drawCircle(Offset(x2, y2), rPx, paint);
    }

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
  }

  @override
  bool shouldRepaint(covariant _GalaxyPainter oldDelegate) {
    return oldDelegate.camRot != camRot || oldDelegate.zoom != zoom || oldDelegate.stars != stars || oldDelegate.nebula != nebula;
  }
}

List<_Star> _generateSpiralGalaxy({
  required int seed,
  required int count,
  required int arms,
  required double radius,
  required double thickness,

  int bulgeCount = 8000,
  double bulgeRadiusNorm = 0.18,
  double innerDiskHoleNorm = 0.14,
}) {

  final rnd = math.Random(seed);

  double randNorm() {
    // Box-Muller
    final u1 = math.max(rnd.nextDouble(), 1e-9);
    final u2 = rnd.nextDouble();
    return math.sqrt(-2.0 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  final stars = <_Star>[];

  // --- Bulge: dense central spheroid ---
  for (int i = 0; i < bulgeCount; i++) {
    // 0..1 (中心に強く寄せる)
    final u = math.pow(rnd.nextDouble(), 2.8).toDouble();
    final r = radius * bulgeRadiusNorm * u;

    // 等方的に球っぽく
    final theta = math.acos(2 * rnd.nextDouble() - 1); // 0..pi
    final phi = rnd.nextDouble() * 2 * math.pi;

    // バルジは少し縦に潰す（楕円体っぽく）
    final flatten = 0.75;

    final x = r * math.sin(theta) * math.cos(phi);
    final y = r * math.sin(theta) * math.sin(phi);
    final z = r * math.cos(theta) * flatten;

    // バルジの星の明るさとサイズ
    final bright = (0.35 + 0.65 * math.pow(1 - u, 0.7) + rnd.nextDouble() * 0.15)
        .clamp(0.0, 1.0)
        .toDouble();

    final size = (0.5 + bright * 0.9 + rnd.nextDouble() * 0.35);

    // 色は白〜黄寄りが多い（古い星の雰囲気）
    final p = rnd.nextDouble();
    final type = (p < 0.55) ? 2 : (p < 0.95) ? 0 : 1;

    stars.add(_Star(
      id: "bulge_$i",
      pos: v.Vector3(x, z, y),
      size: size,
      bright: bright,
      type: type,
    ));
  }

  stars.reserveCapacity(count);

  for (int i = 0; i < count; i++) {
    // r: bias towards center (more dense core)
    final t = rnd.nextDouble();
    // final rNorm = math.pow(t, 0.85).toDouble();
    // final r = radius * rNorm;
    final rNormRaw = math.pow(t, 0.85).toDouble(); // 0..1
    final rNorm = innerDiskHoleNorm + (1.0 - innerDiskHoleNorm) * rNormRaw; // hole..1
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

List<_NebulaPuff> _generateNebula({
  required int seed,
  required int count,       // 例: 400
  required int arms,        // starsと同じ
  required double radius,   // starsと同じ
  required double thickness,
  double innerStartNorm = 0.10, // 中心は濃いけど、腕のモヤは少し外から
}) {
  final rnd = math.Random(seed + 999);

  double randNorm() {
    final u1 = math.max(rnd.nextDouble(), 1e-9);
    final u2 = rnd.nextDouble();
    return math.sqrt(-2.0 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  final puffs = <_NebulaPuff>[];

  for (int i = 0; i < count; i++) {
    // 腕に沿う半径（中心寄り多め）
    final t = rnd.nextDouble();
    final rNormRaw = math.pow(t, 0.55).toDouble(); // 0..1（中心寄り）
    final rNorm = innerStartNorm + (1 - innerStartNorm) * rNormRaw;
    final r = radius * rNorm;

    // 腕を選ぶ
    final arm = rnd.nextInt(arms);
    final baseAngle = (arm / arms) * 2 * math.pi;

    // 腕に沿って巻く
    final spiralTightness = 5.0;
    final angleNoise = 0.12 + 0.40 * rNorm; // 外側ほど広がる
    final angle = baseAngle + r * spiralTightness + randNorm() * angleNoise;

    // 腕の幅（位置ノイズ）
    final posNoise = 0.015 + 0.06 * rNorm;
    final x = r * math.cos(angle) + randNorm() * posNoise;
    final y = r * math.sin(angle) + randNorm() * posNoise;
    final z = randNorm() * thickness * (0.4 + 0.8 * (1 - rNorm)); // 中心ほど厚い

    // puffの大きさ（外側ほど大きく、薄く）
    final baseR = 14.0 + 38.0 * rNorm; // px
    final alpha = (0.10 + 0.22 * (1 - rNorm) + rnd.nextDouble() * 0.08).clamp(0.04, 0.32);

    // 色：ピンク/オレンジ/紫/青を混ぜる
    final p = rnd.nextDouble();
    final colorIndex = (p < 0.45) ? 0 : (p < 0.75) ? 1 : (p < 0.92) ? 2 : 3;

    puffs.add(_NebulaPuff(
      pos: v.Vector3(x, z, y),
      radius: baseR * (0.7 + rnd.nextDouble() * 0.9),
      alpha: alpha.toDouble(),
      colorIndex: colorIndex,
    ));
  }

  return puffs;
}


extension<T> on List<T> {
  void reserveCapacity(int n) {
    // no-op in Dart, but kept for clarity
  }
}
