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

/// 商品ID → 「この端末のApple IDが実際にその商品の無料トライアル(導入オファー)を
/// 受けられるか」のStoreKit判定。
///
/// バックエンドの課金履歴(/billing/plansのtrial_period_months)はWeb(Stripe)の
/// トライアル可否しか表さない —— Appleのトライアル資格はApple ID単位で
/// App Store側にしか履歴が無く、こちらのアカウント履歴からは判定できない。
/// そのためiOSでのトライアル表記は必ずこちらを判定材料にする(ウェブで課金済みの
/// ユーザーがApple側ではまだ資格を持つ、という食い違いもこれで正しく出る)。
///
/// Androidはストア課金を一切行わない(RevenueCatもAndroid用キー未構成。
/// SDK自体もAndroidでは常にunknownを返す)ため、即座に空を返す。
final revenueCatIntroEligibilityProvider =
    FutureProvider.autoDispose<Map<String, IntroEligibility>>((ref) async {
  if (Platform.isAndroid) return const {};

  final offerings = await ref.watch(revenueCatOfferingsProvider.future);
  final productIds = offerings?.current?.availablePackages
          .map((pkg) => pkg.storeProduct.identifier)
          .toList(growable: false) ??
      const <String>[];
  if (productIds.isEmpty) return const {};

  try {
    return await Purchases.checkTrialOrIntroductoryPriceEligibility(productIds);
  } on PlatformException {
    // 資格判定が取れない時はバッジを出さない(出してから「実は課金される」より、
    // 出さずに実際は無料だった方が害が小さい)。
    return const {};
  }
});
