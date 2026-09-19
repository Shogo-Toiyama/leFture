import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../auth/authed_http.dart';
import '../../domain/entities/credit_pack_option.dart';
import '../../domain/entities/credit_summary.dart';
import '../../domain/entities/credit_usage_item.dart';
import '../../domain/entities/plan_option.dart';

class DeviceAlreadyClaimedException implements Exception {
  const DeviceAlreadyClaimedException([this.message = 'Device already claimed.']);
  final String message;
  @override
  String toString() => message;
}

class CreditRepository {
  CreditRepository(SupabaseClient supabase) : _http = AuthedHttpClient(supabase);

  /// 期限切れトークンの事前リフレッシュと、401を受けた時の1回リトライ／
  /// 再ログイン誘導はAuthedHttpClientに集約している。
  final AuthedHttpClient _http;

  static const _cloudRunBaseUrl = AppConfig.backendBaseUrl;

  Future<CreditSummary> fetchSummary() async {
    final response = await _http.get(Uri.parse('$_cloudRunBaseUrl/billing/summary'));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch credit summary (${response.statusCode}): ${response.body}');
    }

    return CreditSummary.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// 今claimできる(claim_mode='self_serve'かつ無効化されていない)プラン一覧。
  Future<List<PlanOption>> fetchClaimablePlans() async {
    final response = await _http.get(Uri.parse('$_cloudRunBaseUrl/billing/plans'));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch plans (${response.statusCode}): ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final plans = (body['plans'] as List<dynamic>? ?? [])
        .map((e) => PlanOption.fromJson(e as Map<String, dynamic>))
        .toList();
    return plans;
  }

  /// self_serveプランを選択・有効化する。失敗時はバックエンドが返す
  /// {"detail": {"error_code": ..., "message": ...}} をそのままExceptionの
  /// メッセージに含めて投げる(呼び出し側でユーザー向けメッセージに変換する)。
  Future<void> claimPlan(String planId, {String? deviceId}) async {
    final payload = <String, dynamic>{'plan_id': planId};
    if (deviceId != null && deviceId.isNotEmpty) {
      payload['device_id'] = deviceId;
    }
    final response = await _http
        .post(Uri.parse('$_cloudRunBaseUrl/billing/claim-plan'), payload: payload);

    if (response.statusCode != 200) {
      if (response.body.contains('DEVICE_ALREADY_CLAIMED')) {
        throw const DeviceAlreadyClaimedException();
      }
      throw Exception('Failed to claim plan (${response.statusCode}): ${response.body}');
    }
  }

  /// 購入可能な追加クレジットパック一覧(都度課金、非サブスク)。
  Future<List<CreditPackOption>> fetchCreditPacks() async {
    final response = await _http.get(Uri.parse('$_cloudRunBaseUrl/billing/credit-packs'));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch credit packs (${response.statusCode}): ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final packs = (body['packs'] as List<dynamic>? ?? [])
        .map((e) => CreditPackOption.fromJson(e as Map<String, dynamic>))
        .toList();
    return packs;
  }

  /// 1時間ごとのクレジット利用履歴を取得する。
  Future<List<CreditUsageItem>> fetchUsageHistory() async {
    final response = await _http.get(Uri.parse('$_cloudRunBaseUrl/billing/history'));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch usage history (${response.statusCode}): ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final historyList = (body['history'] as List<dynamic>? ?? [])
        .map((e) => CreditUsageItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return historyList;
  }
}
