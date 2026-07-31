// lib/presentation/pages/onboarding/widgets/onboarding_done_step.dart
import 'package:flutter/material.dart';

import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// Final onboarding step. Leads straight into the Profile → Course →
/// Lecture checklist on the empty home screen, where the profile is
/// actually filled in.
class OnboardingDoneStep extends StatelessWidget {
  const OnboardingDoneStep({super.key, required this.onFinish});

  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        const Spacer(),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.growthGreen.withValues(alpha: 0.15),
            border: Border.all(color: AppColors.growthGreen.withValues(alpha: 0.4)),
          ),
          child: const Icon(Icons.check_rounded, color: AppColors.growthGreen, size: 32),
        ),
        const SizedBox(height: 20),
        Text(
          l10n.onboardingDoneTitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.onboardingDoneSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.universe.textComet, fontSize: 14, height: 1.4),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.starGold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: onFinish,
            child: Text(l10n.onboardingGetStartedButton, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      ],
    );
  }
}
