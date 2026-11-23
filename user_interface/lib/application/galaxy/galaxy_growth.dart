import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:lefture/application/galaxy/galaxy_data_provider.dart';

// ---------------------------------------------------------------------------
// 銀河の成長(Learning Galaxy)
//
// ユーザーが集めた星の数(数え続ける本当の数)から、銀河の見た目を決める。
// 見た目は5段階のプリセットの間をなめらかに補間する。補間は「集めた星の数」の
// 対数で行うので、最初は速く育ち、後半ほどゆるやかになる。
//
// 5段階の値は 2026-11-22 に開発者が調整画面で決めたもの。
// 指定のなかった項目(腕の本数・厚み・中心と腕のすき間・背景の星)は既定値のまま。
// 既定の画角は段階ごとに持たず、銀河の半径から GalaxyZoomRule で求める(Homeとページで同じ)。
// ---------------------------------------------------------------------------

/// 銀河の見た目のパラメーター一式(形を決めるシード値は含まない)。
@immutable
class GalaxyLook {
  const GalaxyLook({
    required this.totalStars,
    required this.bulgeShare,
    required this.radius,
    required this.bulgeRadiusNorm,
    required this.nebulaCount,
    required this.glow,
    this.starScale = 1.0,
    this.arms = 3,
    this.thickness = 0.05,
    this.innerDiskHoleNorm = 0.14,
    this.bgStarCount = 3200,
  });

  /// 描画する星の数(中心＋腕)。集めた星の数とは別。
  final int totalStars;

  /// 星のうち中心(バルジ)に置く割合。
  final double bulgeShare;
  final double radius;
  final double bulgeRadiusNorm;
  final int nebulaCount;

  /// 中心に重ねる光の倍率(GalaxyView.glowScale)。
  final double glow;

  /// 星1個ごとの大きさ・明るさの倍率(GalaxyView.starScale)。小さい銀河ほど星を大きく見せる。
  final double starScale;
  final int arms;
  final double thickness;
  final double innerDiskHoleNorm;
  final int bgStarCount;

  int get bulgeStars => (totalStars * bulgeShare).round();
  int get diskStars => totalStars - bulgeStars;

  GalaxyConfig toConfig({int seed = 42}) => GalaxyConfig(
        seed: seed,
        bulgeStarCount: bulgeStars,
        diskStarCount: diskStars,
        arms: arms,
        radius: radius,
        thickness: thickness,
        bulgeRadiusNorm: bulgeRadiusNorm,
        innerDiskHoleNorm: innerDiskHoleNorm,
        nebulaCount: nebulaCount,
        bgStarCount: bgStarCount,
      );

  static GalaxyLook lerp(GalaxyLook a, GalaxyLook b, double t) {
    double d(double x, double y) => lerpDouble(x, y, t)!;
    int i(int x, int y) => d(x.toDouble(), y.toDouble()).round();
    return GalaxyLook(
      totalStars: i(a.totalStars, b.totalStars),
      bulgeShare: d(a.bulgeShare, b.bulgeShare),
      radius: d(a.radius, b.radius),
      bulgeRadiusNorm: d(a.bulgeRadiusNorm, b.bulgeRadiusNorm),
      nebulaCount: i(a.nebulaCount, b.nebulaCount),
      glow: d(a.glow, b.glow),
      starScale: d(a.starScale, b.starScale),
      arms: i(a.arms, b.arms),
      thickness: d(a.thickness, b.thickness),
      innerDiskHoleNorm: d(a.innerDiskHoleNorm, b.innerDiskHoleNorm),
      bgStarCount: i(a.bgStarCount, b.bgStarCount),
    );
  }
}

enum GalaxyStage { newborn, small, medium, large, huge }

/// 既定の画角(カメラの倍率)を銀河の半径から求める式: 画角 = k × 半径^(−p)。
/// p = 1 なら半径に反比例(画面上の銀河の大きさが一定)。p > 1 なら小さい銀河ほどさらに寄る。
/// 既定の k = 5.18, p = 1.16 は「巨大(半径1.6)で3、生まれたて(半径0.4)で15」になる値(2026-11-22)。
/// Homeとページで同じ画角を使う。
@immutable
class GalaxyZoomRule {
  const GalaxyZoomRule({this.k = 5.18, this.p = 1.16, this.minRatio = 0.25, this.maxRatio = 2.0});

  /// 半径1.0のときの画角。
  final double k;

  /// 半径による変化の強さ(1で反比例)。
  final double p;

  /// ピンチで引ける限界は既定の画角のこの倍率(0.25 = 既定の1/4まで引ける)。以前のHome(既定4で1〜8)と同じ比率。
  final double minRatio;

  /// ピンチで寄れる限界は既定の画角のこの倍率(2.0 = 既定の2倍まで寄れる)。
  final double maxRatio;

