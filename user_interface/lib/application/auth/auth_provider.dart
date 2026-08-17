import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:http/http.dart' as http;

import '../../core/utils/dev_log.dart';
import '../lecture/lecture_controller.dart';
import '../../infrastructure/local_db/app_database_provider.dart';
import '../../infrastructure/supabase/repositories/user_profile_repository_supabase.dart';
import '../../infrastructure/supabase/supabase_client.dart';
import 'local_data_wipe_service.dart';

part 'auth_provider.g.dart';

/// nonce検証用のランダムな生文字列を生成する。
/// Supabaseはプロバイダーによらず「渡されたnonceをSHA-256でハッシュした値」と
/// IDトークンのnonceクレームを比較して検証する。そのためGoogle・Appleいずれも
/// IdP(Google/Apple)へのリクエストにはこの値のSHA-256ハッシュを渡し、
/// Supabase側へは生の値をそのまま渡す。
String _generateRawNonce({int length = 32}) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List.generate(length, (_) => charset[random.nextInt(charset.length)])
      .join();
}

/// Google Sign-Inのnonce(生の値)。Supabaseの signInWithIdToken にはこちらを渡す。
/// GoogleSignIn.instance.initialize()はアプリ起動時に一度しか呼べない制約が
/// あるため、ここで一度だけ生成してmain.dartでの初期化とsignInWithGoogle()の
/// 両方から参照する。
final String googleSignInRawNonce = _generateRawNonce();

/// Google Sign-Inのnonce(SHA-256ハッシュ済み)。GoogleSignIn.instance.initialize()
/// の nonce 引数にはこちら(ハッシュ済み)を渡す — IDトークンのnonceクレームに
/// この値が入り、Supabase側で生の値をハッシュして突き合わせる仕組みのため。
final String googleSignInHashedNonce =
    sha256.convert(utf8.encode(googleSignInRawNonce)).toString();

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
  final streamUser = authState.asData?.value.session?.user;
  // onAuthStateChange がまだ初回イベントを発行していない、あるいは
  // (パスワードリカバリー等の)特定のイベントで期待通りに再発火しなかった
  // 場合でも、SDKが同期的に保持している最新のセッションにフォールバックする。
  // これが無いと、ストリームの取りこぼし1つで currentUser が古いnullの
  // ままキャッシュされ続け、依存する画面が壊れた表示のまま固まる。
  return streamUser ?? supabase.auth.currentUser;
}

/// ✅ ログイン済みかどうか
@riverpod
bool isLoggedIn(Ref ref) {
  final user = ref.watch(currentUserProvider);
  return user != null;
}

