// lib/presentation/pages/onboarding/widgets/onboarding_profile_step.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/application/profile/user_profile_provider.dart';
import 'package:lefture/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_back_button.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

class _ProfileQuestion {
  const _ProfileQuestion({
    required this.title,
    required this.subtitle,
    required this.hint,
    required this.controller,
    required this.maxLines,
    required this.required,
  });

  final String title;
  final String subtitle;
  final String hint;
  final TextEditingController controller;
  final int maxLines;
  final bool required;
}

/// One-question-per-screen profile setup: Interests → Future Dreams → Bio.
/// Interests/Dreams are the easy, concrete questions and go first; Bio is
/// last (and the only required one — matches `MakeProfileSheet`'s existing
/// validation) since by then the user is warmed up for something reflective.
class OnboardingProfileStep extends HookConsumerWidget {
  const OnboardingProfileStep({super.key, required this.onNext, required this.onBack});

  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final existing = ref.read(currentUserProfileProvider).asData?.value;

    final interestsCtl = useTextEditingController(text: existing?.interests ?? '');
    final dreamsCtl = useTextEditingController(text: existing?.futureGoals ?? '');
    final bioCtl = useTextEditingController(text: existing?.bio ?? '');
    // Rebuilds on every keystroke so the Bio question's Continue button can
    // react to it becoming non-empty.
    useListenable(bioCtl);

    final qIndex = useState(0);
    final isSubmitting = useState(false);

    final questions = [
      _ProfileQuestion(
        title: l10n.onboardingProfileInterestsTitle,
        subtitle: l10n.onboardingProfileInterestsSubtitle,
        hint: l10n.makeProfileInterestsHint,
        controller: interestsCtl,
        maxLines: 2,
        required: false,
      ),
      _ProfileQuestion(
        title: l10n.onboardingProfileDreamsTitle,
        subtitle: l10n.onboardingProfileDreamsSubtitle,
        hint: l10n.makeProfileFutureDreamsHint,
        controller: dreamsCtl,
        maxLines: 2,
        required: false,
      ),
      _ProfileQuestion(
        title: l10n.onboardingProfileBioTitle,
        subtitle: l10n.onboardingProfileBioSubtitle,
        hint: l10n.makeProfileAboutYouHint,
        controller: bioCtl,
        maxLines: 4,
        required: true,
      ),
    ];

    final q = questions[qIndex.value];
    final isLast = qIndex.value == questions.length - 1;
    final canAdvance = !q.required || q.controller.text.trim().isNotEmpty;

    Future<void> submit() async {
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

    void handlePrimary() {
      if (isLast) {
        submit();
      } else {
        qIndex.value++;
      }
    }

    void handleBack() {
      if (qIndex.value > 0) {
        qIndex.value--;
      } else {
        onBack();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OnboardingBackButton(onTap: handleBack),
        const SizedBox(height: 16),
        Row(
          children: [
            for (var i = 0; i < questions.length; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= qIndex.value ? AppColors.starGold : AppColors.universe.glassWhiteLow,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Text(
          l10n.onboardingProfileStepCounter(qIndex.value + 1, questions.length),
          style: TextStyle(
            color: AppColors.universe.textComet,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          q.title,
          style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(q.subtitle, style: TextStyle(color: AppColors.universe.textComet, fontSize: 13, height: 1.4)),
        const SizedBox(height: 20),
        TextField(
          key: ValueKey(qIndex.value),
          controller: q.controller,
          maxLines: q.maxLines,
          style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 14),
          decoration: InputDecoration(
            hintText: q.hint,
            hintStyle: TextStyle(color: AppColors.universe.textComet.withValues(alpha: 0.55)),
            filled: true,
            fillColor: AppColors.universe.glassWhiteLow,
            contentPadding: const EdgeInsets.all(14),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.universe.glassBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: AppColors.starGold),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        if (q.required) ...[
          const SizedBox(height: 8),
          Text(
            l10n.onboardingProfileBioRequiredNote,
            style: TextStyle(color: AppColors.universe.textComet, fontSize: 11.5),
          ),
        ],
        const Spacer(),
        if (!q.required)
          Center(
            child: TextButton(
              onPressed: isSubmitting.value ? null : handlePrimary,
              child: Text(
                l10n.onboardingSkipButton,
                style: TextStyle(color: AppColors.universe.textComet, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.starGold,
              foregroundColor: Colors.black,
              disabledBackgroundColor: AppColors.universe.glassWhiteLow,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: isSubmitting.value ? null : (canAdvance ? handlePrimary : null),
            child: isSubmitting.value
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : Text(
                    isLast ? l10n.onboardingContinueButton : l10n.onboardingNextButton,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
          ),
        ),
      ],
    );
  }
}
