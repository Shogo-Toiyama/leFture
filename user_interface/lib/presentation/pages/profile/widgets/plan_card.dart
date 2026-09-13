import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:lefture/domain/entities/plan_option.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

import 'plan_purchase_state.dart';
import 'plan_theme.dart';

/// カルーセルの1枚。ダークガラスの土台にプランのテーマカラーを
/// にじませたグラデーション(塗りつぶしではなく、既存のisHighlighted
/// カードと同じ「薄く着色」の延長)。CTAボタンはここには置かない
/// (フローティングContinueボタンに集約、PlansPage側)。
class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.plan,
    required this.state,
    required this.isPurchasing,
    required this.isPendingTarget,
  });

  final PlanOption plan;
  final PlanPurchaseState state;
  final bool isPurchasing;

  /// 現在アクティブなプランが、次回更新日にこのプランへ切り替わる予定
  /// (予約中)かどうか。state.isCurrentPlanとは排他(予約先は定義上
  /// 現在のプランとは別物のため)。
  final bool isPendingTarget;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final themeColor = planThemeColor(plan.name, storeProductId: plan.storeProductId);
    final isPremium = plan.isPremiumTier;
    final isStandard = plan.isStandardTier;
    final languageCode = Localizations.localeOf(context).languageCode;
    final subtitle = plan.localizedSubtitle(languageCode);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            gradient: isPremium
                ? const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    stops: [0.0, 0.45, 0.78, 1.0],
                    colors: [
                      Color(0xFF090A14), // 深いコズミックブラック
                      Color(0xFF131026), // ディープバイオレット
                      Color(0xFF1E1036), // コズミックマゼンタ
                      Color(0xFF121E3B), // 右側: オーロラシアンが差す星雲
                    ],
                  )
                : isStandard
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        stops: [0.0, 0.40, 0.75, 1.0],
                        colors: [
                          Color(0xFF140A0F), // 左上: 落ち着いたダークスペース
                          Color(0xFF240E18), // 中央: 深紅のルビー
                          Color(0xFF38141F), // 右下: 暖かなソーラーフレア
                          Color(0xFF4A1A18), // 最右下: 琥珀ソーラーの輝き
                        ],
                      )
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        stops: const [0.0, 0.75],
                        colors: [
                          themeColor.withValues(alpha: 0.22),
                          AppColors.universe.voidBackground.withValues(alpha: 0.85),
                        ],
                      ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isPremium
                  ? const Color(0xFFC084FC) // 澄んだバイオレット
                  : isStandard
                      ? const Color(0xFFFB7185) // 華やかなローズルビー
                      : themeColor,
              width: (isPremium || isStandard) ? 1.8 : 1.4,
            ),
            boxShadow: isPremium
                ? [
                    BoxShadow(color: const Color(0xFFA855F7).withValues(alpha: 0.45), blurRadius: 36, spreadRadius: 1),
                    BoxShadow(color: const Color(0xFF06B6D4).withValues(alpha: 0.28), blurRadius: 48, spreadRadius: 2),
                    BoxShadow(color: const Color(0xFFEC4899).withValues(alpha: 0.20), blurRadius: 56, spreadRadius: 1),
                  ]
                : isStandard
                    ? [
                        BoxShadow(color: const Color(0xFFE11D48).withValues(alpha: 0.38), blurRadius: 32, spreadRadius: 1),
                        BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.25), blurRadius: 46, spreadRadius: 2),
                      ]
                    : [
                        BoxShadow(color: themeColor.withValues(alpha: 0.25), blurRadius: 28),
                      ],
          ),
          child: Stack(
            children: [
              // プレミアム専用: 右側を中心に優しく瞬く星屑・オーロラ・星芒のアニメーション
              if (isPremium)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: _AnimatedCosmicStarfield(),
                  ),
                ),
              // スタンダード専用: 太陽系の背後に温かく呼吸するソーラーコロナ・金色の微細粒子
              if (isStandard)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: _AnimatedSolarCorona(),
                  ),
                ),
              // 背景の一部としてデカデカと枠からはみ出す巨大アイコン (右下配置、上位プランは鮮やかに)
              Positioned(
                bottom: -100,
                right: -120,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: isPremium ? 0.38 : (isStandard ? 0.28 : 0.15),
                    child: Image.asset(
                      planIconAsset(plan.name, storeProductId: plan.storeProductId),
                      width: 400,
                      height: 400,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state.isCurrentPlan) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isPremium
                              ? const Color(0xFFA855F7).withValues(alpha: 0.25)
                              : themeColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: isPremium ? const Color(0xFFC084FC) : themeColor.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Text(
                          l10n.plansCurrentPlanBadge,
                          style: TextStyle(
                            color: isPremium ? const Color(0xFFE879F9) : themeColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ] else if (isPendingTarget) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.universe.glassWhiteLow,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: AppColors.universe.textStarlight.withValues(alpha: 0.6)),
                        ),
                        child: Text(
                          l10n.plansNextPlanBadge,
                          style: TextStyle(
                            color: AppColors.universe.textStarlight,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ] else if (isPremium) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFA855F7), Color(0xFF06B6D4)],
                          ),
                          borderRadius: BorderRadius.circular(100),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFA855F7).withValues(alpha: 0.45),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Text(
                          l10n.plansRecommendedBadge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      plan.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        shadows: isPremium
                            ? const [
                                Shadow(color: Color(0xFF38BDF8), blurRadius: 8),
                                Shadow(color: Color(0xFFEC4899), blurRadius: 18),
                                Shadow(color: Color(0xFFA855F7), blurRadius: 32),
                                Shadow(color: Color(0xFF6366F1), blurRadius: 48),
                              ]
                            : isStandard
                                ? const [
                                    Shadow(color: Color(0xFFFB7185), blurRadius: 8),
                                    Shadow(color: Color(0xFFE11D48), blurRadius: 18),
                                    Shadow(color: Color(0xFFF59E0B), blurRadius: 32),
                                    Shadow(color: Color(0xFFD97706), blurRadius: 48),
                                  ]
                                : [
                                    Shadow(
                                      color: themeColor,
                                      blurRadius: 8,
                                    ),
                                    Shadow(
                                      color: themeColor,
                                      blurRadius: 18,
                                    ),
                                    Shadow(
                                      color: themeColor.withValues(alpha: 0.9),
                                      blurRadius: 30,
                                    ),
                                    Shadow(
                                      color: themeColor.withValues(alpha: 0.6),
                                      blurRadius: 45,
                                    ),
                                  ],
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: AppColors.universe.textStarlight,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    _FeatureCheckRow(label: l10n.plansFeatureCredits, included: plan.tierLevel >= 0, themeColor: themeColor),
                    const SizedBox(height: 8),
                    _FeatureCheckRow(
                      label: l10n.plansFeatureFasterProcessing,
                      included: plan.tierLevel >= 1,
                      themeColor: themeColor,
                    ),
                    const SizedBox(height: 8),
                    _FeatureCheckRow(
                      label: l10n.plansFeaturePrioritySupport,
                      included: plan.tierLevel >= 2,
                      themeColor: themeColor,
                    ),
                    const SizedBox(height: 8),
                    _FeatureCheckRow(
                      label: l10n.plansFeatureEarlyAccess,
                      included: plan.tierLevel >= 3,
                      themeColor: themeColor,
                    ),
                    const Spacer(),
                    Text(
                      state.priceLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.creditDetailPlanSubtitle(plan.monthlyCreditAmountDisplay, plan.billingIntervalMonths),
                      style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
                    ),
                  ],
                ),
              ),
              // プレミアム専用ホログラフィック・オーバーレイ:
              // 文字やバッジの手前に半透明の虹色光沢とダイヤモンドラメが反射して輝く
              if (isPremium)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: _HolographicTiltFoil(),
                  ),
                ),
              if (isPurchasing)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.universe.voidBackground.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Center(child: CircularProgressIndicator(color: themeColor)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// チェックマーク/バツで機能の有無を示す行。実際の機能制限(feature gating)は
/// まだ実装していないため、あくまで見た目上の演出用プレースホルダー。
class _FeatureCheckRow extends StatelessWidget {
  const _FeatureCheckRow({required this.label, required this.included, required this.themeColor});

  final String label;
  final bool included;
  final Color themeColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          included ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: included ? themeColor : AppColors.universe.textComet.withValues(alpha: 0.5),
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: included ? AppColors.universe.textStarlight : AppColors.universe.textComet.withValues(alpha: 0.6),
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// プレミアムプラン専用: 右側を中心に優しく瞬く星屑・星雲のアニメーションウィジェット
class _AnimatedCosmicStarfield extends StatefulWidget {
  const _AnimatedCosmicStarfield();

  @override
  State<_AnimatedCosmicStarfield> createState() => _AnimatedCosmicStarfieldState();
}

class _AnimatedCosmicStarfieldState extends State<_AnimatedCosmicStarfield>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat(reverse: true);
  }

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
          painter: _CosmicStarfieldPainter(progress: _controller.value),
        );
      },
    );
  }
}

