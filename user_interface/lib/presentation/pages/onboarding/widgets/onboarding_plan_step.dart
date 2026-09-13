// lib/presentation/pages/onboarding/widgets/onboarding_plan_step.dart
import 'package:flutter/material.dart';

import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_step_header.dart';
import 'package:lefture/presentation/pages/profile/widgets/plan_selection_view.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// Step 4: プラン選択。アカウント設定と同じ[PlanSelectionView](Free/Entry/
/// Standard/Premiumのタブ+カルーセル+RevenueCat購入)をそのまま移植して使う。
/// ヘッダーは他オンボーディング画面と統一した[OnboardingStepHeader]を渡し、
/// カードと下のフローティングボタン、プラン別のグラデーションはそのまま活かす。
class OnboardingPlanStep extends StatelessWidget {
  const OnboardingPlanStep({super.key, required this.onNext, required this.onBack});

  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return PlanSelectionView(
      header: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 76, 24, 20),
            child: OnboardingStepHeader(
              eyebrow: l10n.onboardingPlanEyebrow,
              title: l10n.onboardingPlanTitle,
              subtitle: l10n.onboardingPlanSubtitle,
              eyebrowColor: AppColors.starGold,
            ),
          ),
        ),
      ),
      onBack: onBack,
      onPlanActivated: onNext,
    );
  }
}
