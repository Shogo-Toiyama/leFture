// lib/infrastructure/repositories/push_notification_repository.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/network_constants.dart';

class PushNotificationRepository {
  final SupabaseClient _supabase;

  PushNotificationRepository(this._supabase);

  static const _cloudRunBaseUrl = AppConfig.backendBaseUrl;

  /// ログイン直後(特にコールドスタート時の永続化セッション復元)は、
  /// currentSessionが「期限切れだが自動リフレッシュがまだ完了していない」
  /// トークンを保持していることがある。その場合だけ明示的にリフレッシュを
  /// 待ってから使う(healthyならリフレッシュAPIを叩かないので余計なコストは無い)。
  Future<String?> _validAccessToken() async {
    var session = _supabase.auth.currentSession;
    if (session == null) return null;
    if (session.isExpired) {
      try {
        final res = await _supabase.auth.refreshSession();
        session = res.session;
      } catch (_) {
        return null;
      }
    }
    return session?.accessToken;
  }

  /// FCMデバイストークンをバックエンドに登録する。
  /// device_tokenはバックエンド側でUNIQUE制約になっており、同じ端末で
  /// 別ユーザーがログインした場合は所有者が自動的に付け替わる。
  Future<void> registerDevice({
    required String deviceToken,
    required String platform,
  }) async {
    final jwt = await _validAccessToken();
    if (jwt == null) return;

    final response = await http
        .post(
          Uri.parse('$_cloudRunBaseUrl/devices/register'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt',
          },
          body: jsonEncode({
            'device_token': deviceToken,
            'platform': platform,
          }),
        )
        .timeout(networkTimeout);

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
    final jwt = await _validAccessToken();
    if (jwt == null) return;

    await http
        .post(
          Uri.parse('$_cloudRunBaseUrl/devices/unregister'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt',
          },
          body: jsonEncode({
            'device_token': deviceToken,
            'platform': platform,
          }),
        )
        .timeout(networkTimeout);
  }
}
