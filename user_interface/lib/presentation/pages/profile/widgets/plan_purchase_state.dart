import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:lefture/domain/entities/credit_summary.dart';
import 'package:lefture/domain/entities/plan_option.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';

/// 1プラン分の「今の状態」。カードごとの表示にも、フローティングContinue
/// ボタン(選択中の1プランだけ)にも同じロジックで使う共通の導出結果。
class PlanPurchaseState {
  const PlanPurchaseState({
    required this.isCurrentPlan,
    required this.package,
    required this.priceLabel,
  });

  final bool isCurrentPlan;
  final Package? package;
  final String priceLabel;
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

  return PlanPurchaseState(isCurrentPlan: isCurrentPlan, package: package, priceLabel: priceLabel);
}
