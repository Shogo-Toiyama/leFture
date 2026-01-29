import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;

final minZoom = 1.0;
final maxZoom = 8.0;

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
    final count = 20000;
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
    
    int frame = 0;

    _ticker = AnimationController(vsync: this, duration: const Duration(days: 99))
      ..addListener(() {
        if ((frame++ & 1) == 1) return;
        t += 1 / 30;
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
              const zoomSensitivity = 0.05;
              final s = math.pow(d.scale, zoomSensitivity).toDouble();
              zoom *= s;
              zoom = zoom.clamp(minZoom, maxZoom);

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
  _BgStar(this.x01, this.y01, this.r, this.baseA);
  final double x01;   // 0..1
  final double y01;   // 0..1
  final double r;     // px
  final double baseA; // 0..1
}

List<_BgStar> _generateBgStars({required int seed, required int count}) {
  final rnd = math.Random(seed);
  final stars = <_BgStar>[];

  for (int i = 0; i < count; i++) {
    final x = rnd.nextDouble();
    final y = rnd.nextDouble();

    // ✅ ほぼ極小（0.25〜1.2pxくらいに集中）
    final r = (0.25 + math.pow(rnd.nextDouble(), 3.4) * 0.9).toDouble();

    // ✅ ほぼ薄い（たまに少し明るい）
    final baseA = (0.3 + math.pow(rnd.nextDouble(), 2.5) * 0.70).toDouble();

    stars.add(_BgStar(x, y, r, baseA));
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

      final a = (s.baseA * avoid).clamp(0.01, 0.5);
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
        stops: const [0.0, 0.3, 0.8],
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
        stops: const [0.0, 0.5, 1.0],
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

    // ズームアウトは薄く
    final zoomFade = (math.log(20 * z01 + 0.8)/2).toDouble(); // 引きでかなり薄い

    for (int i = 0; i < nebula.length; i += 1) {
      final puff = nebula[i];

      final p = puff.pos;
      final v4 = rot.transform(v.Vector4(p.x, p.y, p.z, 1.0));

      final z = v4.z + 2.5;
      if (z <= 0.2) continue;

      final x2 = (v4.x / (z * fov)) * scale + center.dx;
      final y2 = (v4.y / (z * fov)) * scale + center.dy;

      if (x2 < -120 || x2 > size.width + 120 || y2 < -120 || y2 > size.height + 120) continue;

      // ✅ ズームアウトほど「小さく」する
      final sizeFade = (0.35 + 0.65 * z01).toDouble();
      final rPx = (((puff.radius / z) * 2.4) * sizeFade).clamp(2.0, 120.0);
      if (rPx < 2.0) continue;
      final c = nebulaColors[puff.colorIndex];

      // ✅ ズームアウトほど「薄く」
      final a = (puff.alpha * zoomFade).clamp(0.1, 1.0);

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
    
    onProjected(proj);

    // --- Stars: small ones via drawRawPoints, big ones via drawCircle ---

    // 小星の閾値（ここ未満はポイント描画にまとめる）
    const smallThreshold = 0.95; // 0.8〜1.2くらいで調整

    // 小星を詰める（x,y,x,y,...）
    final small = Float32List(proj.length * 2);
    int k = 0;

    // 大きい星はいつも通り（色付き）
    final paints = <int, Paint>{
      0: Paint()..color = const Color(0xCCFFFFFF),
      1: Paint()..color = const Color(0xCCB7D8FF),
      2: Paint()..color = const Color(0xCCFFE7B0),
      3: Paint()..color = const Color(0xCCFFB7B7),
    };

    // 小星用ペイント（白だけ、点を丸く）
    final smallPaint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.18) // 全体の薄さ（0.10〜0.30）
      ..strokeWidth = 1.0 // 点の太さ（0.8〜1.4）
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // 大星用ペイント（使い回し。毎回newしない）
    final bigPaint = Paint()..isAntiAlias = true;

    final zoomT = ((zoom - 0.6) / (3.0 - 0.6)).clamp(0.0, 1.0); // 0..1
    final zoomBoost = 0.55+ 0.9 * math.pow(zoomT, 2.2); // ズームアウトは抑える

    final circleZoomScale = 0.35 + 0.65 * z01; // 引き:0.35 寄り:1.0
    final minCircleR = 0.55 + 0.35 * z01;

    for (final ps in proj) {
      final s = ps.star;
      final depth = ps.depth;

      final sizePx = (s.size / depth) * zoomBoost;
      if (sizePx < 0.25) continue;

      // 明るさ（小星もこれで薄くして遠いほど消える）
      final alpha = (s.bright / math.pow(depth, 0.8)).clamp(0.03, 0.9).toDouble();

      // 小星 → RawPoints に詰める（白一択）
      if (sizePx < smallThreshold) {
        // alpha が薄すぎる星はポイント化しても見えないので捨てる（軽くなる）
        if (alpha < 0.06) continue;

        small[k++] = ps.screen.dx;
        small[k++] = ps.screen.dy;
        continue;
      }

      // 大星 → circle（色あり）
      final base = paints[s.type] ?? paints[0]!;
      bigPaint
        ..color = base.color.withValues(alpha: alpha)
        ..blendMode = base.blendMode;

      final r = math.max(minCircleR, sizePx * circleZoomScale);

      canvas.drawCircle(ps.screen, r, bigPaint);
    }

    // 小星まとめ描画（k>0 のときだけ）
    if (k > 0) {
      // 使う分だけ切り出し（sublistはコピーになるので、できれば避けたい）
      // ここは軽さ優先で “drawRawPointsが受ける範囲” を渡すために sublist します
      final pts = small.sublist(0, k);
      canvas.drawRawPoints(PointMode.points, pts, smallPaint);
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

  int bulgeCount = 5000,
  double bulgeRadiusNorm = 0.2,
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
  // 外側寄りにしつつ殻っぽさを避ける
  const mix = 0.28; // 内部を残す割合（0.20〜0.35）

  final uOuter = 0.75*(1 - math.pow(rnd.nextDouble(), 2.6)).toDouble(); // 外側寄り
  final uInner = math.pow(rnd.nextDouble(), 1.7).toDouble();       // 内部寄り
  final u = (rnd.nextDouble() < mix) ? uInner : uOuter;

  final maxR = radius * bulgeRadiusNorm;
  final r = maxR * u;

  // 半径ジッタで“殻”感を壊す
  final rJ = (r + randNorm() * (maxR * 0.06)).clamp(0.0, maxR).toDouble();

  // 以降、r の代わりに rJ を使う
  final theta = math.acos(2 * rnd.nextDouble() - 1);
  final phi = rnd.nextDouble() * 2 * math.pi;

  final flatten = 0.75;

  final x = rJ * math.sin(theta) * math.cos(phi);
  final y = rJ * math.sin(theta) * math.sin(phi);
  final z = rJ * math.cos(theta) * flatten;

    // バルジの星の明るさとサイズ
    // final bright = (0.35 + 0.65 * math.pow(1 - u, 0.7) + rnd.nextDouble() * 0.15)
    //     .clamp(0.0, 1.0)
    //     .toDouble();
    
    final bright = 1.0;

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
