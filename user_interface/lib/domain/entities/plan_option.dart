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
    required this.subtitles,
    required this.tierLevel,
  });

  final String id;
  final String name;
  final int monthlyCreditAmountMicro;
  final double? priceUsd;
  final int billingIntervalMonths;
  final String claimMode;
  final String? storeProductId;

  /// 言語コード({"en": "...", "ja": "..."})→マーケティング用サブタイトルの
  /// マップ。カラム追加なしで言語を増やせるよう、DB側は1つのjsonb列で持つ。
  final Map<String, String> subtitles;

  /// Free=0, Entry=1, Standard=2, Premium=3 の表示順。monthly_credit_amountで
  /// ソートすると(Freeのcredit量が暫定的にEntryより多いため)意図した並びに
  /// ならないので、表示順は必ずこの値でソートする。
  final int tierLevel;

  static const int _microCreditsPerCredit = 1000000;

  int get monthlyCreditAmountDisplay => monthlyCreditAmountMicro ~/ _microCreditsPerCredit;

  bool get isSelfServe => claimMode == 'self_serve';
  bool get isStorePurchase => claimMode == 'store_purchase';

  /// マーケティング用サブタイトル。DB側の内容はプレーン文字列(nameと同様に
  /// アプリのl10nシステムを経由しない)なので、languageCodeで単純に出し分ける。
  /// 該当言語が無ければ'en'にフォールバックする。
  String? localizedSubtitle(String languageCode) {
    final direct = subtitles[languageCode];
    if (direct != null && direct.isNotEmpty) return direct;
    return subtitles['en'];
  }

  static int _resolveTierLevel(dynamic rawTier, String name) {
    if (rawTier is num && rawTier.toInt() > 0) {
      return rawTier.toInt();
    }
    switch (name.trim().toLowerCase()) {
      case 'free':
        return 0;
      case 'entry':
        return 1;
      case 'standard':
        return 2;
      case 'premium':
        return 3;
      default:
        return (rawTier is num) ? rawTier.toInt() : 0;
    }
  }

  static const Map<String, Map<String, String>> _defaultSubtitles = {
    'free': {
      'en': 'Start your learning journey',
      'ja': '学びの旅を始めよう',
    },
    'entry': {
      'en': 'Perfect for regular study',
      'ja': '日々の学習にぴったり',
    },
    'standard': {
      'en': 'For serious, consistent learners',
      'ja': '本気で学びたい人へ',
    },
    'premium': {
      'en': 'Unlock your full potential',
      'ja': '可能性を最大限に引き出そう',
    },
  };

  static Map<String, String> _resolveSubtitles(dynamic rawSubtitles, String name) {
    if (rawSubtitles is Map && rawSubtitles.isNotEmpty) {
      return rawSubtitles.map((key, value) => MapEntry(key.toString(), value?.toString() ?? ''));
    }
    return _defaultSubtitles[name.trim().toLowerCase()] ?? const <String, String>{};
  }

  factory PlanOption.fromJson(Map<String, dynamic> json) {
    final rawSubtitles = json['subtitles'];
    final name = json['name'] as String? ?? 'Plan';
    return PlanOption(
      id: json['id'] as String,
      name: name,
      monthlyCreditAmountMicro: (json['monthly_credit_amount'] as num?)?.toInt() ?? 0,
      priceUsd: (json['price_usd'] as num?)?.toDouble(),
      billingIntervalMonths: (json['billing_interval_months'] as num?)?.toInt() ?? 1,
      claimMode: json['claim_mode'] as String? ?? 'self_serve',
      storeProductId: json['store_product_id'] as String?,
      subtitles: _resolveSubtitles(rawSubtitles, name),
      tierLevel: _resolveTierLevel(json['tier_level'], name),
    );
  }
}
