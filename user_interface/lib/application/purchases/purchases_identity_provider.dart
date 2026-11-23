import 'dart:async';

import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:lefture/core/utils/dev_log.dart';

import '../auth/auth_provider.dart';
import '../credit/credit_polling_provider.dart';
import '../credit/credit_providers.dart';

part 'purchases_identity_provider.g.dart';

/// RevenueCatのapp_user_idをSupabaseのuser idに同期する。
/// サインイン(signIn/signUp/signInWithGoogle/signInWithApple)・サインアウト
/// (sign_out_flow.dart / deleteAccount)がそれぞれ複数箇所に散っているため、
/// 個別に呼ぶのではなく currentUserProvider の変化を1箇所で監視して行う。
class PurchasesIdentityService {
  PurchasesIdentityService(this._ref) {
    _init();
  }

  final Ref _ref;

  /// このアプリ起動中にsyncPurchases済みのユーザー(起動ごと・ユーザーごとに1回だけ)。
  final Set<String> _syncedUserIds = {};

  void _init() {
    _ref.listen<User?>(currentUserProvider, (previous, next) {
      if (next != null && next.id != previous?.id) {
        unawaited(_logInAndSync(next.id));
      } else if (next == null && previous != null) {
        Purchases.logOut();
      }
    }, fireImmediately: true);
  }

  /// ログイン後、RevenueCat上で有効なサブスクが無い場合だけsyncPurchasesを呼ぶ。
  ///
  /// App Storeのオファーコードを「アプリのインストール前」にリンクから引き換えた
  /// 場合など、アプリ外で成立した購入はSDKが自動では拾わない。RevenueCat公式
  /// (iOS Subscription Offers > Offer Codes)も「アプリに戻ってきた時に
  /// syncPurchasesを呼ぶこと」としている。restorePurchasesと違いOSのサインイン
  /// ダイアログは出ない。
  ///
  /// ★ syncPurchasesは「復元」と同じ扱いのため、同じApple IDの購入が別アカウントに
  /// 紐付いていればTRANSFERが発生しうる(プロジェクト設定: Transfer to new App User ID)。
  /// バックエンドのTRANSFER処理(transfer_store_subscription)が移動元→移動先へ
  /// プランと残クレジットを移す前提。
  ///
  /// ★ logIn の時点で既に有効な場合も、バックエンドへの同期は1回行う。
  /// アプリ外で引き換えた購入が匿名IDに付いていて、logIn の alias でこのユーザーに
  /// 移っただけの場合、新しいwebhookは来ない(匿名ID宛ての INITIAL_PURCHASE は
  /// バックエンドが紐付け先なしとして無視済み)。ここで同期しないと、6時間ごとの
  /// 突き合わせまでDBはFreeのまま残る。
  Future<void> _logInAndSync(String userId) async {
    try {
      final result = await Purchases.logIn(userId);
      if (!_syncedUserIds.add(userId)) return;

      if (result.customerInfo.entitlements.active.isEmpty) {
        await Purchases.syncPurchases();
        final info = await Purchases.getCustomerInfo();
        if (info.entitlements.active.isEmpty) return;
        DevLog.add('💳 [Purchases] syncPurchases found an active entitlement; refreshing credit data');
      } else {
        DevLog.add('💳 [Purchases] logIn returned an active entitlement; asking backend to sync');
      }
      // webhookが届かないケース(匿名IDでの購入がaliasされただけ等)に備えて、
      // バックエンドにRevenueCatとの突き合わせを依頼してから再取得する。
      final action = await _ref.read(creditRepositoryProvider).syncStoreSubscription();
      DevLog.add('💳 [Purchases] backend store sync action=$action');
      // webhook経由の反映は非同期なので、直後と少し後の2回だけ再取得する。
      final polling = _ref.read(creditPollingProvider);
      await polling.invalidateCreditData();
      await Future<void>.delayed(const Duration(seconds: 5));
      if (_ref.read(currentUserProvider)?.id == userId) {
        await polling.invalidateCreditData();
      }
    } catch (e) {
      DevLog.add('⚠️ [Purchases] logIn/syncPurchases failed error=$e');
    }
  }
}

@Riverpod(keepAlive: true)
PurchasesIdentityService purchasesIdentity(Ref ref) {
  return PurchasesIdentityService(ref);
}
