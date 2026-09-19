// lib/infrastructure/repositories/push_notification_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/app_config.dart';
import '../auth/authed_http.dart';

class PushNotificationRepository {
  final SupabaseClient _supabase;
  final AuthedHttpClient _http;

  PushNotificationRepository(this._supabase)
      : _http = AuthedHttpClient(_supabase);

  static const _cloudRunBaseUrl = AppConfig.backendBaseUrl;

  /// 「期限切れだが自動リフレッシュがまだ完了していない」トークンを送らない
  /// ための処理は、以前このクラスだけが_validAccessToken()として持っていたが、
  /// 現在はAuthedHttpClientに集約してある(401時の再試行もそちらが行う)。
  /// ここではデバイス登録がfire-and-forgetである点だけを扱う —
  /// 未ログインなら何もしない。
  bool get _hasSession => _supabase.auth.currentSession != null;

  /// FCMデバイストークンをバックエンドに登録する。
  /// device_tokenはバックエンド側でUNIQUE制約になっており、同じ端末で
  /// 別ユーザーがログインした場合は所有者が自動的に付け替わる。
  Future<void> registerDevice({
    required String deviceToken,
    required String platform,
  }) async {
    if (!_hasSession) return;

    final response = await _http.post(
      Uri.parse('$_cloudRunBaseUrl/devices/register'),
      payload: {
        'device_token': deviceToken,
        'platform': platform,
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to register device (${response.statusCode}): ${response.body}',
      );
    }
  }

  /// サインアウト時などにデバイストークンの登録を解除する。
  Future<void> unregisterDevice({
    required String deviceToken,
    required String platform,
  }) async {
    if (!_hasSession) return;

    try {
      await _http.post(
        Uri.parse('$_cloudRunBaseUrl/devices/unregister'),
        payload: {
          'device_token': deviceToken,
          'platform': platform,
        },
      );
    } on SessionExpiredException {
      // サインアウト処理の一部として呼ばれるため、その時点でセッションが
      // 既に失効しているのは異常ではない。解除できなくてもサインアウト自体は
      // 続行させる(サーバー側のdevice_tokenは次のログイン時に付け替わる)。
    }
  }
}
