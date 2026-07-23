/// バックエンドの GET /billing/summary が返す値をそのまま表現するモデル。
/// クレジット関連のテーブルはすべてRLSでクライアントから直接触れないため、
/// このエンティティは必ずこのAPI経由でのみ取得される(ローカルDBへの
/// キャッシュ・オフライン表示は今回のスコープでは行わない)。
class CreditSummary {
  const CreditSummary({
    required this.creditBalanceMicro,
    required this.monthlyAllocationMicro,
    required this.extraCreditBalanceMicro,
    required this.hasActivePlan,
    required this.currentPeriodEnd,
    required this.creditsPerUsd,
  });

  /// 1 表示クレジット = 1,000,000 内部単位(μクレジット)。バックエンドの
  /// MICRO_CREDITS_PER_USD = CREDITS_PER_USD * 1_000_000 と対応。
  static const int microCreditsPerCredit = 1000000;

  /// null = ユーザーがまだ一度もプランをclaimしていない
  /// (バックエンドのNO_CREDIT_ALLOCATIONに相当)。0以上は割り当て済み。
  final int? creditBalanceMicro;

  /// アクティブなプランの月次付与量。プラン未加入ならnull。
  final int? monthlyAllocationMicro;

  /// 月次付与とは別枠の追加クレジット(将来のストア課金購入分など)。
  final int extraCreditBalanceMicro;

  final bool hasActivePlan;
  final DateTime? currentPeriodEnd;
  final int creditsPerUsd;

  int? get creditBalanceDisplay =>
      creditBalanceMicro == null ? null : creditBalanceMicro! ~/ microCreditsPerCredit;

  int? get monthlyAllocationDisplay =>
      monthlyAllocationMicro == null ? null : monthlyAllocationMicro! ~/ microCreditsPerCredit;

  int get extraCreditBalanceDisplay => extraCreditBalanceMicro ~/ microCreditsPerCredit;

  /// 月次配分に対する残量割合(0.0〜1.0)。プログレスバーの`percent`にそのまま渡せる。
  /// プラン未加入・配分0の場合は0を返す(表示側は`hasActivePlan`で未加入を判定すること)。
  double get remainingFraction {
    final allocation = monthlyAllocationMicro;
    final balance = creditBalanceMicro;
    if (allocation == null || allocation <= 0 || balance == null) return 0;
    return (balance / allocation).clamp(0.0, 1.0);
  }

  /// 指定したUSD相当額以上のクレジットが残っているか。
  /// (例: Realtime文字起こしの$0.1しきい値判定)
  bool hasAtLeastUsd(double usd) {
    final balance = creditBalanceMicro;
    if (balance == null) return false;
    final thresholdMicro = (usd * creditsPerUsd * microCreditsPerCredit).round();
    return balance >= thresholdMicro;
  }

  factory CreditSummary.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) => v == null ? null : DateTime.parse(v as String);
    return CreditSummary(
      creditBalanceMicro: json['credit_balance'] as int?,
      monthlyAllocationMicro: json['monthly_allocation'] as int?,
      extraCreditBalanceMicro: (json['extra_credit_balance'] as int?) ?? 0,
      hasActivePlan: json['has_active_plan'] as bool? ?? false,
      currentPeriodEnd: parseDate(json['current_period_end']),
      creditsPerUsd: (json['credits_per_usd'] as int?) ?? 300,
    );
  }
}
