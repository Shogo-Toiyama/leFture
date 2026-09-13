// lib/presentation/pages/onboarding/widgets/onboarding_top_bar.dart
import 'package:flutter/material.dart';

import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_back_button.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_horizontal_step_indicator.dart';
import 'package:lefture/presentation/widgets/language_header_button.dart';

/// Top bar containing the enlarged back button, 4-step horizontal indicator,
/// and language selection button.
///
/// Intentionally placed at the top of each scrollable onboarding step rather
/// than fixed to the viewport, so it scrolls away naturally with the content
/// when the user scrolls down.
class OnboardingTopBar extends StatelessWidget {
  const OnboardingTopBar({
    super.key,
    required this.onBack,
    required this.currentStepIndex,
  });

  final VoidCallback onBack;

  /// 0 for Language, 1 for Profile, 2 for Permissions, 3 for Plan.
  final int currentStepIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OnboardingBackButton(onTap: onBack),
        const SizedBox(width: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final targetWidth = constraints.maxWidth > 240 ? 240.0 : constraints.maxWidth;
              return Center(
                child: SizedBox(
                  width: targetWidth,
                  child: OnboardingHorizontalStepIndicator(
                    currentStepIndex: currentStepIndex,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        const LanguageHeaderButton(),
      ],
    );
  }
}
