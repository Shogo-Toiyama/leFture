// lib/presentation/pages/onboarding/widgets/onboarding_permissions_step.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_step_header.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/permissions_panel.dart';

/// Mic + notification are nudged but skippable (a confirm dialog lets the
/// user continue anyway). Battery-optimization exemption (Android only) is
/// mandatory — the app can otherwise get killed mid-recording in the
/// background with no visible error, so that dialog only dismisses, it
/// never offers a bypass.
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
      final missingOptional = specs.where((s) => !s.required && !permState.isGranted(s.permission));

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

      if (missingOptional.isNotEmpty) {
        final shouldContinue = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1E1F29),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              l10n.onboardingPermissionsOptionalDialogTitle,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: Text(
              l10n.onboardingPermissionsOptionalDialogMessage,
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  l10n.onboardingPermissionsOptionalDialogCancel,
                  style: TextStyle(color: AppColors.universe.textComet),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  l10n.onboardingPermissionsOptionalDialogContinue,
                  style: const TextStyle(color: AppColors.starGold, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
        if (shouldContinue != true) return;
      }

      onNext();
    }

    return Column(
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
    );
  }
}