class _StarItem {
  const _StarItem({
    required this.relX,
    required this.relY,
    required this.radius,
    required this.baseOpacity,
    required this.speed,
    required this.phase,
  });

  final double relX;
  final double relY;
  final double radius;
  final double baseOpacity;
  final double speed;
  final double phase;
}

// 右側に集中した繊細な星屑 (固定シードで1回のみ初期化)
final List<_StarItem> _cosmicStars = () {
  final random = math.Random(101);
  final stars = <_StarItem>[];
  for (var i = 0; i < 85; i++) {
    // xは0.40〜0.98に集中（左側のテキスト領域をクリーンに保つ）
    final u = random.nextDouble();
    final relX = 0.42 + 0.56 * math.pow(u, 0.82);
    final relY = 0.04 + 0.92 * random.nextDouble();
    final radius = 0.75 + random.nextDouble() * 1.10; // 0.75〜1.85px (程よい大きさ)
    final baseOpacity = 0.12 + random.nextDouble() * 0.26; // 0.12〜0.38の薄く上品な光
    final speed = 0.7 + random.nextDouble() * 1.2;
    final phase = random.nextDouble() * 2 * math.pi;
    stars.add(_StarItem(
      relX: relX,
      relY: relY,
      radius: radius,
      baseOpacity: baseOpacity,
      speed: speed,
      phase: phase,
    ));
  }
  return stars;
}();

