/// GET /billing/plans が返す、今claimできる(claim_mode='self_serve'かつ
/// 無効化されていない)プランの1件分。
class PlanOption {
  const PlanOption({
    required this.id,
    required this.name,
    required this.monthlyCreditAmountMicro,
    required this.priceUsd,
    required this.billingIntervalMonths,
  });

  final String id;
  final String name;
  final int monthlyCreditAmountMicro;
  final double? priceUsd;
  final int billingIntervalMonths;

  static const int _microCreditsPerCredit = 1000000;

  int get monthlyCreditAmountDisplay => monthlyCreditAmountMicro ~/ _microCreditsPerCredit;

  factory PlanOption.fromJson(Map<String, dynamic> json) {
    return PlanOption(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Plan',
      monthlyCreditAmountMicro: (json['monthly_credit_amount'] as num?)?.toInt() ?? 0,
      priceUsd: (json['price_usd'] as num?)?.toDouble(),
      billingIntervalMonths: (json['billing_interval_months'] as num?)?.toInt() ?? 1,
    );
  }
}
