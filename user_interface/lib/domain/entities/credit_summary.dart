import '../plan_features.dart' as plan_features;

/// バックエンドの GET /billing/summary が返す値をそのまま表現するモデル。
/// クレジット関連のテーブルはすべてRLSでクライアントから直接触れないため、
/// このエンティティは必ずこのAPI経由でのみ取得される(ローカルDBへの
/// キャッシュ・オフライン表示は今回のスコープでは行わない)。
///
/// tierLevelも同じレスポンスに乗っている(機能ゲート判定用)。専用の取得経路を
/// 増やさず、既に常時watchされているこのモデルにそのまま相乗りさせている。
class CreditSummary {
  const CreditSummary({
    required this.creditBalanceMicro,
    required this.monthlyAllocationMicro,
    required this.extraCreditBalanceMicro,
    required this.hasActivePlan,
    required this.currentPeriodEnd,
    required this.pendingPlanId,
    required this.creditsPerUsd,
    required this.tierLevel,
    required this.gatingDisabled,
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

  /// 現在アクティブなプランに、次回更新日で切り替わる予定の別プランのid。
  /// Apple同一サブスクグループ内のダウングレード/クロスグレードは即時反映
  /// されず「予約」されるだけなため、それを可視化するための値。予約が
  /// 無ければnull。
  final String? pendingPlanId;

  final int creditsPerUsd;

  /// 0=Free, 1=Lite, 2=Core, 3=Max。有効なプラン割当が無い場合はtierFree(0)扱い
  /// (バックエンドのget_user_tier_levelと同じフォールバック方針)。
  final int tierLevel;

  /// サーバー側のkill-switch(GATING_DISABLED_FOR_ALL_USERS)がこのユーザーに
  /// 効いているか。実機テスト用にREAL_GATING_TEST_USER_IDSへ登録された
  /// アカウントだけfalseになり、本来のtierLevel判定を受ける。
  final bool gatingDisabled;

  /// この機能がtierLevel的に使えるかどうか(plan_features.dart参照)。
  bool hasFeature(String featureKey) =>
      plan_features.hasFeature(tierLevel, featureKey, gatingDisabled: gatingDisabled);

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

  /// 指定した表示クレジット数以上の残高があるか。
  /// (例: Realtime文字起こしの最低クレジットしきい値判定)
  bool hasAtLeastCredits(int credits) {
    final balance = creditBalanceMicro;
    if (balance == null) return false;
    return balance >= credits * microCreditsPerCredit;
  }

  factory CreditSummary.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) => v == null ? null : DateTime.parse(v as String);
    return CreditSummary(
      creditBalanceMicro: json['credit_balance'] as int?,
      monthlyAllocationMicro: json['monthly_allocation'] as int?,
      extraCreditBalanceMicro: (json['extra_credit_balance'] as int?) ?? 0,
      hasActivePlan: json['has_active_plan'] as bool? ?? false,
      currentPeriodEnd: parseDate(json['current_period_end']),
      pendingPlanId: json['pending_plan_id'] as String?,
      creditsPerUsd: (json['credits_per_usd'] as int?) ?? 300,
      tierLevel: (json['tier_level'] as int?) ?? plan_features.tierFree,
      // フィールド欠落時(古いキャッシュ等)はこれまで通りの「全機能開放」に倒す。
      gatingDisabled: (json['gating_disabled'] as bool?) ?? true,
    );
  }
}
