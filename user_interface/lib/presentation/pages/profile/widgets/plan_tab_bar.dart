import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lefture/domain/entities/plan_option.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

import 'plan_theme.dart';

/// プラン選択タブ。非アクティブはアイコンのみ、アクティブになると
/// ラベルがインラインで展開するアニメーションタブ。カード側の
/// カルーセルと双方向に連動する(状態自体は親[PlansPage]が持つ、
/// 制御されたコンポーネント)。
class PlanTabBar extends StatelessWidget {
  const PlanTabBar({
    super.key,
    required this.plans,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<PlanOption> plans;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // 灰色の背景トラック (アクティブタイルが上下に少しはみ出るよう、上下4pxインセット)
          Positioned.fill(
            top: 4,
            bottom: 4,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.universe.glassWhiteLow,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: AppColors.universe.glassBorder),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < plans.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  _PlanTab(
                    key: ValueKey(plans[i].id),
                    plan: plans[i],
                    isActive: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanTab extends StatelessWidget {
  const _PlanTab({super.key, required this.plan, required this.isActive, required this.onTap});

  final PlanOption plan;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = planThemeColor(plan.name);
    // 左側の暗い色 (テーマカラーのニュアンスを含んだ深い不透明ダーク)
    final darkColor = Color.lerp(color, const Color(0xFF0D0F18), 0.75)!;
    final midColor = Color.lerp(color, const Color(0xFF0D0F18), 0.35)!;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: isActive ? 16 : 10, vertical: isActive ? 10 : 8),
        decoration: BoxDecoration(
          // アクティブ時は左側が暗い不透明グラデーションにして下の枠をしっかり隠す
          gradient: isActive
              ? LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0.0, 0.48, 1.0],
                  colors: [
                    darkColor,
                    midColor,
                    color,
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(100),
          border: isActive ? Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.4) : null,
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: 12,
                    spreadRadius: 1,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 白いシャドウをまとった28pxアイコン
            Opacity(
              opacity: isActive ? 1.0 : 0.70,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // アイコン輪郭に沿ったソフトな白いシャドウ
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        Colors.white.withValues(alpha: isActive ? 0.90 : 0.60),
                        BlendMode.srcIn,
                      ),
                      child: Image.asset(planIconAsset(plan.name), width: 28, height: 28),
                    ),
                  ),
                  // 前面のメインアイコン本体
                  Image.asset(planIconAsset(plan.name), width: 28, height: 28),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: isActive
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 8),
                        Text(
                          plan.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: 0.2,
                            shadows: [
                              Shadow(
                                color: Color(0x40000000),
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