/// プレミアムプラン専用: 右側を中心に淡く瞬く星雲・オーロラ・星屑・星芒のカスタムペインター
class _CosmicStarfieldPainter extends CustomPainter {
  const _CosmicStarfieldPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 星雲・コズミックオーロラ (Nebula & Cosmic Aurora)
    final nebulaPulse = math.sin(progress * math.pi) * 0.03;

    // ディープバイオレット星雲
    final nebulaPaint1 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF9C27B0).withValues(alpha: (0.18 + nebulaPulse).clamp(0.04, 0.28)),
          const Color(0xFF3F51B5).withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.84, size.height * 0.30),
        radius: size.width * 0.45,
      ));
    canvas.drawCircle(Offset(size.width * 0.84, size.height * 0.30), size.width * 0.45, nebulaPaint1);

    // ネオンシアンのオーロラスポット
    final nebulaPaint2 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF06B6D4).withValues(alpha: (0.13 + nebulaPulse).clamp(0.03, 0.22)),
          const Color(0xFF7C4DFF).withValues(alpha: 0.06),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.78, size.height * 0.68),
        radius: size.width * 0.42,
      ));
    canvas.drawCircle(Offset(size.width * 0.78, size.height * 0.68), size.width * 0.42, nebulaPaint2);

    // マゼンタの星間ダスト光彩
    final nebulaPaint3 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFEC4899).withValues(alpha: (0.09 + nebulaPulse * 0.8).clamp(0.02, 0.16)),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.92, size.height * 0.50),
        radius: size.width * 0.35,
      ));
    canvas.drawCircle(Offset(size.width * 0.92, size.height * 0.50), size.width * 0.35, nebulaPaint3);

    // 2. 右側に集中した星屑 (個別に瞬くアニメーション)
    final starPaint = Paint()..color = Colors.white;
    for (final star in _cosmicStars) {
      final x = star.relX * size.width;
      final y = star.relY * size.height;
      // 星ごとにずれた穏やかな瞬き (-0.08 〜 +0.08)
      final wave = math.sin(progress * 2 * math.pi * star.speed + star.phase);
      final currentOpacity = (star.baseOpacity + wave * 0.08).clamp(0.04, 0.48);
      starPaint.color = Colors.white.withValues(alpha: currentOpacity);
      canvas.drawCircle(Offset(x, y), star.radius, starPaint);
    }

    // 3. 右側の淡い十字星芒 (7個、シアンとバイオレットの二重光芒で優しくブリージング)
    final crossStars = [
      (0.88, 0.14, 1.0, 0.0, const Color(0xFFE1BEE7)),
      (0.68, 0.24, 1.2, 1.2, const Color(0xFF67E8F9)),
      (0.93, 0.36, 0.9, 2.4, const Color(0xFFF472B6)),
      (0.74, 0.50, 1.3, 0.8, const Color(0xFF67E8F9)),
      (0.86, 0.64, 1.1, 3.1, const Color(0xFFE1BEE7)),
      (0.64, 0.76, 0.85, 1.9, const Color(0xFF67E8F9)),
      (0.91, 0.88, 1.15, 4.2, const Color(0xFFF472B6)),
    ];

    for (final (rx, ry, speed, phaseOffset, auraColor) in crossStars) {
      final pos = Offset(size.width * rx, size.height * ry);
      final pulse = (math.sin(progress * 2 * math.pi * speed + phaseOffset) + 1.0) / 2.0; // 0.0〜1.0
      final coreOpacity = (0.20 + pulse * 0.28).clamp(0.0, 0.52);
      final glowOpacity = (0.05 + pulse * 0.14).clamp(0.0, 0.20);
      final lineOpacity = (0.12 + pulse * 0.22).clamp(0.0, 0.36);
      final beamLength = 3.0 + pulse * 2.5;

      // コアの光
      canvas.drawCircle(pos, 1.2, Paint()..color = Colors.white.withValues(alpha: coreOpacity));
      // 光背グロー
      canvas.drawCircle(pos, 3.5, Paint()..color = auraColor.withValues(alpha: glowOpacity));
      // 十字光条
      final linePaint = Paint()
        ..color = Colors.white.withValues(alpha: lineOpacity)
        ..strokeWidth = 0.6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(pos.dx - beamLength, pos.dy), Offset(pos.dx + beamLength, pos.dy), linePaint);
      canvas.drawLine(Offset(pos.dx, pos.dy - beamLength), Offset(pos.dx, pos.dy + beamLength), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CosmicStarfieldPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// スタンダードプラン専用: ソーラーコロナ（太陽系モチーフ）アニメーション
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedSolarCorona extends StatefulWidget {
  const _AnimatedSolarCorona();

  @override
  State<_AnimatedSolarCorona> createState() => _AnimatedSolarCoronaState();
}

class _AnimatedSolarCoronaState extends State<_AnimatedSolarCorona>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat(reverse: true);
  }

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
          painter: _SolarCoronaPainter(progress: _controller.value),
        );
      },
    );
  }
}

