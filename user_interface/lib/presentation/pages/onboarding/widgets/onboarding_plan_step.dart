// lib/presentation/pages/onboarding/widgets/onboarding_plan_step.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lefture/application/credit/credit_providers.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_step_header.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// Claims the real self-serve/beta plan (same `claimablePlansProvider` /
/// `claimPlan` used on the account credit-detail page) so a new user leaves
/// onboarding with an active plan already — instead of showing dummy plan
/// data and then having `HomePage` force them into a separate claim screen.
class OnboardingPlanStep extends HookConsumerWidget {
  const OnboardingPlanStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final summaryAsync = ref.watch(creditSummaryProvider);
    final plansAsync = ref.watch(claimablePlansProvider);
    final claiming = useState(false);
    final claimError = useState<String?>(null);

    final hasActivePlan = summaryAsync.asData?.value.hasActivePlan ?? false;
    final plans = plansAsync.asData?.value ?? const [];
    final plan = plans.isNotEmpty ? plans.first : null;

    Future<void> handleContinue() async {
      if (hasActivePlan || plan == null) {
        onNext();
        return;
      }
      claiming.value = true;
      claimError.value = null;
      try {
        await ref.read(creditRepositoryProvider).claimPlan(plan.id);
        ref.invalidate(creditSummaryProvider);
        ref.invalidate(claimablePlansProvider);
        onNext();
      } catch (e) {
        claimError.value = l10n.onboardingPlanClaimError;
      } finally {
        claiming.value = false;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OnboardingStepHeader(eyebrow: l10n.onboardingPlanEyebrow, title: l10n.onboardingPlanTitle),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.growthGreen.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: AppColors.growthGreen.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.growthGreen, size: 14),
              const SizedBox(width: 6),
              Text(
                l10n.onboardingPlanBadge,
                style: const TextStyle(color: AppColors.growthGreen, fontSize: 11.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          l10n.onboardingPlanSubtitle,
          style: TextStyle(color: AppColors.universe.textComet, fontSize: 13, height: 1.45),
        ),
        const SizedBox(height: 22),
        if (hasActivePlan)
          _PlanCard(
            title: l10n.onboardingPlanActiveTitle,
            subtitle: summaryAsync.asData?.value.monthlyAllocationDisplay != null
                ? l10n.creditDetailPlanSubtitle(summaryAsync.value!.monthlyAllocationDisplay!, 1)
                : null,
          )
        else
          plansAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(color: AppColors.starGold, strokeWidth: 2.5)),
            ),
            error: (err, _) => Text(
              l10n.creditDetailPlansLoadError,
              style: TextStyle(color: AppColors.universe.textComet, fontSize: 12.5),
            ),
            data: (_) => plan == null
                ? const SizedBox.shrink()
                : _PlanCard(
                    title: plan.name,
                    subtitle: l10n.creditDetailPlanSubtitle(plan.monthlyCreditAmountDisplay, plan.billingIntervalMonths),
                    priceLabel: (plan.priceUsd == null || plan.priceUsd == 0)
                        ? l10n.creditDetailPriceFree
                        : '\$${plan.priceUsd!.toStringAsFixed(2)}',
                  ),
          ),
        if (claimError.value != null) ...[
          const SizedBox(height: 12),
          Text(claimError.value!, style: const TextStyle(color: AppColors.correctionRed, fontSize: 12.5)),
          const SizedBox(height: 6),
          // Never trap the user here — HomePage already redirects anyone
          // without an active plan to the claim screen, so this is a safe
          // way out if claiming keeps failing (e.g. offline).
          TextButton(
            onPressed: onNext,
            style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
            child: Text(
              l10n.onboardingSkipButton,
              style: TextStyle(color: AppColors.universe.textComet, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
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
            onPressed: claiming.value ? null : handleContinue,
            child: claiming.value
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : Text(l10n.onboardingContinueButton, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.title, this.subtitle, this.priceLabel});

  final String title;
  final String? subtitle;
  final String? priceLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x28FFB300),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.starGold, width: 1.4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: TextStyle(color: AppColors.universe.textComet, fontSize: 12)),
                ],
              ],
            ),
          ),
          if (priceLabel != null) ...[
            const SizedBox(width: 12),
            Text(
              priceLabel!,
              style: const TextStyle(color: AppColors.starGold, fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ],
        ],
      ),
    );
  }
}
