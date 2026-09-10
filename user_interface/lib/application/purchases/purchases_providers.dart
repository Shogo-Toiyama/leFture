import 'package:flutter/services.dart' show PlatformException;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// RevenueCatの現在のOffering(App Storeのローカライズ価格・商品情報)。
/// クレジット量など実際に付与する値の真実の源はDB(subscription_plans、
/// /billing/plans経由)であり、これは表示専用(価格文字列・商品タイトル)として使う。
final revenueCatOfferingsProvider = FutureProvider.autoDispose<Offerings?>((ref) async {
  try {
    return await Purchases.getOfferings();
  } on PlatformException {
    return null;
  }
});
