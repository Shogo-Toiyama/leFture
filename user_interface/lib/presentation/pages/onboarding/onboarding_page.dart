// lib/presentation/pages/onboarding/onboarding_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lefture/app/routes.dart';
import 'package:lefture/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_done_step.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_permissions_step.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_plan_step.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_tutorial_step.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

const _totalSteps = 4;

/// Account-creation-directly-after wizard: Tutorial (placeholder) →
/// Permissions → Plan → Done. Profile setup itself lives on the empty
/// home screen's Profile → Course → Lecture checklist, not here.
class OnboardingPage extends HookConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = useState(0);

    Future<void> finish() async {
      await ref.read(userProfileRepositoryProvider).markOnboardingCompleted();
      if (context.mounted) context.go(AppRoutes.home);
    }

    void next() {
      if (step.value < _totalSteps - 1) {
        step.value++;
      } else {
        finish();
      }
    }

    void back() {
      if (step.value > 0) step.value--;
    }

    final steps = <Widget>[
      OnboardingTutorialStep(onNext: next),
      OnboardingPermissionsStep(onNext: next),
      OnboardingPlanStep(onNext: next),
      OnboardingDoneStep(onFinish: finish),
    ];

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 32,
                child: step.value > 0
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: back,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 18,
                              color: AppColors.universe.textComet,
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: KeyedSubtree(key: ValueKey(step.value), child: steps[step.value]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
