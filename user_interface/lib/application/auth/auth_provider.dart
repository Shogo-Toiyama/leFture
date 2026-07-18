import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:http/http.dart' as http;

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

  /// パスワードリセットメール送信
  /// Supabase Auth が Send Email Hook を通じてリセットメールを送信する。
  Future<void> sendPasswordReset(String email) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await supabase.auth.resetPasswordForEmail(
        email,
        // Deep link: アプリが受け取って ResetPasswordPage を開く
        redirectTo: 'lefture://reset-password',
      );
    });
  }

  /// 新しいパスワードに更新
  /// Recovery セッション中（リセットリンクをクリックした後）に呼び出す。
  Future<void> updatePassword(String newPassword) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    });
  }

  /// メールアドレスの更新要求
  Future<void> updateEmail(String newEmail) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await supabase.auth.updateUser(
        UserAttributes(email: newEmail),
      );
    });
  }

  /// パスワードまたはメールアドレスによる再認証を経てアカウントを削除
  Future<void> deleteAccount({String? password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) throw Exception('No active user.');

      // 1. パスワード指定がある場合は再認証を実行 (Email ユーザー向け)
      if (password != null && currentUser.appMetadata['provider'] == 'email') {
        await supabase.auth.signInWithPassword(
          email: currentUser.email!,
          password: password,
        );
      }

      // 再認証はセッションを差し替えるため、JWT は再認証の後に取得する
      final jwt = supabase.auth.currentSession?.accessToken;
      if (jwt == null) throw Exception('No active session.');

      // 2. バックエンドの特権削除エンドポイントを呼び出し
      final response = await http.post(
        Uri.parse('https://lefture-511705914929.us-west1.run.app/auth/delete-account'),
        headers: {
          'Authorization': 'Bearer $jwt',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Failed to delete account: ${response.body}');
      }

      // 3. ローカルサインアウト
      await supabase.auth.signOut();
    });
  }
}