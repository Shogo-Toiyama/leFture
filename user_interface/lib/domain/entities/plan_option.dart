/// GET /billing/plans が返す、無効化されていないクレジット配布プランの1件分。
/// claimModeが'self_serve'ならそのまま/billing/claim-planでclaimできるが、
/// 'store_purchase'の場合はここに含まれていても表示専用であり、実際の購入は
/// RevenueCat経由(Purchases.purchasePackage)でのみ行う。storeProductIdは
/// RevenueCatのPackage/StoreProductのidentifierと突き合わせるためのキー。
class PlanOption {
  const PlanOption({
    required this.id,
    required this.name,
    required this.monthlyCreditAmountMicro,
    required this.priceUsd,
    required this.billingIntervalMonths,
    required this.claimMode,
    required this.storeProductId,
  });

  final String id;
  final String name;
  final int monthlyCreditAmountMicro;
  final double? priceUsd;
  final int billingIntervalMonths;
  final String claimMode;
  final String? storeProductId;

  static const int _microCreditsPerCredit = 1000000;

  int get monthlyCreditAmountDisplay => monthlyCreditAmountMicro ~/ _microCreditsPerCredit;

  bool get isSelfServe => claimMode == 'self_serve';
  bool get isStorePurchase => claimMode == 'store_purchase';

  factory PlanOption.fromJson(Map<String, dynamic> json) {
    return PlanOption(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Plan',
      monthlyCreditAmountMicro: (json['monthly_credit_amount'] as num?)?.toInt() ?? 0,
      priceUsd: (json['price_usd'] as num?)?.toDouble(),
      billingIntervalMonths: (json['billing_interval_months'] as num?)?.toInt() ?? 1,
      claimMode: json['claim_mode'] as String? ?? 'self_serve',
      storeProductId: json['store_product_id'] as String?,
    );
  }
}
