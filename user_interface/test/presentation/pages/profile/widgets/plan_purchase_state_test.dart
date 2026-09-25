import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:lefture/domain/entities/credit_summary.dart';
import 'package:lefture/domain/entities/plan_option.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/profile/widgets/plan_purchase_state.dart';

/// 無料トライアル表記の判定は「App Store Connectに無料の導入オファーがある」
/// かつ「このApple IDがその資格を持つ」の両方が揃った時だけtrueになる必要がある。
/// 資格不明(取得失敗・Android)で出してしまうと「無料と書いてあるのに課金された」
/// になるため、ここを退行させないよう固定する。
void main() {
  const maxProductId = 'com.lefture.app.sub.premium';

  final maxPlan = PlanOption.fromJson({
    'id': 'p_max',
    'name': 'Max',
    'tier_level': 3,
    'claim_mode': 'store_purchase',
    'store_product_id': maxProductId,
    'monthly_credit_amount': 3000000000,
  });

  StoreProduct productWith(IntroductoryPrice? intro) => StoreProduct(
        maxProductId,
        'Max plan',
        'Max',
        29.99,
        '\$29.99',
        'USD',
        introductoryPrice: intro,
      );

  Offerings offeringsWith(StoreProduct product) {
    const context = PresentedOfferingContext('default', null, null);
    final package = Package('\$rc_monthly', PackageType.monthly, product, context);
    final offering = Offering('default', 'default offering', const {}, [package]);
    return Offerings({'default': offering}, current: offering);
  }

  IntroEligibility eligibility(IntroEligibilityStatus status) =>
      IntroEligibility.fromJson({'status': status.index, 'description': status.name});

  const freeTrialOneMonth = IntroductoryPrice(0, '\$0.00', 'P1M', 1, PeriodUnit.month, 1);

  late AppLocalizations l10n;

  setUp(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  PlanPurchaseState resolve({
    required IntroductoryPrice? intro,
    IntroEligibilityStatus? status,
    CreditSummary? summary,
  }) {
    return resolvePlanPurchaseState(
      l10n: l10n,
      plan: maxPlan,
      summary: summary,
      offerings: offeringsWith(productWith(intro)),
      introEligibility: status == null ? null : {maxProductId: eligibility(status)},
    );
  }

  test('reports the trial length when a free intro offer exists and the Apple ID is eligible', () {
    final state = resolve(
      intro: freeTrialOneMonth,
      status: IntroEligibilityStatus.introEligibilityStatusEligible,
    );

    expect(state.trialPeriod?.count, 1);
    expect(state.trialPeriod?.unit, TrialPeriodUnit.month);
  });

  test('reports no trial when the Apple ID is ineligible (e.g. already used it on this Apple ID)', () {
    final state = resolve(
      intro: freeTrialOneMonth,
      status: IntroEligibilityStatus.introEligibilityStatusIneligible,
    );

    expect(state.trialPeriod, isNull);
  });

  test('reports no trial when eligibility is unknown or was not fetched', () {
    expect(
      resolve(
        intro: freeTrialOneMonth,
        status: IntroEligibilityStatus.introEligibilityStatusUnknown,
      ).trialPeriod,
      isNull,
    );
    expect(resolve(intro: freeTrialOneMonth).trialPeriod, isNull);
  });

  test('reports no trial when the product has no intro offer configured', () {
    final state = resolve(
      intro: null,
      status: IntroEligibilityStatus.introEligibilityStatusEligible,
    );

    expect(state.trialPeriod, isNull);
  });

  test('reports no trial for a paid (non-zero) intro offer, which is a discount rather than a trial', () {
    const discountedIntro = IntroductoryPrice(9.99, '\$9.99', 'P1M', 1, PeriodUnit.month, 1);

    final state = resolve(
      intro: discountedIntro,
      status: IntroEligibilityStatus.introEligibilityStatusEligible,
    );

    expect(state.trialPeriod, isNull);
  });

  test('reports no trial on the plan the user is already subscribed to', () {
    final state = resolve(
      intro: freeTrialOneMonth,
      status: IntroEligibilityStatus.introEligibilityStatusEligible,
      summary: const CreditSummary(
        creditBalanceMicro: 3000000000,
        monthlyAllocationMicro: 3000000000,
        extraCreditBalanceMicro: 0,
        hasActivePlan: true,
        currentPeriodEnd: null,
        pendingPlanId: null,
        creditsPerUsd: 100,
        tierLevel: 3,
        gatingDisabled: false,
        suspended: false,
      ),
    );

    expect(state.isCurrentPlan, isTrue);
    expect(state.trialPeriod, isNull);
  });

  test('keeps the store-reported unit instead of converting it to an approximate day count', () {
    // 1ヶ月を30日と換算すると2月開始時に「30日間無料」と過大表示してしまうため、
    // 単位は落とさずそのまま保持する。
    const oneWeek = IntroductoryPrice(0, '\$0.00', 'P1W', 1, PeriodUnit.week, 1);
    const twoMonths = IntroductoryPrice(0, '\$0.00', 'P2M', 1, PeriodUnit.month, 2);

    final weekState = resolve(intro: oneWeek, status: IntroEligibilityStatus.introEligibilityStatusEligible);
    expect(weekState.trialPeriod?.count, 1);
    expect(weekState.trialPeriod?.unit, TrialPeriodUnit.week);

    final monthState = resolve(intro: twoMonths, status: IntroEligibilityStatus.introEligibilityStatusEligible);
    expect(monthState.trialPeriod?.count, 2);
    expect(monthState.trialPeriod?.unit, TrialPeriodUnit.month);
  });

  test('reports no trial when the store reports an unknown period unit', () {
    const unknownUnit = IntroductoryPrice(0, '\$0.00', 'P1M', 1, PeriodUnit.unknown, 1);

    expect(
      resolve(intro: unknownUnit, status: IntroEligibilityStatus.introEligibilityStatusEligible).trialPeriod,
      isNull,
    );
  });
}
