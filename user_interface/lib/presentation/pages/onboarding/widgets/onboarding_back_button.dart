// lib/presentation/pages/onboarding/widgets/onboarding_back_button.dart
import 'package:flutter/material.dart';

import 'package:lefture/presentation/themes/app_colors.dart';

/// Enlarged back button shared by onboarding steps. Styled to match
/// [LanguageHeaderButton] with a glassmorphism circular container and a
/// comfortable touch target.
class OnboardingBackButton extends StatelessWidget {
  const OnboardingBackButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final buttonSize = isTablet ? 46.0 : 40.0;
    final iconSize = isTablet ? 22.0 : 18.0;

    return Material(
      color: AppColors.universe.glassWhiteLow,
      shape: const CircleBorder(side: BorderSide(color: Color(0x1CFFFFFF))),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 2), // Chevron visual center correction
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: iconSize,
                color: AppColors.universe.textStarlight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
