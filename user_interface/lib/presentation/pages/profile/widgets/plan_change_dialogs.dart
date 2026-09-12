import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:lefture/domain/entities/plan_option.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

import 'plan_theme.dart';

/// handlePurchase呼び出しの結果、どのダイアログを出すべきかを表す。
/// upgrade/初回購入は即時に権利が切り替わるためお祝い演出、downgradeは
/// 次回更新日まで反映されない非直感的な挙動の説明。
///
/// 予約されたdowngrade/crossgradeの取り消し(revert)はここには含まれない:
/// 「現在のプランをもう一度purchase()する」ことでApple側の予約を取り消せる、
/// というのは非公式(RevenueCatコミュニティ発の未確認情報)で、実機検証の
/// 結果その場で新しい購入として処理されてしまい機能しなかった。Appleが
/// 唯一公式に保証する取り消し手段はApple自身の「サブスクリプションを管理」
/// 画面のみのため、revertはshowRevertGuideDialog経由でその画面を開く
/// 案内に一本化している(purchase()は呼ばない)。
enum PlanChangeOutcome { upgrade, downgrade }

Future<void> _showPlainDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String okLabel,
}) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1E1F29),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      content: Text(message, style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(okLabel, style: const TextStyle(color: AppColors.starGold)),
        ),
      ],
    ),
  );
}

/// ダウングレード成立時に表示する、事務的な説明ダイアログ。
/// 「次回更新日に切り替わる」という非直感的な挙動を、その場で誤解なく
/// 伝えるためのもの(祝祭演出はアップグレード専用)。
Future<void> showDowngradeDialog({
  required BuildContext context,
  required AppLocalizations l10n,
}) {
  return _showPlainDialog(
    context: context,
    title: l10n.plansDowngradeDialogTitle,
    message: l10n.plansDowngradeDialogMessage,
    okLabel: l10n.creditDetailOkButton,
  );
}

/// 予約されたdowngrade/crossgradeを取り消したい時の案内ダイアログ。
/// アプリ内で直接取り消す手段は無い(purchase()を使う非公式な方法は実機で
/// 機能しなかった)ため、Apple自身の「サブスクリプションを管理」画面を
/// 開く導線をここに集約する。実際に取り消されたかどうかはこの場では
/// わからない(後続のPRODUCT_CHANGE Webhookでpending_plan_idが更新される
/// のを待つ)ため、成功を装う演出は一切しない。
Future<void> showRevertGuideDialog({
  required BuildContext context,
  required AppLocalizations l10n,
}) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1E1F29),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(l10n.plansRevertGuideDialogTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      content: Text(l10n.plansRevertGuideDialogMessage, style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.plansRevertGuideDialogDismissButton, style: const TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            launchUrl(Uri.parse('https://apps.apple.com/account/subscriptions'), mode: LaunchMode.externalApplication);
          },
          child: Text(
            l10n.plansRevertGuideDialogOpenButton,
            style: const TextStyle(color: AppColors.starGold, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}

/// アップグレード(または初回購入)成立時に表示する、プランカラーの
/// 紙吹雪演出付きお祝いダイアログ。
Future<void> showUpgradeCelebrationDialog({
  required BuildContext context,
  required AppLocalizations l10n,
  required PlanOption plan,
}) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _CelebrationDialog(l10n: l10n, plan: plan),
  );
}

class _CelebrationDialog extends StatefulWidget {
  const _CelebrationDialog({required this.l10n, required this.plan});
  final AppLocalizations l10n;
  final PlanOption plan;

  @override
  State<_CelebrationDialog> createState() => _CelebrationDialogState();
}

