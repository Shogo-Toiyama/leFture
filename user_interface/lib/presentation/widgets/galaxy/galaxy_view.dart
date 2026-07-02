import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/galaxy/galaxy_state_provider.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

// 定数はクラスの外に出しておくとコンパイル時定数として扱われやすい
const double _minZoom = 1.0;
const double _maxZoom = 8.0;

class GalaxyView extends ConsumerStatefulWidget {
  const GalaxyView({super.key});

  @override
  ConsumerState<GalaxyView> createState() => GalaxyViewState();
}

class GalaxyViewState extends ConsumerState<GalaxyView> with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  late final List<_Star> _stars;
  late final List<_NebulaPuff> _nebula;
  late final List<_BgStar> _bgStars;

  ui.Image? _spriteTexture;
  double t = 0.0;
  int _frame = 0; // フレームカウンタをフィールドに移動

  // Camera / controls
  bool userInteracting = false;

  // Cache projected points for picking
  List<_ProjectedStar> _projected = [];

  @override
  void initState() {
    super.initState();

    const seed = 42;
    const starCount = 20000;
    const arms = 3;
    const radius = 1.0;
    const thickness = 0.05;

    _stars = _generateSpiralGalaxy(
      seed: seed,
      count: starCount,
      arms: arms,
      radius: radius,
      thickness: thickness,
    );

    _nebula = _generateNebula(
      seed: seed,
      count: (starCount / 500).toInt(),
      arms: arms,
      radius: radius * 0.7,
      thickness: thickness,
    );

    _bgStars = _generateBgStars(
      seed: 123,
      count: 3200,
    );

    _ticker = AnimationController(vsync: this, duration: const Duration(days: 99))
      ..addListener(_onTick) // リスナーメソッドを分けるとスッキリする
      ..forward();

    _generateSpriteTexture();
  }

  void _onTick() {
    if (!mounted) return;
    if ((_frame++ & 1) == 1) return; // 30FPS制限
    t += 1 / 30;

    final state = ref.read(galaxyStateProvider);
    if (!userInteracting && state.autoRotate) {
      const spin = 0.002;
      final worldUp = v.Vector3(0, 1, 0);
      final q = v.Quaternion.axisAngle(worldUp, spin);
      final newCamRot = q * state.camRot;
      newCamRot.normalize();
      
      ref.read(galaxyStateProvider.notifier).updateState(
        camRot: newCamRot,
        zoom: state.zoom,
      );
    }
    setState(() {});
  }

  Future<void> _generateSpriteTexture() async {
    const size = 64;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = const Offset(size / 2, size / 2);
    final radius = size / 2.0;

    final paint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        const [0.0, 1.0],
      );

    canvas.drawCircle(center, radius, paint);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);

    if (mounted) {
      setState(() {
        _spriteTexture = image;
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // --- 外部からジェスチャーを流し込むための公開メソッド ---
  void handleScaleStart(ScaleStartDetails details) {
    setState(() => userInteracting = true);
  }

  void handleScaleUpdate(ScaleUpdateDetails d) {
    final state = ref.read(galaxyStateProvider);
    var newZoom = state.zoom;
    var newCamRot = state.camRot.clone();

    // Zoom
    const zoomSensitivity = 0.05;
    final s = math.pow(d.scale, zoomSensitivity).toDouble();
    newZoom = (newZoom * s).clamp(_minZoom, _maxZoom);

    // Rotation
    final dx = d.focalPointDelta.dx;
    final dy = d.focalPointDelta.dy;
    const rotSpeed = 0.005;

    final worldUp = v.Vector3(0, 1, 0);
    final qYaw = v.Quaternion.axisAngle(worldUp, -dx * rotSpeed);

    final camRight = v.Vector3(1, 0, 0);
    newCamRot.rotate(camRight); 
    final qPitch = v.Quaternion.axisAngle(camRight, -dy * rotSpeed);

    newCamRot = (qPitch * qYaw) * newCamRot;
    newCamRot.normalize();

    ref.read(galaxyStateProvider.notifier).updateState(
      camRot: newCamRot,
      zoom: newZoom,
    );
    setState(() {});
  }

  void handleScaleEnd(ScaleEndDetails details) {
    setState(() => userInteracting = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_spriteTexture == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // プロバイダーから状態を直接読み取る（watchしないことでリビルドを防ぐ）
    final state = ref.read(galaxyStateProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            GestureDetector(
              onScaleStart: handleScaleStart,
              onScaleEnd: handleScaleEnd,
              onScaleUpdate: handleScaleUpdate,
              child: RepaintBoundary(
                // 2. ClipRect: 画用紙からはみ出したインク（drawColor）をカットする
                child: ClipRect(
                  child: CustomPaint(
                    painter: _GalaxyPainter(
                      stars: _stars,
                      nebula: _nebula,
                      bgStars: _bgStars,
                      time: t,
                      camRot: state.camRot,
                      zoom: state.zoom,
                      onProjected: (list) => _projected = list,
                      sprite: _spriteTexture!,
                    ),
                    isComplex: true,
                    willChange: true,
                    size: Size.infinite, 
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Data Classes (Immutable & Simple)
// ---------------------------------------------------------------------------

class _Star {
  const _Star({
    required this.id,
    required this.pos,
    required this.size,
    required this.bright,
    required this.type,
  });

  final String id;
  final v.Vector3 pos;
  final double size;
  final double bright;
  final int type;
}

class _ProjectedStar {
  const _ProjectedStar({required this.star, required this.screen, required this.depth});
  final _Star star;
  final Offset screen;
  final double depth;
}

class _NebulaPuff {
  const _NebulaPuff({
    required this.pos,
    required this.radius,
    required this.alpha,
    required this.colorIndex,
  });

  final v.Vector3 pos;
  final double radius;
  final double alpha;
  final int colorIndex;
}

class _BgStar {
  const _BgStar(this.x01, this.y01, this.r, this.baseA);
  final double x01;
  final double y01;
  final double r;
  final double baseA;
}

typedef _ProjectedCallback = void Function(List<_ProjectedStar> list);


// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _GalaxyPainter extends CustomPainter {
  _GalaxyPainter({
    required this.stars,
    required this.nebula,
    required this.bgStars,
    required this.time,
    required this.camRot,
    required this.zoom,
    required this.onProjected,
    required this.sprite,
  });

  final List<_Star> stars;
  final List<_NebulaPuff> nebula;
  final List<_BgStar> bgStars;
  final double time;
  final v.Quaternion camRot;
  final double zoom;
  final _ProjectedCallback onProjected;
  final ui.Image sprite;

  // 定数を外に出して再利用可能に
  static final _bgColor = AppColors.universe.voidBackground;
  static const _nebulaPalette = [
    Color(0xFFFF5FA2), Color(0xFFFF9A3D), Color(0xFFB86BFF), Color(0xFF4FA8FF),
  ];
  static const _starPalette = [
    Color(0xFFFFFFFF), Color(0xFFB7D8FF), Color(0xFFFFE7B0), Color(0xFFFFB7B7),
  ];
  static const _glowGradientColors = [Color(0xE6D8F3FF), Color(0x7A6BCBFF), Color(0x001E1B2E)];
  static const _coreGradientColors = [Color(0x66FFB26B), Color(0x33FF4FA2), Color(0x00FF4FA2)];

  @override
  void paint(Canvas canvas, Size size) {
    // -------------------------------------------------------
    // Pre-calculation
    // -------------------------------------------------------
    canvas.drawColor(_bgColor, BlendMode.src);

    final center = Offset(size.width * 0.5, size.height * 0.52);
    final screenMin = math.min(size.width, size.height);
    
    // Density Fix: iPad等で星がスカスカになるのを防ぐ
    final densityScale = screenMin / 380.0;
    
    final fov = 1.2;
    final scale = screenMin * 0.38 * zoom;
    final z01 = ((zoom - _minZoom) / (_maxZoom - _minZoom)).clamp(0.0, 1.0).toDouble();

    // Matrix manual expansion
    final rotMatrix = v.Matrix4.identity()..setRotation(camRot.asRotationMatrix());
    final m = rotMatrix.storage; 
    final m00 = m[0], m01 = m[4], m02 = m[8],  m03 = m[12];
    final m10 = m[1], m11 = m[5], m12 = m[9],  m13 = m[13];
    final m20 = m[2], m21 = m[6], m22 = m[10], m23 = m[14];

    // Sprite info
    final spriteW = sprite.width.toDouble();
    final spriteRect = Rect.fromLTWH(0, 0, spriteW, sprite.height.toDouble());
    final anchorX = spriteW / 2;
    final anchorY = sprite.height.toDouble() / 2;

    // -------------------------------------------------------
    // 1. Background Stars
    // -------------------------------------------------------
    final bgTransforms = <RSTransform>[];
    final bgRects = <Rect>[];
    final bgColors = <Color>[];
    final avoidR = screenMin * 0.14; 
    final avoidRSq = avoidR * avoidR;

    for (final s in bgStars) {
      final x = s.x01 * size.width;
      final y = s.y01 * size.height;

      // Avoid center galaxy
      final dx = x - center.dx;
      final dy = y - center.dy;
      final dist2 = dx * dx + dy * dy;
      final avoid = (dist2 / avoidRSq).clamp(0.55, 1.0);

      final a = (s.baseA * avoid).clamp(0.01, 0.5);
      final sScale = (s.r * 2.5) * densityScale / spriteW;

      bgTransforms.add(RSTransform.fromComponents(
        rotation: 0,
        scale: sScale,
        anchorX: anchorX,
        anchorY: anchorY,
        translateX: x,
        translateY: y,
      ));
      bgRects.add(spriteRect);
      bgColors.add(Colors.white.withValues(alpha: a));
    }

    if (bgTransforms.isNotEmpty) {
      canvas.drawAtlas(
        sprite, bgTransforms, bgRects, bgColors, 
        BlendMode.modulate, null, Paint()
      );
    }

    // -------------------------------------------------------
    // 2. Center Glow (Deformed by view angle)
    // -------------------------------------------------------
    final normalX = m01;
    final normalY = m11; 
    final normalZ = m21; 
    final tilt = normalZ.abs();
    final angle = math.atan2(normalY, normalX);
    
    final haze = 1.35 - 0.55 * z01;
    final coreRadius = screenMin * 0.18 * zoom * haze;

    // Outer Glow
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.scale(0.35 + 0.65 * tilt, 1.0); // Flatten

    final glowPaint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = ui.Gradient.radial(
        Offset.zero, coreRadius, _glowGradientColors, const [0.0, 0.3, 0.8]
      );
    canvas.drawCircle(Offset.zero, coreRadius, glowPaint);
    canvas.restore();

    // Inner Core
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.scale(0.75 + 0.25 * tilt, 1.0); // Less flattened

    final corePaint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = ui.Gradient.radial(
        Offset.zero, coreRadius * 0.55, _coreGradientColors, const [0.0, 0.5, 1.0]
      );
    canvas.drawCircle(Offset.zero, coreRadius * 0.55, corePaint);
    canvas.restore();

    // -------------------------------------------------------
    // 3. Nebula Layer
    // -------------------------------------------------------
    final nebulaTransforms = <RSTransform>[];
    final nebulaRects = <Rect>[];
    final nebulaColors = <Color>[];
    final zoomFade = math.log(20 * z01 + 0.8) / 2;

    for (final puff in nebula) {
      final px = puff.pos.x;
      final py = puff.pos.y;
      final pz = puff.pos.z;

      final rotX = m00 * px + m01 * py + m02 * pz + m03;
      final rotY = m10 * px + m11 * py + m12 * pz + m13;
      final rotZ = m20 * px + m21 * py + m22 * pz + m23;

      final z = rotZ + 2.5;
      if (z <= 0.2) continue;

      final x2 = (rotX / (z * fov)) * scale + center.dx;
      final y2 = (rotY / (z * fov)) * scale + center.dy;

      // Culling
      if (x2 < -150 || x2 > size.width + 150 || y2 < -150 || y2 > size.height + 150) continue;

      final sizeFade = (0.35 + 0.65 * z01);
      final rPx = ((puff.radius / z) * 2.4 * sizeFade * densityScale);
      final sScale = (rPx * 2) / spriteW;

      final alpha = (puff.alpha * zoomFade).clamp(0.0, 1.0) * 0.7;
      if (alpha < 0.01) continue;

      nebulaTransforms.add(RSTransform.fromComponents(
        rotation: 0, scale: sScale, anchorX: anchorX, anchorY: anchorY, 
        translateX: x2, translateY: y2
      ));
      nebulaRects.add(spriteRect);
      nebulaColors.add(_nebulaPalette[puff.colorIndex].withValues(alpha: alpha));
    }

    if (nebulaTransforms.isNotEmpty) {
      canvas.drawAtlas(
        sprite, nebulaTransforms, nebulaRects, nebulaColors, 
        BlendMode.modulate, null, Paint()..blendMode = BlendMode.screen
      );
    }

    // -------------------------------------------------------
    // 4. Stars Layer
    // -------------------------------------------------------
    final starTransforms = <RSTransform>[];
    final starRects = <Rect>[];
    final starColors = <Color>[];
    final projList = <_ProjectedStar>[];
    
    final zoomT = ((zoom - 0.6) / 2.4).clamp(0.0, 1.0); // 3.0 - 0.6 = 2.4
    final zoomBoost = 0.55 + 0.9 * math.pow(zoomT, 2.2);
    
    // Zoom Alpha Logic
    final baseAlphaFactor = 0.3 + 0.5 * z01;

    for (final s in stars) {
      final px = s.pos.x;
      final py = s.pos.y;
      final pz = s.pos.z;

      final rotX = m00 * px + m01 * py + m02 * pz + m03;
      final rotY = m10 * px + m11 * py + m12 * pz + m13;
      final rotZ = m20 * px + m21 * py + m22 * pz + m23;

      final z = rotZ + 2.5;
      if (z <= 0.2) continue;

      final x2 = (rotX / (z * fov)) * scale + center.dx;
      final y2 = (rotY / (z * fov)) * scale + center.dy;

      // Culling (tight)
      if (x2 < -20 || x2 > size.width + 20 || y2 < -20 || y2 > size.height + 20) continue;

      projList.add(_ProjectedStar(star: s, screen: Offset(x2, y2), depth: z));

      final sizePx = (s.size / z) * zoomBoost * densityScale;
      if (sizePx < 0.2) continue;

      // Alpha calc
      final alpha = (s.bright / math.pow(z, 0.8) * baseAlphaFactor).clamp(0.3, 1.0);
      if (alpha < 0.01) continue;

      final visualScale = 1.2; 
      final sScale = (sizePx * 2 * visualScale) / spriteW;

      starTransforms.add(RSTransform.fromComponents(
        rotation: 0, scale: sScale, anchorX: anchorX, anchorY: anchorY, 
        translateX: x2, translateY: y2
      ));
      starRects.add(spriteRect);
      starColors.add(_starPalette[s.type].withValues(alpha: alpha));
    }

    onProjected(projList);

    if (starTransforms.isNotEmpty) {
      canvas.drawAtlas(
        sprite, starTransforms, starRects, starColors, 
        BlendMode.modulate, null, Paint()..blendMode = BlendMode.screen
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GalaxyPainter oldDelegate) {
    return oldDelegate.camRot != camRot || 
           oldDelegate.zoom != zoom || 
           oldDelegate.time != time;
  }
}


// ---------------------------------------------------------------------------
// Generators
// ---------------------------------------------------------------------------

List<_BgStar> _generateBgStars({required int seed, required int count}) {
  final rnd = math.Random(seed);
  return List.generate(count, (_) {
    final x = rnd.nextDouble();
    final y = rnd.nextDouble();
    final r = 0.25 + math.pow(rnd.nextDouble(), 3.4) * 0.9;
    final baseA = 0.3 + math.pow(rnd.nextDouble(), 2.5) * 0.70;
    return _BgStar(x, y, r, baseA);
  });
}

List<_NebulaPuff> _generateNebula({
  required int seed,
  required int count,
  required int arms,
  required double radius,
  required double thickness,
  double innerStartNorm = 0.10,
}) {
  final rnd = math.Random(seed + 999);
  
  // Helper: Box-Muller normal distribution
  double randNorm() {
    final u1 = math.max(rnd.nextDouble(), 1e-9);
    final u2 = rnd.nextDouble();
    return math.sqrt(-2.0 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  final puffs = <_NebulaPuff>[];

  for (int i = 0; i < count; i++) {
    final t = rnd.nextDouble();
    final rNormRaw = math.pow(t, 0.55).toDouble();
    final rNorm = innerStartNorm + (1 - innerStartNorm) * rNormRaw;
    final r = radius * rNorm;

    final arm = rnd.nextInt(arms);
    final baseAngle = (arm / arms) * 2 * math.pi;

    const spiralTightness = 5.0;
    final angleNoise = 0.12 + 0.40 * rNorm;
    final angle = baseAngle + r * spiralTightness + randNorm() * angleNoise;

    final posNoise = 0.015 + 0.06 * rNorm;
    final x = r * math.cos(angle) + randNorm() * posNoise;
    final y = r * math.sin(angle) + randNorm() * posNoise;
    final z = randNorm() * thickness * (0.4 + 0.8 * (1 - rNorm));

    final baseR = 14.0 + 38.0 * rNorm;
    final alpha = (0.10 + 0.22 * (1 - rNorm) + rnd.nextDouble() * 0.08).clamp(0.04, 0.32);

    final p = rnd.nextDouble();
    final colorIndex = (p < 0.45) ? 0 : (p < 0.75) ? 1 : (p < 0.92) ? 2 : 3;

    puffs.add(_NebulaPuff(
      pos: v.Vector3(x, z, y),
      radius: baseR * (0.7 + rnd.nextDouble() * 0.9),
      alpha: alpha,
      colorIndex: colorIndex,
    ));
  }
  return puffs;
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
  final stars = <_Star>[];

  // Helper
  double randNorm() {
    final u1 = math.max(rnd.nextDouble(), 1e-9);
    final u2 = rnd.nextDouble();
    return math.sqrt(-2.0 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  // --- Bulge ---
  for (int i = 0; i < bulgeCount; i++) {
    const mix = 0.28;
    final uOuter = 0.75 * (1 - math.pow(rnd.nextDouble(), 2.6));
    final uInner = math.pow(rnd.nextDouble(), 1.7).toDouble();
    final u = (rnd.nextDouble() < mix) ? uInner : uOuter;

    final maxR = radius * bulgeRadiusNorm;
    final r = maxR * u;
    final rJ = (r + randNorm() * (maxR * 0.06)).clamp(0.0, maxR);

    final theta = math.acos(2 * rnd.nextDouble() - 1);
    final phi = rnd.nextDouble() * 2 * math.pi;
    const flatten = 0.75;

    final x = rJ * math.sin(theta) * math.cos(phi);
    final y = rJ * math.sin(theta) * math.sin(phi);
    final z = rJ * math.cos(theta) * flatten;

    final bright = (0.35 + 0.65 * math.pow(1 - u, 0.7) + rnd.nextDouble() * 0.15)
        .clamp(0.0, 1.0).toDouble();
    
    final size = (0.5 + bright * 0.9 + rnd.nextDouble() * 0.35);

    final p = rnd.nextDouble();
    final type = (p < 0.55) ? 2 : (p < 0.95) ? 0 : 1;

    stars.add(_Star(
      id: "bulge_$i", pos: v.Vector3(x, z, y), size: size, bright: bright, type: type
    ));
  }

  // --- Disk ---
  final diskCount = count - stars.length; // 残りをディスクにする
  for (int i = 0; i < diskCount; i++) {
    final t = rnd.nextDouble();
    final rNormRaw = math.pow(t, 0.85).toDouble();
    final rNorm = innerDiskHoleNorm + (1.0 - innerDiskHoleNorm) * rNormRaw;
    final r = radius * rNorm;

    final arm = rnd.nextInt(arms);
    final baseAngle = (arm / arms) * 2 * math.pi;

    const spiralTightness = 5.0;
    final angleNoise = (0.18 + 0.35 * rNorm);
    final angle = baseAngle + r * spiralTightness + randNorm() * angleNoise;

    final posNoise = 0.012 + 0.05 * rNorm;
    final x = r * math.cos(angle) + randNorm() * posNoise;
    final y = r * math.sin(angle) + randNorm() * posNoise;
    final z = randNorm() * thickness * (0.6 + 0.8 * (1 - rNorm));

    final bright = (0.15 + 0.85 * math.pow(1 - rNorm, 1.8) + rnd.nextDouble() * 0.15)
        .clamp(0.0, 1.0);
    final size = (0.6 + bright * 1.8 + rnd.nextDouble() * 0.6);

    final p = rnd.nextDouble();
    final type = (p < 0.55) ? 1 : (p < 0.78) ? 0 : (p < 0.93) ? 2 : 3;

    stars.add(_Star(
      id: "disk_$i", pos: v.Vector3(x, z, y), size: size, bright: bright, type: type
    ));
  }

  return stars;
}