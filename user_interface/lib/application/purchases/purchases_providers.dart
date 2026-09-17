import 'dart:io' show Platform;

import 'package:flutter/services.dart' show PlatformException;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// RevenueCatの現在のOffering(App Storeのローカライズ価格・商品情報)。
/// クレジット量など実際に付与する値の真実の源はDB(subscription_plans、
/// /billing/plans経由)であり、これは表示専用(価格文字列・商品タイトル)として使う。
///
/// Androidではストア課金を一切行わない(RevenueCatもAndroid用APIキーを
/// 構成していない)ため、そもそも価格取得を試みない。以前はPlatformException
/// を握りつぶしてnullを返していたが、無駄なネットワーク呼び出し・エラーログを
/// 発生させないよう、Android版はここで即座にnullを返す。
final revenueCatOfferingsProvider = FutureProvider.autoDispose<Offerings?>((ref) async {
  if (Platform.isAndroid) return null;
  try {
    return await Purchases.getOfferings();
  } on PlatformException {
    return null;
  }
});
