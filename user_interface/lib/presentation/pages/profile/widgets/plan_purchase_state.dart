import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:lefture/domain/entities/credit_summary.dart';
import 'package:lefture/domain/entities/plan_option.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';

/// 無料トライアルの長さ。日数へ換算せず、ストアが返した単位のまま保持する。
///
/// App Store Connectの導入オファーは暦月単位(1ヶ月/2ヶ月/…)でしか設定できず、
/// 「1ヶ月 = 30日」と換算すると実際の長さとズレる —— 2月1日開始なら実際は
/// 28日しかないのに「30日間無料」と過大表示してしまう。自動更新法は
/// トライアル条件の正確な開示を求めるため、単位を落とさずそのまま表示する。
class TrialPeriod {
  const TrialPeriod({required this.count, required this.unit});

  final int count;
  final TrialPeriodUnit unit;

  /// 「1ヶ月」「30日間」等、文中に差し込むためのローカライズ済み期間表記。
  String localizedDuration(AppLocalizations l10n) {
    switch (unit) {
      case TrialPeriodUnit.day:
        return l10n.trialDurationDays(count);
      case TrialPeriodUnit.week:
        return l10n.trialDurationWeeks(count);
      case TrialPeriodUnit.month:
        return l10n.trialDurationMonths(count);
      case TrialPeriodUnit.year:
        return l10n.trialDurationYears(count);
    }
  }
}

/// purchases_flutterのPeriodUnitからunknownを除いたもの。unknownを弾いた形で
/// 保持することで、「単位が分からないのに期間を表示してしまう」状態を作れなくする。
enum TrialPeriodUnit { day, week, month, year }

/// 導入オファーの期間をTrialPeriodへ変換する。単位不明・0以下は
/// 正確に表示できないためnull(=トライアル表記を出さない)を返す。
TrialPeriod? _resolveTrialPeriod(IntroductoryPrice intro) {
  if (intro.periodNumberOfUnits <= 0) return null;
  switch (intro.periodUnit) {
    case PeriodUnit.day:
      return TrialPeriod(count: intro.periodNumberOfUnits, unit: TrialPeriodUnit.day);
    case PeriodUnit.week:
      return TrialPeriod(count: intro.periodNumberOfUnits, unit: TrialPeriodUnit.week);
    case PeriodUnit.month:
      return TrialPeriod(count: intro.periodNumberOfUnits, unit: TrialPeriodUnit.month);
    case PeriodUnit.year:
      return TrialPeriod(count: intro.periodNumberOfUnits, unit: TrialPeriodUnit.year);
    case PeriodUnit.unknown:
      return null;
  }
}

/// 1プラン分の「今の状態」。カードごとの表示にも、フローティングContinue
/// ボタン(選択中の1プランだけ)にも同じロジックで使う共通の導出結果。
class PlanPurchaseState {
  const PlanPurchaseState({
    required this.isCurrentPlan,
    required this.package,
    required this.priceLabel,
    this.trialPeriod,
  });

  final bool isCurrentPlan;
  final Package? package;
  final String priceLabel;

  /// 今このプランを購入したら受けられる無料トライアルの期間。対象外ならnull。
  /// App Store Connect側の導入オファー設定(introductoryPrice)と、この端末の
  /// Apple IDの資格(checkTrialOrIntroductoryPriceEligibility)の両方が
  /// 揃った時だけ入る。バックエンドのWeb向け判定は一切見ない。
  final TrialPeriod? trialPeriod;
}

/// RevenueCatのOfferings(current)の中から、storeProductIdと
/// StoreProduct.identifierが一致するPackageを探す。プラン購入・追加クレジット
/// パック購入の両方で使う共通ロジック(商品はどちらも同じcurrent Offeringに
/// 含まれている)。
Package? findPackageByProductId(Offerings? offerings, String? storeProductId) {
  if (storeProductId == null) return null;
  final availablePackages = offerings?.current?.availablePackages ?? const <Package>[];
  for (final pkg in availablePackages) {
    if (pkg.storeProduct.identifier == storeProductId) {
      return pkg;
    }
  }
  return null;
}

/// summary(現在のクレジット状況)とofferings(RevenueCatの価格情報)から、
/// 1プラン分の状態を導出する。isCurrentPlanはmonthlyAllocationMicroの
/// 一致で判定する(/billing/summaryはactiveなプランのidそのものを
/// 返さないため)。
PlanPurchaseState resolvePlanPurchaseState({
  required AppLocalizations l10n,
  required PlanOption plan,
  required CreditSummary? summary,
  required Offerings? offerings,
  Map<String, IntroEligibility>? introEligibility,
}) {
  final hasActivePlan = summary?.hasActivePlan ?? false;
  final monthlyAllocationMicro = summary?.monthlyAllocationMicro;
  final isCurrentPlan = hasActivePlan && monthlyAllocationMicro == plan.monthlyCreditAmountMicro;

  final package = plan.isStorePurchase ? findPackageByProductId(offerings, plan.storeProductId) : null;

  final String priceLabel;
  if (plan.isSelfServe) {
    priceLabel = l10n.creditDetailPriceFree;
  } else if (package != null) {
    priceLabel = package.storeProduct.priceString;
  } else {
    priceLabel = '—';
  }

  // 「App Store Connect側に無料の導入オファーが設定されている」かつ「この
  // Apple IDがその資格を持つ」かつ「まだこのプランに加入していない」時だけ
  // トライアル表記の対象にする。資格がunknown(取得失敗・Android)の場合は
  // 出さない —— 出してから課金される方が、出さずに無料だったより害が大きい。
  final intro = package?.storeProduct.introductoryPrice;
  final eligibility = introEligibility?[package?.storeProduct.identifier];
  final TrialPeriod? trialPeriod = (!isCurrentPlan &&
          intro != null &&
          intro.price == 0 &&
          eligibility?.status == IntroEligibilityStatus.introEligibilityStatusEligible)
      ? _resolveTrialPeriod(intro)
      : null;

  return PlanPurchaseState(
    isCurrentPlan: isCurrentPlan,
    package: package,
    priceLabel: priceLabel,
    trialPeriod: trialPeriod,
  );
}
