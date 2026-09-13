// lib/presentation/pages/onboarding/onboarding_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lefture/app/routes.dart';
import 'package:lefture/application/credit/credit_providers.dart';
import 'package:lefture/application/purchases/purchases_providers.dart';
import 'package:lefture/core/services/recording_preferences.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:lefture/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_done_step.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_intro_step.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_language_step.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_permissions_step.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_plan_step.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_profile_step.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_top_bar.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

import 'package:lefture/presentation/widgets/language_header_button.dart';

const _totalSteps = 6;
const _planStepIndex = 4;

/// Account-creation-directly-after wizard: Intro → Language → Profile →
/// Permissions → Plan → Done. Each step renders its own back affordance (via
/// `OnboardingStepHeader`/`OnboardingBackButton`) since the profile step has
/// its own internal question-level back navigation in addition to the macro
/// step-level one.
///
/// Planステップ(`_planStepIndex`)だけは他ステップの580px中央カラム+ヘッダーには
/// 収めず、アカウント設定のプラン画面と全く同じフルブリード表示にする
/// (`PlanSelectionView`を移植して使っているため)。
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
    final isHeaderVisible = useState(true);

    // ステップ遷移時はヘッダーを表示状態にリセット
    useEffect(() {
      isHeaderVisible.value = true;
      return null;
    }, [step.value]);

    // プランページ到達時のローディング待ちを解消するため、オンボーディング開始時からプリフェッチしておく
    ref.watch(claimablePlansProvider);
    ref.watch(creditSummaryProvider);
    ref.watch(revenueCatOfferingsProvider);

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

    final isPlanStep = step.value == _planStepIndex;
    final currentStep = steps[step.value];
    final topPadding = (step.value >= 1 && step.value <= 3) ? 76.0 : 12.0;
    final animatedChild = isPlanStep
        ? KeyedSubtree(key: ValueKey(step.value), child: currentStep)
        : SafeArea(
            key: ValueKey(step.value),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, topPadding, 24, 24),
                  child: currentStep,
                ),
              ),
            ),
          );

    Color? stepGradientColor;
    switch (step.value) {
      case 1: // Language
        stepGradientColor = AppColors.cosmicBlue;
      case 2: // Profile
        stepGradientColor = AppColors.growthGreen;
      case 3: // Permissions
        stepGradientColor = AppColors.alertAmber;
      default:
        stepGradientColor = null;
    }

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          final pixels = notification.metrics.pixels;
          final shouldBeVisible = pixels <= 15;
          if (isHeaderVisible.value != shouldBeVisible) {
            isHeaderVisible.value = shouldBeVisible;
          }
          return false;
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    gradient: stepGradientColor != null
                        ? LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              stepGradientColor.withValues(alpha: 0.32),
                              stepGradientColor.withValues(alpha: 0.10),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.18, 0.35],
                          )
                        : null,
                  ),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: animatedChild,
            ),
            if (step.value >= 1 && step.value <= 4)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                    child: AnimatedOpacity(
                      opacity: isHeaderVisible.value ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: IgnorePointer(
                        ignoring: !isHeaderVisible.value,
                        child: OnboardingTopBar(
                          onBack: back,
                          currentStepIndex: step.value - 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (step.value == 0)
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
      ),
    );
  }
}