class _SolarFlareParticle {
  const _SolarFlareParticle({
    required this.relX,
    required this.relY,
    required this.radius,
    required this.baseOpacity,
    required this.speed,
    required this.phase,
  });

  final double relX;
  final double relY;
  final double radius;
  final double baseOpacity;
  final double speed;
  final double phase;
}

final List<_SolarFlareParticle> _solarParticles = () {
  final random = math.Random(42);
  final list = <_SolarFlareParticle>[];
  for (var i = 0; i < 35; i++) {
    // 右側（0.45〜0.96）に集中
    final relX = 0.45 + 0.50 * random.nextDouble();
    final relY = 0.08 + 0.84 * random.nextDouble();
    final radius = 0.8 + random.nextDouble() * 1.4;
    final baseOpacity = 0.10 + random.nextDouble() * 0.25;
    final speed = 0.6 + random.nextDouble() * 1.0;
    final phase = random.nextDouble() * 2 * math.pi;
    list.add(_SolarFlareParticle(
      relX: relX,
      relY: relY,
      radius: radius,
      baseOpacity: baseOpacity,
      speed: speed,
      phase: phase,
    ));
  }
  return list;
}();

class _SolarCoronaPainter extends CustomPainter {
  const _SolarCoronaPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final pulse = math.sin(progress * math.pi) * 0.05;

