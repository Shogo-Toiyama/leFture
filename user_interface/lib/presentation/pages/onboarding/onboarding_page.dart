// lib/presentation/pages/onboarding/onboarding_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lefture/app/routes.dart';
import 'package:lefture/core/services/recording_preferences.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:lefture/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_done_step.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_intro_step.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_language_step.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_permissions_step.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_plan_step.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_profile_step.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

import 'package:lefture/presentation/widgets/language_header_button.dart';

const _totalSteps = 6;

/// Account-creation-directly-after wizard: Intro → Language → Profile →
/// Permissions → Plan → Done. Each step renders its own back affordance (via
/// `OnboardingStepHeader`/`OnboardingBackButton`) since the profile step has
/// its own internal question-level back navigation in addition to the macro
/// step-level one.
///
/// 以前はここに「Tutorial」ステップ(プレースホルダーのスライド1枚)があったが、
/// 常設チュートリアル講義に置き換えたため一度削除した。その後、サインアップ
/// 直後にいきなりプロフィール入力が始まるのが急すぎたため、これから何をする
/// のか見せる導入スライド(Intro)と、言語設定ステップ(Language)を新たに
/// 先頭2ステップとして追加している。
class OnboardingPage extends HookConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = useState(0);

    // 「準備完了です」の完了ページ(Step 6)が表示された瞬間に自動でオンボーディング完了をマークする
    useEffect(() {
      if (step.value == _totalSteps - 1) {
        ref.read(userProfileRepositoryProvider).markOnboardingCompleted();
        final uid = supabase.auth.currentUser?.id;
        if (uid != null) {
          RecordingPreferences().setHasCompletedDeviceSetup(uid, true);
        }
      }
      return null;
    }, [step.value]);

    Future<void> finish() async {
      await ref.read(userProfileRepositoryProvider).markOnboardingCompleted();
      final uid = supabase.auth.currentUser?.id;
      if (uid != null) {
        await RecordingPreferences().setHasCompletedDeviceSetup(uid, true);
      }
      if (context.mounted) context.go(AppRoutes.home);
    }

    void next() {
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      if (step.value < _totalSteps - 1) {
        step.value++;
      } else {
        finish();
      }
    }

    void back() {
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      if (step.value > 0) step.value--;
    }

    final steps = <Widget>[
      OnboardingIntroStep(onNext: next),
      OnboardingLanguageStep(onNext: next, onBack: back),
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
