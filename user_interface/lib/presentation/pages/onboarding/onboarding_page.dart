// lib/presentation/pages/onboarding/onboarding_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lefture/app/routes.dart';
import 'package:lefture/application/credit/credit_providers.dart';
import 'package:lefture/application/purchases/purchases_providers.dart';
import 'package:lefture/core/services/recording_preferences.dart';
import 'package:lefture/core/utils/dev_log.dart';
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
const _stepNames = ['intro', 'language', 'profile', 'permissions', 'plan', 'done'];

String _stepName(int i) => (i >= 0 && i < _stepNames.length) ? _stepNames[i] : 'step$i';

/// 診断用: next()/back()/finish() を誰が呼んだかを、アプリ自身のコードの
/// スタックフレームだけ数件残す(プランを選ばずにDoneへ進んだ事例の切り分け用)。
String _callerFrames() => StackTrace.current
    .toString()
    .split('\n')
    .where((l) => l.contains('package:lefture/') && !l.contains('onboarding_page.dart'))
    .take(4)
    .map((l) => l.replaceFirst(RegExp(r'^#\d+\s+'), '').trim())
    .join(' <- ');

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
      DevLog.add('🧭 [Onboarding] now showing step ${step.value} (${_stepName(step.value)})');
      if (step.value == _totalSteps - 1) {
        DevLog.add('🧭 [Onboarding] reached done step -> markOnboardingCompleted');
        ref.read(userProfileRepositoryProvider).markOnboardingCompleted();
        final uid = supabase.auth.currentUser?.id;
        if (uid != null) {
          RecordingPreferences().setHasCompletedDeviceSetup(uid, true);
        }
      }
      return null;
    }, [step.value]);

    Future<void> finish() async {
      DevLog.add('🧭 [Onboarding] finish() at step ${step.value} (${_stepName(step.value)}) caller=${_callerFrames()}');
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
      DevLog.add(
        '🧭 [Onboarding] next() from step ${step.value} (${_stepName(step.value)}) '
        '-> ${_stepName(step.value + 1)} caller=${_callerFrames()}',
      );
      if (step.value < _totalSteps - 1) {
        step.value++;
      } else {
        finish();
      }
    }

    // 各ステップには「自分が表示中のときだけ次へ進める」next を渡す。画面の
    // 更新が遅れて古いステップがまだ見えている間に「続ける」を連打されても、
    // step が2つ以上進んで Plan を飛ばすことがないようにするため
    // (2026-11-23、Plan を選ばずに Done → ホームへ進んだ事例があった)。
    VoidCallback nextFrom(int index) => () {
          if (step.value != index) {
            DevLog.add(
              '🧭 [Onboarding] ignored next() from stale step $index (${_stepName(index)}); '
              'current step is ${step.value} (${_stepName(step.value)})',
            );
            return;
          }
          next();
        };

    void back() {
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      DevLog.add('🧭 [Onboarding] back() from step ${step.value} (${_stepName(step.value)})');
      if (step.value > 0) step.value--;
    }

    final steps = <Widget>[
      OnboardingIntroStep(onNext: nextFrom(0)),
      OnboardingLanguageStep(onNext: nextFrom(1), onBack: back),
      OnboardingProfileStep(onNext: nextFrom(2), onBack: back),
      OnboardingPermissionsStep(onNext: nextFrom(3), onBack: back),
      OnboardingPlanStep(onNext: nextFrom(4), onBack: back),
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
            // ★ スクロール通知はレイアウトの最中にも届く(内容の高さが変わって
            //   慣性スクロールが止まった時の ScrollEndNotification 等)。そこで直接
            //   書き換えると、デバッグビルドでは "Build scheduled during frame" の
            //   assertが markNeedsBuild の途中で投げられ、この画面の Element が
            //   「dirtyなのに再ビルド待ちの一覧に入っていない」状態で残る。以後は
            //   step を進めても再ビルドされず、画面が固まったように見える
            //   (2026-11-23 実機で再現)。フレーム処理中はフレームの後に回す。
            final schedulerPhase = SchedulerBinding.instance.schedulerPhase;
            if (schedulerPhase == SchedulerPhase.persistentCallbacks ||
                schedulerPhase == SchedulerPhase.midFrameMicrotasks) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) isHeaderVisible.value = shouldBeVisible;
              });
            } else {
              isHeaderVisible.value = shouldBeVisible;
            }
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
