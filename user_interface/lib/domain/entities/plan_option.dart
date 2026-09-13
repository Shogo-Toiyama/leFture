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

  /// Free=0, Starter/Lite/Entry=1, Standard/Core=2, Premium/Max=3 の表示順。
  final int tierLevel;

  static const int _microCreditsPerCredit = 1000000;

  int get monthlyCreditAmountDisplay => monthlyCreditAmountMicro ~/ _microCreditsPerCredit;

  bool get isSelfServe => claimMode == 'self_serve';
  bool get isStorePurchase => claimMode == 'store_purchase';

  bool get isFreeTier => tierLevel == 0 || isSelfServe;

  bool get isStarterTier {
    final id = storeProductId?.toLowerCase() ?? '';
    return id.contains('starter') || id.contains('entry') || id.contains('lite') || tierLevel == 1;
  }

  bool get isStandardTier {
    final id = storeProductId?.toLowerCase() ?? '';
    return id.contains('standard') || id.contains('core') || tierLevel == 2;
  }

  bool get isPremiumTier {
    final id = storeProductId?.toLowerCase() ?? '';
    return id.contains('premium') || id.contains('max') || tierLevel >= 3;
  }

  /// マーケティング用サブタイトル。DB側の内容はプレーン文字列(nameと同様に
  /// アプリのl10nシステムを経由しない)なので、languageCodeで単純に出し分ける。
  /// 該当言語が無ければ'en'にフォールバックする。
  String? localizedSubtitle(String languageCode) {
    final direct = subtitles[languageCode];
    if (direct != null && direct.isNotEmpty) return direct;
    return subtitles['en'];
  }

  static int _resolveTierLevel(dynamic rawTier, String name, String? storeProductId) {
    if (rawTier is num && rawTier.toInt() > 0) {
      return rawTier.toInt();
    }
    final id = storeProductId?.toLowerCase() ?? '';
    if (id.contains('premium') || id.contains('max')) return 3;
    if (id.contains('standard') || id.contains('core')) return 2;
    if (id.contains('starter') || id.contains('entry') || id.contains('lite')) return 1;

    switch (name.trim().toLowerCase()) {
      case 'max':
      case 'premium':
        return 3;
      case 'core':
      case 'standard':
        return 2;
      case 'lite':
      case 'entry':
        return 1;
      case 'free':
        return 0;
      default:
        return (rawTier is num) ? rawTier.toInt() : 0;
    }
  }

  static const Map<String, Map<String, String>> _defaultSubtitles = {
    'free': {
      'en': 'Start your learning journey',
      'ja': '学びの旅を始めよう',
    },
    'starter': {
      'en': 'Perfect for regular study',
      'ja': '日々の学習にぴったり',
    },
    'entry': {
      'en': 'Perfect for regular study',
      'ja': '日々の学習にぴったり',
    },
    'lite': {
      'en': 'Perfect for regular study',
      'ja': '日々の学習にぴったり',
    },
    'standard': {
      'en': 'For serious, consistent learners',
      'ja': '本気で学びたい人へ',
    },
    'core': {
      'en': 'For serious, consistent learners',
      'ja': '本気で学びたい人へ',
    },
    'premium': {
      'en': 'Unlock your full potential',
      'ja': '可能性を最大限に引き出そう',
    },
    'max': {
      'en': 'Unlock your full potential',
      'ja': '可能性を最大限に引き出そう',
    },
  };

  static Map<String, String> _resolveSubtitles(dynamic rawSubtitles, String name, String? storeProductId) {
    if (rawSubtitles is Map && rawSubtitles.isNotEmpty) {
      return rawSubtitles.map((key, value) => MapEntry(key.toString(), value?.toString() ?? ''));
    }
    final id = storeProductId?.toLowerCase() ?? '';
    if (id.contains('premium') || id.contains('max')) return _defaultSubtitles['max']!;
    if (id.contains('standard') || id.contains('core')) return _defaultSubtitles['core']!;
    if (id.contains('starter') || id.contains('entry') || id.contains('lite')) return _defaultSubtitles['lite']!;

    return _defaultSubtitles[name.trim().toLowerCase()] ?? const <String, String>{};
  }

  factory PlanOption.fromJson(Map<String, dynamic> json) {
    final rawSubtitles = json['subtitles'];
    final name = json['name'] as String? ?? 'Plan';
    final storeProductId = json['store_product_id'] as String?;
    return PlanOption(
      id: json['id'] as String,
      name: name,
      monthlyCreditAmountMicro: (json['monthly_credit_amount'] as num?)?.toInt() ?? 0,
      priceUsd: (json['price_usd'] as num?)?.toDouble(),
      billingIntervalMonths: (json['billing_interval_months'] as num?)?.toInt() ?? 1,
      claimMode: json['claim_mode'] as String? ?? 'self_serve',
      storeProductId: storeProductId,
      subtitles: _resolveSubtitles(rawSubtitles, name, storeProductId),
      tierLevel: _resolveTierLevel(json['tier_level'], name, storeProductId),
    );
  }
}
