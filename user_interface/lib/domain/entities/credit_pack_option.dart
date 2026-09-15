/// GET /billing/credit-packs が返す、無効化されていない追加クレジットパック
/// (都度課金、非サブスク)の1件分。storeProductIdはRevenueCatのPackage/
/// StoreProductのidentifierと突き合わせるためのキー(plan_option.dartと同じ方針)。
/// プラン(サブスク)と違いtier比較・claimMode等は持たない単純な形。
class CreditPackOption {
  const CreditPackOption({
    required this.id,
    required this.name,
    required this.creditAmountMicro,
    required this.priceUsd,
    required this.storeProductId,
  });

  final String id;
  final String name;
  final int creditAmountMicro;
  final double? priceUsd;
  final String storeProductId;

  static const int _microCreditsPerCredit = 1000000;

  int get creditAmountDisplay => creditAmountMicro ~/ _microCreditsPerCredit;

  factory CreditPackOption.fromJson(Map<String, dynamic> json) {
    return CreditPackOption(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Credit Pack',
      creditAmountMicro: (json['credit_amount'] as num?)?.toInt() ?? 0,
      priceUsd: (json['price_usd'] as num?)?.toDouble(),
      storeProductId: json['store_product_id'] as String,
    );
  }
}
