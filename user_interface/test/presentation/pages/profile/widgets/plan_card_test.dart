import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/domain/entities/plan_option.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/profile/widgets/plan_card.dart';
import 'package:lefture/presentation/pages/profile/widgets/plan_purchase_state.dart';

void main() {
  Widget buildTestWidget({
    required PlanOption plan,
    Locale locale = const Locale('ja'),
    TextScaler textScaler = TextScaler.noScaling,
    double height = 600,
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: SingleChildScrollView(
            child: SizedBox(
              height: height,
              child: PlanCard(
                plan: plan,
                state: const PlanPurchaseState(
                  isCurrentPlan: false,
                  package: null,
                  priceLabel: '\$0',
                ),
                isPurchasing: false,
                isPendingTarget: false,
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('PlanCard feature checklist verification', () {
    final freePlan = PlanOption.fromJson({
      'id': 'p_free',
      'name': 'Free',
      'tier_level': 0,
      'claim_mode': 'self_serve',
      'monthly_credit_amount': 500000000,
    });

    final litePlan = PlanOption.fromJson({
      'id': 'p_lite',
      'name': 'Lite',
      'tier_level': 1,
      'claim_mode': 'store_purchase',
      'store_product_id': 'com.lefture.app.sub.starter',
      'monthly_credit_amount': 1200000000,
    });

    final corePlan = PlanOption.fromJson({
      'id': 'p_core',
      'name': 'Core',
      'tier_level': 2,
      'claim_mode': 'store_purchase',
      'store_product_id': 'com.lefture.app.sub.standard',
      'monthly_credit_amount': 2000000000,
    });

    final maxPlan = PlanOption.fromJson({
      'id': 'p_max',
      'name': 'Max',
      'tier_level': 3,
      'claim_mode': 'store_purchase',
      'store_product_id': 'com.lefture.app.sub.premium',
      'monthly_credit_amount': 3000000000,
    });

    testWidgets('Free plan shows: ✅ ❌ ❌ ❌ ❌ in Japanese with credit banner', (tester) async {
      await tester.pumpWidget(buildTestWidget(plan: freePlan, locale: const Locale('ja')));
      await tester.pump();

      expect(find.text('500 クレジット / 月'), findsOneWidget);
      expect(find.text('約週1回の講義'), findsOneWidget);

      expect(find.text('Review CardsとFun Fact生成'), findsOneWidget);
      expect(find.text('DeepNotes（詳細ノート）生成'), findsOneWidget);
      expect(find.text('トランスクリプト閲覧・出典検索'), findsOneWidget);
      expect(find.text('キーワード・アナウンスメント生成'), findsOneWidget);
      expect(find.text('リアルタイム文字起こし'), findsOneWidget);

      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(1));
      expect(find.byIcon(Icons.cancel_rounded), findsNWidgets(4));
    });

    testWidgets('Lite plan shows: ✅ ✅ ❌ ❌ ❌ in Japanese', (tester) async {
      await tester.pumpWidget(buildTestWidget(plan: litePlan, locale: const Locale('ja')));
      await tester.pump();

      expect(find.text('1,200 クレジット / 月'), findsOneWidget);
      expect(find.text('約週3回の講義'), findsOneWidget);

      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.cancel_rounded), findsNWidgets(3));
    });

    testWidgets('Core plan shows: ✅ ✅ ✅ ✅ ❌ in Japanese with credit banner', (tester) async {
      await tester.pumpWidget(buildTestWidget(plan: corePlan, locale: const Locale('ja')));
      await tester.pump();

      expect(find.text('2,000 クレジット / 月'), findsOneWidget);
      expect(find.text('約週5回の講義'), findsOneWidget);

      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(4));
      expect(find.byIcon(Icons.cancel_rounded), findsNWidgets(1));
    });

    testWidgets('Max plan shows: ✅ ✅ ✅ ✅ ✅ in Japanese', (tester) async {
      await tester.pumpWidget(buildTestWidget(plan: maxPlan, locale: const Locale('ja')));
      await tester.pump();

      expect(find.text('3,000 クレジット / 月'), findsOneWidget);
      expect(find.text('約週8回の講義'), findsOneWidget);

      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(5));
      expect(find.byIcon(Icons.cancel_rounded), findsNothing);
    });

    testWidgets('English localization shows English labels for all features and credit banner', (tester) async {
      await tester.pumpWidget(buildTestWidget(plan: maxPlan, locale: const Locale('en')));
      await tester.pump();

      expect(find.text('3,000 credits / month'), findsOneWidget);
      expect(find.text('Approx. 8 lectures / week'), findsOneWidget);

      expect(find.text('Review Cards & Fun Facts generation'), findsOneWidget);
      expect(find.text('DeepNotes (detailed notes) generation'), findsOneWidget);
      expect(find.text('Transcript viewing & source search'), findsOneWidget);
      expect(find.text('Keyword & announcement generation'), findsOneWidget);
      expect(find.text('Real-time transcription'), findsOneWidget);

      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(5));
    });

    testWidgets('PlanCard renders without overflow when text is scaled to 1.35x', (tester) async {
      const textScaler = TextScaler.linear(1.35);
      final scaledHeight = 450.0 * 1.35;

      await tester.pumpWidget(
        buildTestWidget(
          plan: corePlan,
          locale: const Locale('ja'),
          textScaler: textScaler,
          height: scaledHeight,
        ),
      );
      await tester.pump();

      expect(find.text('Core'), findsOneWidget);
      expect(find.text('2,000 クレジット / 月'), findsOneWidget);
      expect(find.text('約週5回の講義'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(4));
      // No FlutterError / overflow thrown
      expect(tester.takeException(), isNull);
    });
  });
}
