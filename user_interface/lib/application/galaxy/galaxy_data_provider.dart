import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vector_math/vector_math_64.dart' as v;

part 'galaxy_data_provider.g.dart';

// ---------------------------------------------------------------------------
// Data Classes (Immutable & Simple)
//
// 生成コストが高いため、画面(GalaxyView)のインスタンスごとに作り直すのではなく
// galaxyDataProvider でアプリ全体として1回だけ生成してキャッシュする。
// ---------------------------------------------------------------------------

class GalaxyStar {
  const GalaxyStar({
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

class GalaxyNebulaPuff {
  const GalaxyNebulaPuff({
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

class GalaxyBgStar {
  const GalaxyBgStar(this.x01, this.y01, this.r, this.baseA);
  final double x01;
  final double y01;
  final double r;
  final double baseA;
}

/// 銀河描画に必要な、不変な生成済みデータ一式。
/// カメラ回転・ズームなどの動的な状態は含まない（galaxyStateProviderが担当する）。
class GalaxyData {
  const GalaxyData({
    required this.stars,
    required this.nebula,
    required this.bgStars,
    required this.sprite,
  });

  final List<GalaxyStar> stars;
  final List<GalaxyNebulaPuff> nebula;
  final List<GalaxyBgStar> bgStars;
  final ui.Image sprite;
}

@Riverpod(keepAlive: true)
Future<GalaxyData> galaxyData(Ref ref) async {
  const seed = 42;
  const starCount = 20000;
  const arms = 3;
  const radius = 1.0;
  const thickness = 0.05;

  final stars = _generateSpiralGalaxy(
    seed: seed,
    count: starCount,
    arms: arms,
    radius: radius,
    thickness: thickness,
  );

  final nebula = _generateNebula(
    seed: seed,
    count: (starCount / 500).toInt(),
    arms: arms,
    radius: radius * 0.7,
    thickness: thickness,
  );

  final bgStars = _generateBgStars(seed: 123, count: 3200);

  final sprite = await _generateSpriteTexture();

  return GalaxyData(stars: stars, nebula: nebula, bgStars: bgStars, sprite: sprite);
}

// ---------------------------------------------------------------------------
// Generators
// ---------------------------------------------------------------------------

Future<ui.Image> _generateSpriteTexture() async {
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
  return picture.toImage(size, size);
}

List<GalaxyBgStar> _generateBgStars({required int seed, required int count}) {
  final rnd = math.Random(seed);
  return List.generate(count, (_) {
    final x = rnd.nextDouble();
    final y = rnd.nextDouble();
    final r = 0.25 + math.pow(rnd.nextDouble(), 3.4) * 0.9;
    final baseA = 0.3 + math.pow(rnd.nextDouble(), 2.5) * 0.70;
    return GalaxyBgStar(x, y, r, baseA);
  });
}

List<GalaxyNebulaPuff> _generateNebula({
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

  final puffs = <GalaxyNebulaPuff>[];

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

    puffs.add(GalaxyNebulaPuff(
      pos: v.Vector3(x, z, y),
      radius: baseR * (0.7 + rnd.nextDouble() * 0.9),
      alpha: alpha,
      colorIndex: colorIndex,
    ));
  }
  return puffs;
}

List<GalaxyStar> _generateSpiralGalaxy({
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
  final stars = <GalaxyStar>[];

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
        .clamp(0.0, 1.0)
        .toDouble();

    final size = (0.5 + bright * 0.9 + rnd.nextDouble() * 0.35);

    final p = rnd.nextDouble();
    final type = (p < 0.55) ? 2 : (p < 0.95) ? 0 : 1;

    stars.add(GalaxyStar(
      id: "bulge_$i", pos: v.Vector3(x, z, y), size: size, bright: bright, type: type,
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

    stars.add(GalaxyStar(
      id: "disk_$i", pos: v.Vector3(x, z, y), size: size, bright: bright, type: type,
    ));
  }

  return stars;
}
