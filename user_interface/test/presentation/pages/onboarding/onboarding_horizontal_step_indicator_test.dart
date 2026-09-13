import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/presentation/pages/onboarding/widgets/onboarding_horizontal_step_indicator.dart';

void main() {
  testWidgets('OnboardingHorizontalStepIndicator renders 4 step icons', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OnboardingHorizontalStepIndicator(currentStepIndex: 0),
        ),
      ),
    );

    // 4つのアイコンが存在することを確認
    expect(find.byIcon(Icons.language_rounded), findsOneWidget);
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.workspace_premium_rounded), findsOneWidget);
  });

  testWidgets('OnboardingHorizontalStepIndicator handles step progression', (tester) async {
    for (var step = 0; step < 4; step++) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OnboardingHorizontalStepIndicator(currentStepIndex: step),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // レンダーエラーなく正常に遷移できること
      expect(find.byType(OnboardingHorizontalStepIndicator), findsOneWidget);
    }
  });
}