class _CelebrationDialogState extends State<_CelebrationDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiParticle> _particles;

  @override
  void initState() {
    super.initState();
    // 2.8秒かけて優雅に開花し、チカチカと星屑のように瞬きながら舞い落ちる
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
    _particles = _generateParticles(planThemeColor(widget.plan.name));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_ConfettiParticle> _generateParticles(Color themeColor) {
    final random = math.Random(42);
    final hsl = HSLColor.fromColor(themeColor);
    final luminousColor = hsl.withLightness((hsl.lightness + 0.35).clamp(0.0, 0.94)).toColor();
    final softTintColor = hsl.withLightness((hsl.lightness + 0.20).clamp(0.0, 0.86)).toColor();

    // 白 〜 プラン色の洗練されたスターパレットに完全統一
    final palette = <Color>[
      Colors.white,
      const Color(0xFFF8FAFC), // ピュアスターホワイト
      const Color(0xFFE2E8F0), // シルバースターホワイト
      const Color(0xFFE0E7FF), // 淡いコズミックホワイト
      luminousColor,
      softTintColor,
      themeColor,
    ];

    return List.generate(90, (i) {
      // 中央の惑星アイコン位置（center基準で y = -55）から放射状に開花
      final originOffset = Offset(
        (random.nextDouble() - 0.5) * 16,
        -55 + (random.nextDouble() - 0.5) * 16,
      );

      // 360度全方位へふわりと広がる
      final angle = random.nextDouble() * 2 * math.pi;

      // ★ 画面全体に広がりすぎず、ダイアログ周辺に美しく収まる飛散半径（80px〜200px）
      final spreadRadius = 80.0 + random.nextDouble() * 120.0;

      // ★ すべて繊細な星形（ダイヤモンドスター）に統一（2.2px〜4.8px）
      final size = 2.2 + random.nextDouble() * 2.6;

      return _ConfettiParticle(
        originOffset: originOffset,
        angle: angle,
        spreadRadius: spreadRadius,
        color: palette[random.nextInt(palette.length)],
        size: size,
        rotationSpeed: (random.nextDouble() - 0.5) * 5,
        delay: random.nextDouble() * 0.04,
        gravity: 80 + random.nextDouble() * 50, // ユーザー好評の自然な重力速度
        twinkleFrequency: 7.0 + random.nextDouble() * 12.0,
        twinklePhase: random.nextDouble() * 2 * math.pi,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = planThemeColor(widget.plan.name);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.zero,
      child: SizedBox.expand(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. ダイアログ本体（画面中央）
            Container(
              width: 284,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1F29),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: color, width: 1.4),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 30, spreadRadius: 2)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.18),
                      border: Border.all(color: color, width: 1.5),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Image.asset(planIconAsset(widget.plan.name), fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.l10n.plansUpgradeDialogTitle(widget.plan.name),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.l10n.plansUpgradeDialogMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(widget.l10n.plansUpgradeDialogButton, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),

            // 2. コズミック・ダイヤモンドスター瞬き演出（★全画面の手前レイヤー）
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _ConfettiPainter(particles: _particles, t: _controller.value),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfettiParticle {
  _ConfettiParticle({
    required this.originOffset,
    required this.angle,
    required this.spreadRadius,
    required this.color,
    required this.size,
    required this.rotationSpeed,
    required this.delay,
    required this.gravity,
    required this.twinkleFrequency,
    required this.twinklePhase,
  });

  final Offset originOffset;
  final double angle;
  final double spreadRadius;
  final Color color;
  final double size;
  final double rotationSpeed;
  final double delay;
  final double gravity;
  final double twinkleFrequency;
  final double twinklePhase;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.particles, required this.t});

  final List<_ConfettiParticle> particles;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.5);

    for (final p in particles) {
      final localT = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (localT <= 0) continue;

      // ★ 物理的に滑らかな空気抵抗（指数関数的減衰: 1 - e^(-4.0 * t)）
      // 初速は強く勢いがありながら、空気抵抗によって角のない極めて自然な減速でエネルギーを失う
      final dragProgress = 1.0 - math.exp(-9.0 * localT);

      final start = center + p.originOffset;
      final currentRadius = p.spreadRadius * dragProgress;
      final dx = start.dx + math.cos(p.angle) * currentRadius;
      // 放射状の初速度と重力加速度が途切れなくスムーズに融合
      final dy = start.dy + math.sin(p.angle) * (currentRadius * 0.78) + (0.5 * p.gravity * localT * localT);

      // フェードアウト（後半に向けて自然に溶けるように消失）
      final baseFade = localT < 0.65 ? 1.0 : (1 - ((localT - 0.65) / 0.35)).clamp(0.0, 1.0);
      if (baseFade <= 0) continue;

      // ★ 個別トゥインクル明滅（各星がチカチカと美しく瞬く）
      final twinkle = 0.20 + 0.80 * math.sin(localT * p.twinkleFrequency * math.pi + p.twinklePhase).abs();
      final currentOpacity = (baseFade * twinkle).clamp(0.0, 0.65);
      if (currentOpacity <= 0.015) continue;

      canvas.save();
      canvas.translate(dx, dy);
      final spin = p.rotationSpeed * localT * math.pi;
      canvas.rotate(spin);

      // ★ 全粒子を純白・カラーの極細ダイヤモンドスター（星形）に統一！
      final rayLength = p.size;
      final rayPaint = Paint()
        ..color = p.color.withValues(alpha: currentOpacity * 0.60)
        ..strokeWidth = 0.50
        ..strokeCap = StrokeCap.round;

      // 十字光条（縦横）
      canvas.drawLine(Offset(-rayLength, 0), Offset(rayLength, 0), rayPaint);
      canvas.drawLine(Offset(0, -rayLength), Offset(0, rayLength), rayPaint);

      // やや大きい星には繊細な斜め光条を追加（8方向スターバースト）
      if (p.size > 3.6) {
        final diag = rayLength * 0.45;
        canvas.drawLine(Offset(-diag, -diag), Offset(diag, diag), rayPaint);
        canvas.drawLine(Offset(-diag, diag), Offset(diag, -diag), rayPaint);
      }

      // 純白の微小コア光
      final starCorePaint = Paint()..color = Colors.white.withValues(alpha: currentOpacity * 0.90);
      canvas.drawCircle(Offset.zero, 0.55, starCorePaint);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => oldDelegate.t != t;
}
