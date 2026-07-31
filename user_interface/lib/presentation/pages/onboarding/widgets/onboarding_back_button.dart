// lib/presentation/pages/onboarding/widgets/onboarding_back_button.dart
import 'package:flutter/material.dart';

import 'package:lefture/presentation/themes/app_colors.dart';

/// Small back chevron shared by onboarding steps that can go back — either
/// to the previous macro step, or (on the profile step) to the previous
/// question within the step.
class OnboardingBackButton extends StatelessWidget {
  const OnboardingBackButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: AppColors.universe.textComet),
      ),
    );
  }
}
