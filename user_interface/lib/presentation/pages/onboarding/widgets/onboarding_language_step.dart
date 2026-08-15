// lib/presentation/pages/onboarding/widgets/onboarding_language_step.dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lefture/application/profile/display_language_controller.dart';
import 'package:lefture/application/recording/recording_language_controller.dart';
import 'package:lefture/domain/entities/app_language.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_step_header.dart';
import 'package:lefture/presentation/pages/profile/widgets/language_selection_sheet.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// First real setup step, right after the intro/bridge step: pick the
/// display language (app UI text) and the recording language (on-device
/// transcription). Both pickers just reopen the same
/// [LanguageSelectionSheet] used elsewhere in the app, so the choice made
/// here and later from account settings always stay in sync.
class OnboardingLanguageStep extends HookConsumerWidget {
  const OnboardingLanguageStep({super.key, required this.onNext, required this.onBack});

  final VoidCallback onNext;
  final VoidCallback onBack;

  Future<void> _openSheet(BuildContext context, LanguageSheetMode mode) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => LanguageSelectionSheet(mode: mode),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    final displayCode = ref.watch(displayLanguageControllerProvider);
    final recordingCode = ref.watch(recordingLanguageControllerProvider);
    final displayLanguage = displayLanguageFromCode(displayCode);
    final recordingLanguage = recordingLanguageFromCode(recordingCode);

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
                    eyebrow: l10n.onboardingLanguageEyebrow,
                    title: l10n.onboardingLanguageTitle,
                    subtitle: l10n.onboardingLanguageSubtitle,
                    onBack: onBack,
                  ),
                  const SizedBox(height: 28),
                  _LanguageRow(
                    icon: Icons.language_rounded,
                    label: l10n.onboardingLanguageDisplayLabel,
                    description: l10n.onboardingLanguageDisplayDesc,
                    selected: displayLanguage,
                    onTap: () => _openSheet(context, LanguageSheetMode.display),
                  ),
                  const SizedBox(height: 12),
                  _LanguageRow(
                    icon: Icons.record_voice_over_outlined,
                    label: l10n.onboardingLanguageRecordingLabel,
                    description: l10n.onboardingLanguageRecordingDesc,
                    selected: recordingLanguage,
                    onTap: () => _openSheet(context, LanguageSheetMode.recording),
                  ),
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
                      onPressed: onNext,
                      child: Text(
                        l10n.onboardingContinueButton,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
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

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final AppLanguage selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.universe.glassWhiteLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.universe.glassBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.starGold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.starGold, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: AppColors.universe.textStarlight,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(color: AppColors.universe.textComet, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selected.nativeName,
                    style: const TextStyle(
                      color: AppColors.starGold,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, color: AppColors.universe.textComet, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