  /// この半径の銀河でピンチで引ける限界の倍率。
  double minZoomFor(double radius) => zoomFor(radius) * minRatio;

  /// この半径の銀河でピンチで寄れる限界の倍率。
  double maxZoomFor(double radius) => zoomFor(radius) * maxRatio;

  double zoomFor(double radius) => k * math.pow(math.max(radius, 0.05), -p).toDouble();

  /// 今の半径で [zoom] になるように k を決め直す(p はそのまま)。
  GalaxyZoomRule fitTo({required double radius, required double zoom}) =>
      GalaxyZoomRule(k: zoom * math.pow(math.max(radius, 0.05), p).toDouble(), p: p, minRatio: minRatio, maxRatio: maxRatio);

  GalaxyZoomRule copyWith({double? k, double? p, double? minRatio, double? maxRatio}) => GalaxyZoomRule(
        k: k ?? this.k,
        p: p ?? this.p,
        minRatio: minRatio ?? this.minRatio,
        maxRatio: maxRatio ?? this.maxRatio,
      );

  @override
  bool operator ==(Object other) =>
      other is GalaxyZoomRule &&
      other.k == k &&
      other.p == p &&
      other.minRatio == minRatio &&
      other.maxRatio == maxRatio;

  @override
  int get hashCode => Object.hash(k, p, minRatio, maxRatio);
}

const defaultGalaxyZoomRule = GalaxyZoomRule();

const Map<GalaxyStage, GalaxyLook> galaxyStageLooks = {
  GalaxyStage.newborn: GalaxyLook(
    totalStars: 500, bulgeShare: 0.25, radius: 0.4, bulgeRadiusNorm: 0.1, nebulaCount: 0, glow: 0.1, starScale: 3.0),
  GalaxyStage.small: GalaxyLook(
    totalStars: 1000, bulgeShare: 0.25, radius: 0.5, bulgeRadiusNorm: 0.15, nebulaCount: 5, glow: 0.2, starScale: 2.2),
  GalaxyStage.medium: GalaxyLook(
    totalStars: 5000, bulgeShare: 0.20, radius: 0.7, bulgeRadiusNorm: 0.2, nebulaCount: 20, glow: 0.4, starScale: 1.5),
  GalaxyStage.large: GalaxyLook(
    totalStars: 20000, bulgeShare: 0.15, radius: 1.0, bulgeRadiusNorm: 0.2, nebulaCount: 40, glow: 1.0),
  GalaxyStage.huge: GalaxyLook(
    totalStars: 30000, bulgeShare: 0.10, radius: 1.6, bulgeRadiusNorm: 0.3, nebulaCount: 80, glow: 1.5),
};

/// 想定する1日の獲得数(2026-11-22 の暫定の目安。開発者が実際に使って見直す)。
/// 講義: 1トピック1個 × 1講義平均4.5トピック × 1日平均1〜1.5講義 ＝ 5〜6個。
/// チャット: 1回20〜30個 × 2日に1回 ＝ 10〜15個。合計で約20個。
const int galaxyExpectedStarsPerDay = 20;

/// 各段階の見た目にちょうど到達する「集めた星の数」(到達させたい日数 × 想定する1日の獲得数)。
/// 日数は 小さい 7日 / 中くらい 27日(1か月以内) / 大きい 365日 / 巨大 900日(約2.5年)。
/// 1日20個なら 0 / 140 / 540 / 7,300 / 18,000。
const Map<GalaxyStage, int> galaxyStageEarnedStars = {
  GalaxyStage.newborn: 0,
  GalaxyStage.small: 7 * galaxyExpectedStarsPerDay,
  GalaxyStage.medium: 27 * galaxyExpectedStarsPerDay,
  GalaxyStage.large: 365 * galaxyExpectedStarsPerDay,
  GalaxyStage.huge: 900 * galaxyExpectedStarsPerDay,
};

/// 集めた星の数から銀河の見た目を求める。段階の間は log(1 + 星の数) で補間し、
/// 巨大な銀河より先は巨大な銀河のまま。
GalaxyLook galaxyLookForEarnedStars(int earnedStars) {
  final n = math.max(0, earnedStars);
  const stages = GalaxyStage.values;
  for (var k = 0; k < stages.length - 1; k++) {
    final a = galaxyStageEarnedStars[stages[k]]!;
    final b = galaxyStageEarnedStars[stages[k + 1]]!;
    if (n <= b) {
      final la = math.log(1 + a);
      final lb = math.log(1 + b);
      final t = ((math.log(1 + n) - la) / (lb - la)).clamp(0.0, 1.0);
      return GalaxyLook.lerp(galaxyStageLooks[stages[k]]!, galaxyStageLooks[stages[k + 1]]!, t);
    }
  }
  return galaxyStageLooks[GalaxyStage.huge]!;
}
