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
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_profile_step.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

import 'package:lefture/presentation/widgets/language_header_button.dart';

const _totalSteps = 4;

/// Account-creation-directly-after wizard: Profile → Permissions → Plan →
/// Done. Each step renders its own back affordance (via
/// `OnboardingStepHeader`/`OnboardingBackButton`) since the profile step has
/// its own internal question-level back navigation in addition to the macro
/// step-level one.
///
/// 以前はこの前に「Tutorial」ステップ(プレースホルダーのスライド1枚)が
/// あったが、常設チュートリアル講義に置き換えたため削除した。設定が全部
/// 終わってからHomePageを見せ、そこに最初から並んでいるチュートリアル講義を
/// ユーザー自身が開く形にする(自動遷移はしない)。
class OnboardingPage extends HookConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = useState(0);

    // 「準備完了です」の完了ページ(Step 4)が表示された瞬間に自動でオンボーディング完了をマークする
    useEffect(() {
      if (step.value == _totalSteps - 1) {
        ref.read(userProfileRepositoryProvider).markOnboardingCompleted();
      }
      return null;
    }, [step.value]);

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
      OnboardingProfileStep(onNext: next, onBack: back),
      OnboardingPermissionsStep(onNext: next, onBack: back),
      OnboardingPlanStep(onNext: next, onBack: back),
      OnboardingDoneStep(onFinish: finish),
    ];

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: KeyedSubtree(key: ValueKey(step.value), child: steps[step.value]),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 18,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: const LanguageHeaderButton(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
