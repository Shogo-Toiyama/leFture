import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../infrastructure/supabase/supabase_client.dart';

part 'auth_provider.g.dart';

/// 🔄 現在のセッション（ログイン状態）を監視
@riverpod
Stream<AuthState> authState(Ref ref) {
  return supabase.auth.onAuthStateChange;
}

/// 👤 ログイン中のユーザー情報
@riverpod
User? currentUser(Ref ref) {
  final authState = ref.watch(authStateProvider);
  // authStateProvider は StreamProvider<AuthState> になるので AsyncValue<AuthState>
  return authState.asData?.value.session?.user;
}

/// ✅ ログイン済みかどうか
@riverpod
bool isLoggedIn(Ref ref) {
  final user = ref.watch(currentUserProvider);
  return user != null;
}

/// 🔐 Auth操作を管理する AsyncNotifier 相当のクラス
@riverpod
class AuthController extends _$AuthController {
  @override
  FutureOr<void> build() {
    // 初期状態。特に何もないならこれでOK。
    return null;
  }

  /// サインイン
  Future<void> signIn(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
    });
  }

  /// サインアップ
  Future<void> signUp({
    required String username,
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final response = await supabase.auth.signUp(
        data: {
          'display_name': username,
        },
        email: email,
        password: password,
      );

      if (response.user != null && response.session == null) {
        throw Exception('Please check your email to verify your account.');
      }
    });
  }

  /// サインアウト
  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await supabase.auth.signOut();
    });
  }
}