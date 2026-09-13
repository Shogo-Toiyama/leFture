// lib/presentation/pages/onboarding/widgets/onboarding_profile_step.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/application/profile/user_profile_provider.dart';
import 'package:lefture/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_illustrations.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_step_header.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// Single-screen profile setup: Bio → Interests → Future Goals.
/// Simplifies the former 3-step wizard into one scrollable, unified form.
class OnboardingProfileStep extends HookConsumerWidget {
  const OnboardingProfileStep({super.key, required this.onNext, required this.onBack});

  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final existing = ref.read(currentUserProfileProvider).asData?.value;

    final bioCtl = useTextEditingController(text: existing?.bio ?? '');
    final interestsCtl = useTextEditingController(text: existing?.interests ?? '');
    final dreamsCtl = useTextEditingController(text: existing?.futureGoals ?? '');

    // Rebuilds on keystrokes so the Continue button can enable/disable
    useListenable(bioCtl);

    final isSubmitting = useState(false);
    final canAdvance = bioCtl.text.trim().isNotEmpty;

    Future<void> submit() async {
      if (isSubmitting.value) return;
      isSubmitting.value = true;
      try {
        await ref.read(userProfileRepositoryProvider).updateProfile(
              bio: bioCtl.text.trim(),
              interests: interestsCtl.text.trim().isEmpty ? null : interestsCtl.text.trim(),
              futureGoals: dreamsCtl.text.trim().isEmpty ? null : dreamsCtl.text.trim(),
            );
        ref.read(lectureControllerProvider.notifier).pushOutboxNow();
        onNext();
      } finally {
        isSubmitting.value = false;
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
                    eyebrow: l10n.onboardingProfileEyebrow,
                    title: l10n.onboardingProfileTitle,
                    subtitle: l10n.onboardingProfileSubtitle,
                    eyebrowColor: AppColors.growthGreen,
                  ),
                  const SizedBox(height: 16),
                  const Center(child: ProfileStepIllustration()),
                  const SizedBox(height: 20),

                  // 1. Bio (あなたについて) - 順番: Bio → Interests → Future
                  _ProfileFieldCard(
                    title: l10n.onboardingProfileBioTitle,
                    subtitle: l10n.onboardingProfileBioSubtitle,
                    hint: l10n.makeProfileAboutYouHint,
                    controller: bioCtl,
                    minLines: 3,
                    maxLines: 5,
                    isRequired: true,
                  ),
                  const SizedBox(height: 16),

                  // 2. Interests (興味・関心)
                  _ProfileFieldCard(
                    title: l10n.onboardingProfileInterestsTitle,
                    subtitle: l10n.onboardingProfileInterestsSubtitle,
                    hint: l10n.makeProfileInterestsHint,
                    controller: interestsCtl,
                    minLines: 2,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 16),

                  // 3. Future Dreams / Goals (将来の目標)
                  _ProfileFieldCard(
                    title: l10n.onboardingProfileDreamsTitle,
                    subtitle: l10n.onboardingProfileDreamsSubtitle,
                    hint: l10n.makeProfileFutureDreamsHint,
                    controller: dreamsCtl,
                    minLines: 2,
                    maxLines: 4,
                  ),

                  const Spacer(),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.starGold,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: AppColors.universe.glassWhiteLow,
                        disabledForegroundColor: Colors.white38,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: isSubmitting.value ? null : (canAdvance ? submit : null),
                      child: isSubmitting.value
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : Text(
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

class _ProfileFieldCard extends StatelessWidget {
  const _ProfileFieldCard({
    required this.title,
    required this.subtitle,
    required this.hint,
    required this.controller,
    this.minLines = 2,
    this.maxLines = 4,
    this.isRequired = false,
  });

  final String title;
  final String subtitle;
  final String hint;
  final TextEditingController controller;
  final int minLines;
  final int maxLines;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (isRequired) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.growthGreen.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.growthGreen.withValues(alpha: 0.38)),
                ),
                child: const Text(
                  'REQUIRED',
                  style: TextStyle(
                    color: AppColors.growthGreen,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(color: AppColors.universe.textComet, fontSize: 12),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          minLines: minLines,
          maxLines: maxLines,
          style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppColors.universe.textComet.withValues(alpha: 0.55), fontSize: 13),
            filled: true,
            fillColor: AppColors.universe.glassWhiteLow,
            contentPadding: const EdgeInsets.all(12),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.universe.glassBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: AppColors.growthGreen, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}
