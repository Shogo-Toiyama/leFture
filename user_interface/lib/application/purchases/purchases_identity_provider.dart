import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../auth/auth_provider.dart';

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

  void _init() {
    _ref.listen<User?>(currentUserProvider, (previous, next) {
      if (next != null && next.id != previous?.id) {
        Purchases.logIn(next.id);
      } else if (next == null && previous != null) {
        Purchases.logOut();
      }
    }, fireImmediately: true);
  }
}

@Riverpod(keepAlive: true)
PurchasesIdentityService purchasesIdentity(Ref ref) {
  return PurchasesIdentityService(ref);
}