/// deleteAccount() が signOut() を呼ぶ直前にセットするフラグ。
/// signOut() は onAuthStateChange を発火させ、GoRouter の redirect が
/// 「未ログイン→/sign_in」判定を、まだ画面遷移前(ダイアログが開いたまま)の
/// 現在地に対して割り込み的に行ってしまう。redirect 側はこのフラグを見て
/// /sign_in ではなく /account_deleted へ誘導する(router.dart 参照)。
/// リダイレクトに一度使われたら redirect 側で false に戻すため、ここでは
/// セットのみを行う。
bool isAccountBeingDeleted = false;

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
    final result = await AsyncValue.guard(() async {
      await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
    });
    if (!ref.mounted) return;
    state = result;
  }

  /// サインアップ
  Future<void> signUp({
    required String username,
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      await supabase.auth.signUp(
        data: {
          'display_name': username,
        },
        email: email,
        password: password,
      );
    });
    if (!ref.mounted) return;
    state = result;
  }

  /// サインアウト(Supabaseのセッションを破棄するだけ)。
  ///
  /// ⚠️ UIからのサインアウトはこれを直接呼ばず、`runSignOutFlow()`
  /// (sign_out_flow.dart)を経由すること。ローカルDBはサインアウトでは消えない
  /// ため、未同期データの救済とローカルデータのwipeを飛ばすと、同じ端末で別
  /// アカウントを使った時に行が混在して壊れる([LocalDataWipeService]のヘッダ参照)。
  Future<void> signOut() async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      await supabase.auth.signOut();
    });
    if (!ref.mounted) return;
    state = result;
  }

  /// パスワードリセットメール送信
  /// Supabase Auth が Send Email Hook を通じてリセットメールを送信する。
  /// 成否を呼び出し元が判定できるよう、結果の [AsyncValue] を返す。
  /// AsyncValue.guard は例外を握りつぶして state に格納するだけで再throwしないため、
  /// 戻り値を見ないと「失敗したのに成功扱い」になる点に注意。
  Future<AsyncValue<void>> sendPasswordReset(String email) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      await supabase.auth.resetPasswordForEmail(
        email,
        // Deep link: アプリが受け取って ResetPasswordPage を開く
        redirectTo: 'lefture://reset-password',
      );
    });
    if (ref.mounted) state = result;
    return result;
  }

  /// 新しいパスワードに更新
  /// Recovery セッション中（リセットリンクをクリックした後）に呼び出す。
  Future<void> updatePassword(String newPassword) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      await supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    });
    if (!ref.mounted) return;
    state = result;
  }

  /// メールアドレスの更新要求
  /// 成否を呼び出し元が判定できるよう、結果の [AsyncValue] を返す。
  Future<AsyncValue<void>> updateEmail(String newEmail) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      await supabase.auth.updateUser(
        UserAttributes(email: newEmail),
        emailRedirectTo: 'com.lefture.app://login-callback/',
      );
    });
    if (ref.mounted) state = result;
    return result;
  }

  /// サインアップ画面でGoogle/Appleを選んだ場合に、入力済みのユーザーネームを
  /// user_profiles に反映する。既にusernameが設定済み(＝以前から使っている
  /// アカウントで、サインアップ画面から誤って実行したケースを含む)の場合は
  /// 上書きしない。反映の失敗はサインイン自体の成否には影響させない
  /// (ベストエフォート)。
  Future<void> _applyDesiredUsernameIfMissing(String? desiredUsername) async {
    if (desiredUsername == null || desiredUsername.isEmpty) return;
    try {
      final repository = ref.read(userProfileRepositoryProvider);
      // サインアップ画面でユーザーが入力した名前を、Social側の名前に関わらず無条件で最優先適用する
      await repository.updateProfile(username: desiredUsername);
    } catch (e) {
      DevLog.add('[Auth] Failed to apply desired username after social sign-in: $e');
    }
  }

  /// Google でサインイン
  /// ネイティブSDK(google_sign_in)経由でGoogleと直接やり取りし、得たIDトークンを
  /// signInWithIdTokenでSupabaseに渡す。ブラウザを一切開かないため、
  /// Supabaseのプロジェクトドメインが同意画面に表示されない。
  ///
  /// [desiredUsername] はサインアップ画面で入力されたユーザーネーム。
  /// サインイン画面からの呼び出しではnullのままでよい。
  Future<void> signInWithGoogle({String? desiredUsername}) async {
    state = const AsyncLoading();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw Exception('Google sign-in did not return an ID token.');
      }
      final result = await AsyncValue.guard(() async {
        await supabase.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          nonce: googleSignInRawNonce,
        );
      });
      if (!result.hasError) {
        await _applyDesiredUsernameIfMissing(desiredUsername);
      }
      if (!ref.mounted) return;
      state = result;
    } on GoogleSignInException catch (e) {
      if (!ref.mounted) return;
      // ユーザーによる明示的なキャンセルはエラー扱いにしない
      state = e.code == GoogleSignInExceptionCode.canceled
          ? const AsyncData(null)
          : AsyncError(e, StackTrace.current);
    }
  }

  /// Apple でサインイン
  /// ネイティブSDK(sign_in_with_apple)経由でAppleと直接やり取りし、得た
  /// IDトークンをsignInWithIdTokenでSupabaseに渡す。Googleと同様、ブラウザを
  /// 一切開かない。Appleはnonceの検証を要求するため、生のnonceを生成して
  /// そのSHA-256ハッシュをApple側のリクエストに渡し、Supabase側へは
  /// 検証用に生のnonceをそのまま渡す。
  ///
  /// AndroidにはネイティブのSign in with Apple自体が存在せず、
  /// sign_in_with_apple パッケージはAndroidでは別途Services ID/返却URLの
  /// Web用設定(webAuthenticationOptions)が無いと動作しない。その設定は
  /// 未実施のため、Android(および万一のWeb)では従来のブラウザ経由の
  /// signInWithOAuthにフォールバックする。iOS/macOSのみネイティブフローを使う。
  ///
  /// [desiredUsername] はサインアップ画面で入力されたユーザーネーム。
  /// サインイン画面からの呼び出しではnullのままでよい。ブラウザ経由の
  /// Androidフォールバックはこの場では認証が完了しない(ディープリンク
  /// コールバック待ち)ため、ユーザーネームの反映は非ネイティブ経路では行わない。
  Future<void> signInWithApple({String? desiredUsername}) async {
    if (kIsWeb || !(Platform.isIOS || Platform.isMacOS)) {
      state = const AsyncLoading();
      final result = await AsyncValue.guard(() async {
        await supabase.auth.signInWithOAuth(
          OAuthProvider.apple,
          redirectTo: 'com.lefture.app://login-callback/',
        );
      });
      if (!ref.mounted) return;
      state = result;
      return;
    }

    state = const AsyncLoading();
    try {
      final rawNonce = _generateRawNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
      final idToken = credential.identityToken;
      if (idToken == null) {
        throw Exception('Apple sign-in did not return an identity token.');
      }
      final result = await AsyncValue.guard(() async {
        await supabase.auth.signInWithIdToken(
          provider: OAuthProvider.apple,
          idToken: idToken,
          nonce: rawNonce,
        );
      });
      if (!result.hasError) {
        await _applyDesiredUsernameIfMissing(desiredUsername);
      }
      if (!ref.mounted) return;
      state = result;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (!ref.mounted) return;
      // ユーザーによる明示的なキャンセルはエラー扱いにしない
      // ※ iOSの ASAuthorizationError.canceled (code 1000) がプラグイン側で
      // AuthorizationErrorCode.unknown として返されることがあるため、
      // エラーコードおよびメッセージ内容の両方でキャンセル判定を行う。
      final isCanceled = e.code == AuthorizationErrorCode.canceled ||
          e.message.contains('1000') ||
          e.message.toLowerCase().contains('canceled') ||
          e.message.toLowerCase().contains('cancelled');
      state = isCanceled
          ? const AsyncData(null)
          : AsyncError(e, StackTrace.current);
    } catch (e, st) {
      if (!ref.mounted) return;
      final msg = e.toString().toLowerCase();
      final isCanceled = msg.contains('1000') ||
          msg.contains('canceled') ||
          msg.contains('cancelled');
      state = isCanceled
          ? const AsyncData(null)
          : AsyncError(e, st);
    }
  }

  /// 現在のプロバイダーを取得（Email, Google, Apple など）
  String? getCurrentProvider() {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    // identities の最初のプロバイダーを使用
    final provider = user.identities?.firstOrNull?.provider;
    return provider;
  }

  /// プロバイダーを新しいものにリンク（切り替え）
  /// linkIdentity は外部ブラウザでの認証を要求するため、ここで完了するのは
  /// 「ブラウザを開く」ところまで。実際にリンクが成功したかはOAuthの
  /// コールバック(router.dart)で分かる。古いプロバイダーのアンリンクも
  /// そちら(コールバック成功時)で行う — この時点ではまだ新しいidentityが
  /// 存在しないため、ここでアンリンクすることはできない。
  /// 成否を呼び出し元が判定できるよう、結果の [AsyncValue] を返す。
  Future<AsyncValue<void>> switchProvider(OAuthProvider newProvider) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('No active user.');

      DevLog.add('[LinkFlow] linkIdentity(${newProvider.name}) '
          'current identities=${user.identities?.map((i) => i.provider).toList()}');
      // 新しいプロバイダーでリンク
      // 端末に既にサインイン済みのGoogleアカウントがあると、確認画面をスキップ
      // して自動的にそのアカウントへ進んでしまう。prompt=select_accountは
      // Google固有のパラメータで、常にアカウント選択画面を強制表示させる
      // (別アカウントをリンクしたいケースがあるため、明示的な選択を必須にする)。
      await supabase.auth.linkIdentity(
        newProvider,
        redirectTo: 'com.lefture.app://login-callback/',
        queryParams: newProvider == OAuthProvider.google
            ? {'prompt': 'select_account'}
            : null,
      );
    });
    if (ref.mounted) state = result;
    return result;
  }

  /// パスワードまたはメールアドレスによる再認証を経てアカウントを削除
  /// 成否を呼び出し元が判定できるよう、結果の [AsyncValue] を返す。
  Future<AsyncValue<void>> deleteAccount({String? password}) async {
    state = const AsyncLoading();
    // 非同期処理の途中でこのProviderが破棄されてもwipeを実行できるよう、
    // DBへの参照は最初に取っておく。LectureController(keepAlive)も同様に
    // 先に掴んでおき、wipe後のキャッシュ無効化に使う。
    final wipeService = LocalDataWipeService(ref.read(appDatabaseProvider));
    final lectureController = ref.read(lectureControllerProvider.notifier);
    final result = await AsyncValue.guard(() async {
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
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('Failed to delete account: ${response.body}');
      }

      // 3. ローカルサインアウト
      // signOut() が発火する onAuthStateChange より先に、router.dart の
      // redirect がこのフラグを参照できるよう必ず呼び出し前にセットする。
      isAccountBeingDeleted = true;
      await supabase.auth.signOut();

      // 4. ローカルデータの削除
      // アカウント自体がサーバーから消えているため、この端末に残ったデータは
      // 二度と同期先が無い(Outbox行はFK/RLS違反を出し続ける)。サインアウトと
      // 同じ基準で、ASRモデルと端末設定以外を消し切る。
      //
      // ここは「アカウント削除が既に成功した後」の後片付けなので、失敗しても
      // guardの外へ例外を出さない。出すと呼び出し元(UI)が「削除に失敗しました」
      // を表示し、/account_deletedへの遷移まで止まってしまう。取りこぼした
      // 残骸は次のサインイン時にwipeOtherUsersが回収する。
      try {
        await wipeService.wipeAll();
        // キャッシュ済みのFileパスを保持しているProviderも捨てる(実ファイルが
        // 消えたパスをImage.fileが読もうとしてPathNotFoundExceptionになる)。
        lectureController.invalidateArtifactFileCache();
      } catch (e, st) {
        DevLog.add(
          '⚠️ [AuthController] Local wipe after account deletion failed '
          '(account itself is already deleted): $e\n$st',
        );
      }
    });
    if (ref.mounted) state = result;
    return result;
  }
}