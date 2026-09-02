// lib/presentation/pages/onboarding/widgets/onboarding_permissions_step.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_step_header.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/permissions_panel.dart';

/// Apple's 5.1.1(iv) forbids a custom message in front of a permission
/// request when the button that dismisses it doesn't say "Continue" or
/// "Next" — so this step no longer shows any custom pre-permission copy or
/// per-permission tiles at all. The single "Continue" button below is the
/// entire UI: tapping it walks through each OS permission prompt directly
/// (mic, notification, and — Android only — the battery-optimization
/// exemption), in order, with no explanatory dialog in front of any of
/// them. Already-granted permissions are skipped.
///
/// Battery-optimization exemption (Android only) is mandatory — the app can
/// otherwise get killed mid-recording in the background with no visible
/// error — so if it's still missing after the request above, a dialog
/// blocks progress until it's granted. That dialog only dismisses; it never
/// offers a way past. (This one isn't a pre-permission message — it's shown
/// after the real OS prompt has already run, so 5.1.1(iv) doesn't apply.)
class OnboardingPermissionsStep extends HookConsumerWidget {
  const OnboardingPermissionsStep({super.key, required this.onNext, required this.onBack});

  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final specs = buildPermissionSpecs(l10n, isAndroid: Platform.isAndroid);
    final permState = usePermissionsStatus(specs.map((s) => s.permission).toList());
    final isRequesting = useState(false);

    Future<void> handleContinue() async {
      if (isRequesting.value) return;
      isRequesting.value = true;
      try {
        for (final spec in specs) {
          final status = await spec.permission.status;
          if (!status.isGranted && !status.isPermanentlyDenied && !status.isRestricted) {
            await spec.permission.request();
          }
        }
        await permState.refresh();

        for (final spec in specs.where((s) => s.required)) {
          final status = await spec.permission.status;
          if (!status.isGranted) {
            if (context.mounted) {
              await showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF1E1F29),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Text(
                    l10n.onboardingPermissionsRequiredDialogTitle,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  content: Text(
                    l10n.onboardingPermissionsRequiredDialogMessage,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        l10n.onboardingPermissionsRequiredDialogButton,
                        style: const TextStyle(color: AppColors.starGold, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              );
            }
            return;
          }
        }

        onNext();
      } finally {
        isRequesting.value = false;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OnboardingStepHeader(
                    eyebrow: l10n.onboardingPermissionsEyebrow,
                    title: l10n.onboardingPermissionsTitle,
                    subtitle: l10n.onboardingPermissionsSubtitle,
                    onBack: onBack,
                  ),
                  const SizedBox(height: 28),
                  PermissionsRows(specs: specs, state: permState, isOnboarding: true),
                  const Spacer(),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.starGold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: (isRequesting.value || permState.loading) ? null : handleContinue,
                      child: isRequesting.value
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                            )
                          : Text(l10n.onboardingContinueButton, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