    // 1. 太陽コロナの呼吸する温かい光彩 (右下を中心に展開)
    final coronaCenter = Offset(size.width * 0.86, size.height * 0.68);
    final coronaRadius = size.width * 0.58;

    final coronaPaint1 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFF59E0B).withValues(alpha: (0.16 + pulse).clamp(0.06, 0.28)),
          const Color(0xFFE11D48).withValues(alpha: (0.10 + pulse * 0.7).clamp(0.03, 0.20)),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: coronaCenter, radius: coronaRadius));
    canvas.drawCircle(coronaCenter, coronaRadius, coronaPaint1);

    // 右上側の淡いフレア
    final flareCenter = Offset(size.width * 0.80, size.height * 0.22);
    final flarePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFB7185).withValues(alpha: (0.08 + pulse * 0.5).clamp(0.02, 0.16)),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: flareCenter, radius: size.width * 0.35));
    canvas.drawCircle(flareCenter, size.width * 0.35, flarePaint);

    // 2. 漂う微細な黄金の火の粉・光の粒子
    final particlePaint = Paint();
    for (final p in _solarParticles) {
      final x = p.relX * size.width;
      final y = p.relY * size.height;
      final wave = math.sin(progress * 2 * math.pi * p.speed + p.phase);
      final currentOpacity = (p.baseOpacity + wave * 0.09).clamp(0.04, 0.45);
      // 粒子は琥珀ゴールドと温かいホワイト
      particlePaint.color = const Color(0xFFFFD54F).withValues(alpha: currentOpacity);
      canvas.drawCircle(Offset(x, y), p.radius, particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SolarCoronaPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// プレミアムプラン専用: 端末の傾き(SensorsPlus)に連動するホログラフィック・フォイル＆ラメ
// ─────────────────────────────────────────────────────────────────────────────

class _HolographicTiltFoil extends StatefulWidget {
  const _HolographicTiltFoil();

  @override
  State<_HolographicTiltFoil> createState() => _HolographicTiltFoilState();
}

class _HolographicTiltFoilState extends State<_HolographicTiltFoil>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 約5秒周期で左上から右下へスーッと光彩が通り抜けるループアニメーション
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    )..repeat();
  }

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
        final progress = _controller.value;
        // 最初の約1.5秒で左上から右下へスーッと駆け抜け、残りの約3.5秒は待機して次の波へ
        double sweep;
        if (progress < 1) {
          final t = progress;
          sweep = Curves.easeInOutCubic.transform(t);
        } else {
          sweep = 1.0; // 画面外（右下）で待機
        }

        // -1.8 (左上画面外) から +1.8 (右下画面外) へ斜め45度で直線スイープ
        final tilt = -1.8 + sweep * 3.6;

        return CustomPaint(
          painter: _HolographicFoilPainter(
            tiltX: tilt,
            tiltY: tilt,
            rotationAngle: math.pi / 4,
          ),
        );
      },
    );
  }
}

class _GlitterFacet {
  const _GlitterFacet({
    required this.relX,
    required this.relY,
    required this.facetAngleX,
    required this.facetAngleY,
    required this.size,
    required this.tint,
    required this.ribbonAffinity,
  });

