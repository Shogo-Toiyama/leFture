import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_back_button.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_horizontal_step_indicator.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_top_bar.dart';
import 'package:lefture/presentation/widgets/language_header_button.dart';

import 'package:lefture/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('OnboardingTopBar renders back button, indicator, and language button', (tester) async {
    var backTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: OnboardingTopBar(
            onBack: () => backTapped = true,
            currentStepIndex: 1,
          ),
        ),
      ),
    );

    // 戻るボタン、インジケーター、言語ボタンが存在することを確認
    expect(find.byType(OnboardingBackButton), findsOneWidget);
    expect(find.byType(OnboardingHorizontalStepIndicator), findsOneWidget);
    expect(find.byType(LanguageHeaderButton), findsOneWidget);

    // 戻るボタンをタップできることを確認
    await tester.tap(find.byType(OnboardingBackButton));
    expect(backTapped, isTrue);
  });
}
