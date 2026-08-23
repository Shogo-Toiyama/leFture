// lib/presentation/pages/onboarding/widgets/onboarding_permissions_step.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_step_header.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/permissions_panel.dart';

/// Continue only advances once every permission below has actually been
/// through the real OS prompt at least once (granted, denied, or
/// permanently denied all count — "denied" from a status the app has never
/// requested is the one state that blocks progress). Microphone is core to
/// the app, so an undetermined mic permission gets a short explanation
/// dialog first ("Continue" only ever triggers the system prompt — never
/// bypasses it, and never grants anything itself). Notification is a nice-
/// to-have, so an undetermined notification permission is requested
/// directly with no dialog in front of it. Battery-optimization exemption
/// (Android only) is mandatory — the app can otherwise get killed
/// mid-recording in the background with no visible error — so that dialog
/// only dismisses, it never offers a way past.
class OnboardingPermissionsStep extends HookConsumerWidget {
  const OnboardingPermissionsStep({super.key, required this.onNext, required this.onBack});

  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final specs = buildPermissionSpecs(l10n, isAndroid: Platform.isAndroid);
    final permState = usePermissionsStatus(specs.map((s) => s.permission).toList());

    Future<void> handleContinue() async {
      final missingRequired = specs.where((s) => s.required && !permState.isGranted(s.permission));

      if (missingRequired.isNotEmpty) {
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
        return;
      }

      // Microphone is core to the app: explain why before routing to the
      // real system prompt. "Continue" never grants anything itself — it
      // only ever triggers Permission.microphone.request() below.
      if (permState.isUndetermined(Permission.microphone)) {
        final shouldContinue = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1E1F29),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              l10n.onboardingPermissionsMicDialogTitle,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: Text(
              l10n.onboardingPermissionsMicDialogMessage,
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  l10n.onboardingPermissionsMicDialogCancel,
                  style: TextStyle(color: AppColors.universe.textComet),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  l10n.onboardingPermissionsMicDialogContinue,
                  style: const TextStyle(color: AppColors.starGold, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
        if (shouldContinue != true) return;
        await permState.requestOne(Permission.microphone);
      }

      // Notification is optional, so it's requested directly with no
      // explanation dialog in front of it.
      if (permState.isUndetermined(Permission.notification)) {
        await permState.requestOne(Permission.notification);
      }

      onNext();
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
                  PermissionsRows(specs: specs, state: permState),
                  const SizedBox(height: 20),
                  AllowAllPermissionsButton(specs: specs, state: permState),
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
                      onPressed: permState.loading ? null : handleContinue,
                      child: Text(l10n.onboardingContinueButton, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