  final double relX;
  final double relY;
  final double facetAngleX; // この傾き角度と一致した時に直射鏡面反射（ピカッ）
  final double facetAngleY;
  final double size;
  final Color tint;
  final double ribbonAffinity; // 光帯通過時の励起感度
}

final List<_GlitterFacet> _glitterFacets = () {
  final random = math.Random(88);
  final list = <_GlitterFacet>[];
  const tints = [
    Color(0xFFFFFFFF), // ダイヤモンドホワイト
    Color(0xFF67E8F9), // ネオンシアン
    Color(0xFFF472B6), // ホログラフィックピンク
    Color(0xFFFBBF24), // プリズムゴールド
    Color(0xFFC084FC), // コズミックバイオレット
    Color(0xFF34D399), // エメラルドグリーン
    Color(0xFF38BDF8), // スカイシアン
  ];

  for (var i = 0; i < 85; i++) {
    // カード全面に高密度に分散配置
    final relX = 0.05 + 0.90 * random.nextDouble();
    final relY = 0.04 + 0.92 * random.nextDouble();
    // 反射ファセットの向き (-1.0 〜 +1.0)
    final facetAngleX = (random.nextDouble() * 2.0 - 1.0);
    final facetAngleY = (random.nextDouble() * 2.0 - 1.0);
    final size = 0.9 + random.nextDouble() * 1.5;
    final tint = tints[random.nextInt(tints.length)];
    final ribbonAffinity = 0.45 + random.nextDouble() * 0.55;
    list.add(_GlitterFacet(
      relX: relX,
      relY: relY,
      facetAngleX: facetAngleX,
      facetAngleY: facetAngleY,
      size: size,
      tint: tint,
      ribbonAffinity: ribbonAffinity,
    ));
  }
  return list;
}();

class _HolographicFoilPainter extends CustomPainter {
  const _HolographicFoilPainter({
    required this.tiltX,
    required this.tiltY,
    required this.rotationAngle,
  });

  final double tiltX;
  final double tiltY;
  final double rotationAngle;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width * 0.5 + tiltX * (size.width * 0.55);
    final centerY = size.height * 0.5 + tiltY * (size.height * 0.55);

    // ─────────────────────────────────────────────────────────────────────────
    // 1. 旋回・偏光プリズム光帯 (Rotating Rainbow Foil Sheen)
    // スマホの横回転(Roll)によって角度がダイナミックに旋回し、
    // 縦横の傾きによって文字やカード全面を手前に反射しながら走る
    // ─────────────────────────────────────────────────────────────────────────
    final diagonal = math.sqrt(size.width * size.width + size.height * size.height);
    final ribbonWidth = diagonal * 0.78;
    final ribbonHalf = ribbonWidth * 0.5;

    canvas.save();
    canvas.translate(centerX, centerY);
    canvas.rotate(rotationAngle);

    final sheenShader = LinearGradient(
      begin: const Alignment(-1.0, 0.0),
      end: const Alignment(1.0, 0.0),
      stops: const [
        0.0, 0.16, 0.30, 0.42, 0.50, 0.58, 0.70, 0.84, 1.0,
      ],
      colors: [
        Colors.transparent,
        const Color(0xFF06B6D4).withValues(alpha: 0.05), // ネオンシアン
        const Color(0xFFA855F7).withValues(alpha: 0.06), // コズミックバイオレット
        const Color(0xFFEC4899).withValues(alpha: 0.08), // ホログラフィックマゼンタ
        const Color(0xFFFFFFFF).withValues(alpha: 0.1), // ★中心の直射ダイヤモンド光沢
        const Color(0xFFFBBF24).withValues(alpha: 0.08), // プリズムゴールド
        const Color(0xFF10B981).withValues(alpha: 0.06), // オーロラエメラルド
        const Color(0xFF38BDF8).withValues(alpha: 0.05), // スカイシアン
        Colors.transparent,
      ],
    ).createShader(Rect.fromLTWH(-ribbonHalf, -diagonal, ribbonWidth, diagonal * 2));

