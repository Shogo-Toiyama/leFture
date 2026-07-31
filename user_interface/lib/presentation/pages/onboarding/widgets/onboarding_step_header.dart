// lib/presentation/pages/onboarding/widgets/onboarding_step_header.dart
import 'package:flutter/material.dart';

import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_back_button.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// Eyebrow + title (+ optional subtitle) header shared by onboarding steps.
class OnboardingStepHeader extends StatelessWidget {
  const OnboardingStepHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.onBack,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onBack != null) ...[
          OnboardingBackButton(onTap: onBack!),
          const SizedBox(height: 12),
        ],
        Text(
          eyebrow,
          style: TextStyle(
            color: AppColors.universe.textComet,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: TextStyle(
            color: AppColors.universe.textStarlight,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: TextStyle(color: AppColors.universe.textComet, fontSize: 13, height: 1.4),
          ),
        ],
      ],
    );
  }
}
