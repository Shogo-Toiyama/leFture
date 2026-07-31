// lib/presentation/pages/onboarding/widgets/onboarding_tutorial_step.dart
import 'package:flutter/material.dart';

import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

class _TutorialSlide {
  const _TutorialSlide({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
}

/// First onboarding step. Placeholder content only — real slides (dummy-data
/// screenshots or a designed deck) will replace [_slides] later. The
/// PageView + dot indicator below already support multiple entries, so
/// extending this to ~3 slides is just appending to that list.
class OnboardingTutorialStep extends StatefulWidget {
  const OnboardingTutorialStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  State<OnboardingTutorialStep> createState() => _OnboardingTutorialStepState();
}

class _OnboardingTutorialStepState extends State<OnboardingTutorialStep> {
  final _pageController = PageController();
  int _slideIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final slides = [
      _TutorialSlide(title: l10n.onboardingTutorialTitle, subtitle: l10n.onboardingTutorialSubtitle),
    ];
    final isLastSlide = _slideIndex == slides.length - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'le',
                  style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const Text('F', style: TextStyle(color: AppColors.starGold, fontSize: 16, fontWeight: FontWeight.w800)),
                Text(
                  'ture',
                  style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            TextButton(
              onPressed: widget.onNext,
              child: Text(
                l10n.onboardingSkipButton,
                style: TextStyle(color: AppColors.universe.textComet, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          l10n.onboardingTutorialEyebrow,
          style: TextStyle(
            color: AppColors.universe.textComet,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: slides.length,
            onPageChanged: (i) => setState(() => _slideIndex = i),
            itemBuilder: (context, i) {
              final slide = slides[i];
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.universe.glassBorder, width: 1.5),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: AppColors.universe.textComet, size: 30),
                    const SizedBox(height: 14),
                    Text(
                      slide.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      slide.subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.universe.textComet, fontSize: 12.5, height: 1.4),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        if (slides.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < slides.length; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _slideIndex ? AppColors.universe.textComet : AppColors.universe.glassBorder,
                      ),
                    ),
                ],
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.starGold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: isLastSlide
                ? widget.onNext
                : () => _pageController.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
            child: Text(
              isLastSlide ? l10n.onboardingContinueButton : l10n.onboardingNextButton,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }
}
