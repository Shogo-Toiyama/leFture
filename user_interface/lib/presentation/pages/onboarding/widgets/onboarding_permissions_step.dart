// lib/presentation/pages/onboarding/widgets/onboarding_permissions_step.dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_step_header.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

class OnboardingPermissionsStep extends StatefulWidget {
  const OnboardingPermissionsStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  State<OnboardingPermissionsStep> createState() => _OnboardingPermissionsStepState();
}

class _OnboardingPermissionsStepState extends State<OnboardingPermissionsStep> {
  bool _requesting = false;

  Future<void> _continue() async {
    setState(() => _requesting = true);
    // Priming screen only — proceed regardless of grant/deny so onboarding
    // never gets stuck on an OS permission dialog.
    await [Permission.microphone, Permission.notification].request();
    if (!mounted) return;
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OnboardingStepHeader(
          eyebrow: l10n.onboardingPermissionsEyebrow,
          title: l10n.onboardingPermissionsTitle,
          subtitle: l10n.onboardingPermissionsSubtitle,
        ),
        const SizedBox(height: 28),
        _PermissionRow(
          icon: Icons.mic_none_rounded,
          iconColor: AppColors.starGold,
          title: l10n.onboardingPermissionsMicTitle,
          subtitle: l10n.onboardingPermissionsMicSubtitle,
        ),
        const SizedBox(height: 12),
        _PermissionRow(
          icon: Icons.notifications_none_rounded,
          iconColor: AppColors.cosmicBlue,
          title: l10n.onboardingPermissionsNotifTitle,
          subtitle: l10n.onboardingPermissionsNotifSubtitle,
        ),
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
            onPressed: _requesting ? null : _continue,
            child: _requesting
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

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.universe.glassWhiteLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: AppColors.universe.textComet, fontSize: 11.5, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
