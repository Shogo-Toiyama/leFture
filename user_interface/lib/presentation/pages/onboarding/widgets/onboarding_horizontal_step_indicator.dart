// lib/presentation/pages/onboarding/widgets/onboarding_horizontal_step_indicator.dart
import 'package:flutter/material.dart';

import 'package:lefture/presentation/themes/app_colors.dart';

class _StepSpec {
  const _StepSpec({
    required this.color,
    required this.icon,
  });

  final Color color;
  final IconData icon;
}

const _steps = [
  _StepSpec(
    color: AppColors.cosmicBlue,
    icon: Icons.language_rounded,
  ),
  _StepSpec(
    color: AppColors.growthGreen,
    icon: Icons.person_outline_rounded,
  ),
  _StepSpec(
    color: AppColors.alertAmber,
    icon: Icons.lock_outline_rounded,
  ),
  _StepSpec(
    color: AppColors.starGold,
    icon: Icons.workspace_premium_rounded,
  ),
];

/// Horizontal 4-step indicator connecting circular nodes with glowing gradients.
/// Faithfully mirrors the vertical waypoint design from [OnboardingIntroStep],
/// laid out horizontally to bridge the back button and language button.
///
/// [currentStepIndex]: 0 for Step 1 (Language), 1 for Step 2 (Profile),
/// 2 for Step 3 (Permissions), 3 for Step 4 (Plan).
class OnboardingHorizontalStepIndicator extends StatelessWidget {
  const OnboardingHorizontalStepIndicator({
    super.key,
    required this.currentStepIndex,
  });

  final int currentStepIndex;

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final nodeSize = isTablet ? 34.0 : 28.0;
    final iconSize = isTablet ? 17.0 : 14.0;

    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          _StepNode(
            spec: _steps[i],
            isActive: i == currentStepIndex,
            isCompleted: i < currentStepIndex,
            nodeSize: nodeSize,
            iconSize: iconSize,
          ),
          if (i < _steps.length - 1)
            Expanded(
              child: _StepConnector(
                prevColor: _steps[i].color,
                nextColor: _steps[i + 1].color,
                isPassed: i < currentStepIndex,
              ),
            ),
        ],
      ],
    );
  }
}

class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.spec,
    required this.isActive,
    required this.isCompleted,
    required this.nodeSize,
    required this.iconSize,
  });

  final _StepSpec spec;
  final bool isActive;
  final bool isCompleted;
  final double nodeSize;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final color = spec.color;
    final isLit = isActive || isCompleted;
    final effectiveSize = isActive ? nodeSize + 4 : nodeSize;
    final effectiveIconSize = isActive ? iconSize + 2 : iconSize;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      width: effectiveSize,
      height: effectiveSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isLit
            ? RadialGradient(
                center: const Alignment(-0.3, -0.3),
                colors: [
                  Color.lerp(color, Colors.white, isActive ? 0.28 : 0.18)!,
                  color,
                ],
              )
            : null,
        color: isLit ? null : AppColors.universe.glassWhiteLow,
        border: Border.all(
          color: isLit ? color.withValues(alpha: isActive ? 0.75 : 0.45) : const Color(0x1CFFFFFF),
          width: isActive ? 1.5 : 1.0,
        ),
        boxShadow: isLit
            ? [
                BoxShadow(
                  color: color.withValues(alpha: isActive ? 0.55 : 0.25),
                  blurRadius: isActive ? 14 : 6,
                  spreadRadius: isActive ? 1 : 0,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Icon(
          spec.icon,
          size: effectiveIconSize,
          color: isLit ? Colors.white : Colors.white.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

class _StepConnector extends StatelessWidget {
  const _StepConnector({
    required this.prevColor,
    required this.nextColor,
    required this.isPassed,
  });

  final Color prevColor;
  final Color nextColor;
  final bool isPassed;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(1),
        gradient: isPassed
            ? LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [prevColor, nextColor],
              )
            : null,
        color: isPassed ? null : const Color(0x1CFFFFFF),
        boxShadow: isPassed
            ? [
                BoxShadow(
                  color: prevColor.withValues(alpha: 0.45),
                  blurRadius: 4,
                ),
              ]
            : null,
      ),
    );
  }
}
