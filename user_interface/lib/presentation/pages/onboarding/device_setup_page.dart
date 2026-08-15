// lib/presentation/pages/onboarding/device_setup_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lefture/app/routes.dart';
import 'package:lefture/core/services/recording_preferences.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_language_step.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_permissions_step.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/language_header_button.dart';

const _totalSteps = 2;

/// 既存ユーザーが新しい端末でログインした際に表示する軽量セットアップウィザード:
/// Step 0: Language (表示言語 & 録音言語の確認・設定)
/// Step 1: Permissions (マイク・通知・Androidバッテリー最適化の権限許可)
class DeviceSetupPage extends HookConsumerWidget {
  const DeviceSetupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = useState(0);

    Future<void> finish() async {
      final uid = supabase.auth.currentUser?.id;
      if (uid != null) {
        await RecordingPreferences().setHasCompletedDeviceSetup(uid, true);
      }
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
      OnboardingLanguageStep(onNext: next, onBack: () {}),
      OnboardingPermissionsStep(onNext: next, onBack: back),
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
                    child: KeyedSubtree(
                      key: ValueKey(step.value),
                      child: steps[step.value],
                    ),
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
