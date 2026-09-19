import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/network_constants.dart';

/// バックエンドにセッションそのものを拒否された(=再ログインが必要)ことを表す例外。
/// 単なる通信失敗と区別できるように専用の型にしてある。
class SessionExpiredException implements Exception {
  const SessionExpiredException([
    this.message = 'Your session has expired. Please sign in again.',
  ]);
  final String message;
  @override
  String toString() => message;
}

/// Cloud Runバックエンドを叩くための、認証付きHTTPクライアント。
///
/// 経緯: 2026-09-19、Web側のサインアウトがscope=global(supabase-jsの既定)で
/// 「そのユーザーの全端末」のセッションを失効させ、iOSアプリが
/// 「有効期限内だが失効済み」のアクセストークンを送り続ける状態になった。
/// このときトークン自体は期限内なのでSDKの自動リフレッシュは発火せず、
/// PostgREST(/rest/v1/*)は署名と有効期限しか見ないので200を返し続け、
/// セッション実体を照会するバックエンド経由のクレジット表示だけが壊れた。
///
/// バックエンドは現在このケースを必ず401で返す。ここではその401を受けて
///   1. セッションを1回だけ強制リフレッシュして再試行する
///   2. それでも駄目ならローカルのセッションを破棄する
///      (onAuthStateChangeが発火し、router.dartのredirectが/sign_inへ飛ばす)
/// ことで、アプリを再起動しなくても復帰できるようにする。
class AuthedHttpClient {
  AuthedHttpClient(this._supabase);

  final SupabaseClient _supabase;

  /// 期限切れのトークンをそのまま送らないようにする。
  /// currentSessionは期限切れでもnullにならず古いトークンを返し続けるため、
  /// isExpiredを見て明示的にリフレッシュを待つ
  /// (健全ならリフレッシュAPIを叩かないので余計なコストは無い)。
  Future<String> _accessToken() async {
    var session = _supabase.auth.currentSession;
    if (session == null) {
      throw const SessionExpiredException('Not logged in.');
    }
    if (session.isExpired) {
      session = await _refreshSession();
      if (session == null) {
        await _abandonSession();
        throw const SessionExpiredException();
      }
    }
    return session.accessToken;
  }

  Future<Session?> _refreshSession() async {
    try {
      return (await _supabase.auth.refreshSession()).session;
    } catch (_) {
      // リフレッシュトークンごと失効している場合はここに来る。
      return null;
    }
  }

  /// ローカルのセッションを破棄して再ログインに誘導する。
  /// scopeは必ずlocal — ここでglobalにすると、復帰のためのサインアウトが
  /// 他端末のセッションまで巻き添えで失効させてしまう(今回の事故と同じ構図)。
  Future<void> _abandonSession() async {
    try {
      await _supabase.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // gotrueはローカルセッションを先に破棄してからサーバーへ通知するため、
      // ここで例外が出てもサインアウト自体は成立している。
    }
  }

  /// [request] はAuthorizationヘッダを含むheadersを受け取ってHTTPを投げる関数。
  /// 401なら1回だけリフレッシュして同じリクエストを投げ直す。
  ///
  /// [timeout] は呼び出し元が元々使っていた値をそのまま引き継げるようにしてある
  /// (アカウント削除30秒、ゴミ箱を空にする60秒など、処理によって妥当な長さが
  /// 違うため)。nullを渡すとタイムアウトを掛けない。
  Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) request, {
    Map<String, String> extraHeaders = const {},
    Duration? timeout,
  }) async {
    Map<String, String> headersWith(String token) => {
          ...extraHeaders,
          'Authorization': 'Bearer $token',
        };

    Future<http.Response> run(String token) {
      final future = request(headersWith(token));
      return timeout == null ? future : future.timeout(timeout);
    }

    final response = await run(await _accessToken());
    if (response.statusCode != 401) return response;

    // 401 = バックエンドがJWTを拒否した。1回だけリフレッシュして再試行する。
    final session = await _refreshSession();
    if (session == null) {
      await _abandonSession();
      throw const SessionExpiredException();
    }

    final retried = await run(session.accessToken);
    if (retried.statusCode == 401) {
      // 新しいトークンでも拒否された = セッション実体が失効している
      // (他端末からのglobalサインアウト、アカウント削除など)。再ログインが必要。
      await _abandonSession();
      throw const SessionExpiredException();
    }
    return retried;
  }

  Future<http.Response> get(
    Uri url, {
    Duration? timeout = networkTimeout,
  }) =>
      _send((h) => http.get(url, headers: h), timeout: timeout);

  /// [payload] がnullの場合はボディ無しのPOSTになる
  /// (パスにIDを含めるだけの /lectures/{id}/hard-delete などがこれ)。
  Future<http.Response> post(
    Uri url, {
    Map<String, dynamic>? payload,
    Duration? timeout = networkTimeout,
  }) =>
      _send(
        (h) => http.post(
          url,
          headers: h,
          body: payload == null ? null : jsonEncode(payload),
        ),
        extraHeaders: payload == null
            ? const {}
            : const {'Content-Type': 'application/json'},
        timeout: timeout,
      );
}