    final sheenPaint = Paint()
      ..shader = sheenShader
      ..blendMode = BlendMode.screen;

    canvas.drawRect(Rect.fromLTWH(-ribbonHalf, -diagonal, ribbonWidth, diagonal * 2), sheenPaint);
    canvas.restore();

    // ─────────────────────────────────────────────────────────────────────────
    // 2. 高密度ダイヤモンド・グリッター鏡面反射 (Specular Glitter Sparkles)
    // - ファセット角一致（傾きピント）
    // - 光帯通過（虹色リボンがラメの上を横切った瞬間の励起フラッシュ）
    // のデュアルトリガーで手前に鮮烈に瞬く
    // ─────────────────────────────────────────────────────────────────────────
    final dotPaint = Paint();

    for (final flake in _glitterFacets) {
      final x = flake.relX * size.width;
      final y = flake.relY * size.height;

      // トリガーA: ファセット角度とスマホ傾きの鏡面反射
      final dx = tiltX - flake.facetAngleX;
      final dy = tiltY - flake.facetAngleY;
      final distTilt = math.sqrt(dx * dx + dy * dy);
      const reflectRadius = 0.36;
      final tiltIntensity = distTilt < reflectRadius
          ? math.pow(1.0 - (distTilt / reflectRadius), 2.2).toDouble()
          : 0.0;

      // トリガーB: 旋回光帯の直射光がラメ粒子を励起
      final relX = x - centerX;
      final relY = y - centerY;
      // 回転フレームにおけるリボン垂直軸方向の距離
      final ribbonDist = (relX * math.cos(-rotationAngle) - relY * math.sin(-rotationAngle)).abs();
      final ribbonCore = ribbonHalf * 0.42;
      final ribbonIntensity = ribbonDist < ribbonCore
          ? math.pow(1.0 - (ribbonDist / ribbonCore), 2.6).toDouble() * flake.ribbonAffinity
          : 0.0;

      final intensity = math.max(tiltIntensity, ribbonIntensity).clamp(0.0, 1.0);

      if (intensity > 0.03) {
        // 色付きオーラ（ラメのカラー反射）
        dotPaint.color = flake.tint.withValues(alpha: (intensity * 0.65).clamp(0.0, 0.85));
        canvas.drawCircle(Offset(x, y), flake.size * (1.3 + intensity * 1.8), dotPaint);

        // ダイヤモンド白熱コア
        dotPaint.color = Colors.white.withValues(alpha: (intensity * 0.98).clamp(0.0, 1.0));
        canvas.drawCircle(Offset(x, y), flake.size * (0.75 + intensity * 0.6), dotPaint);

        // 高輝度時の十字ダイヤモンド光芒 (Diamond Starburst)
        if (intensity > 0.42) {
          final beam = (intensity - 0.42) * 11.0;
          final flarePaint = Paint()
            ..color = Colors.white.withValues(alpha: ((intensity - 0.42) * 1.8).clamp(0.0, 0.95))
            ..strokeWidth = 0.8
            ..strokeCap = StrokeCap.round;

          canvas.drawLine(Offset(x - beam, y), Offset(x + beam, y), flarePaint);
          canvas.drawLine(Offset(x, y - beam), Offset(x, y + beam), flarePaint);

          // 超高輝度時の斜め光芒 (8方向スターバースト)
          if (intensity > 0.72) {
            final diagBeam = (intensity - 0.72) * 6.5;
            canvas.drawLine(Offset(x - diagBeam, y - diagBeam), Offset(x + diagBeam, y + diagBeam), flarePaint);
            canvas.drawLine(Offset(x - diagBeam, y + diagBeam), Offset(x + diagBeam, y - diagBeam), flarePaint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HolographicFoilPainter oldDelegate) =>
      oldDelegate.tiltX != tiltX ||
      oldDelegate.tiltY != tiltY ||
      oldDelegate.rotationAngle != rotationAngle;
}

