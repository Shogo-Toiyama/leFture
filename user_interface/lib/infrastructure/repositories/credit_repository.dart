import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/network_constants.dart';
import '../../domain/entities/credit_summary.dart';
import '../../domain/entities/credit_usage_item.dart';
import '../../domain/entities/plan_option.dart';

class CreditRepository {
  final SupabaseClient _supabase;
  CreditRepository(this._supabase);

  static const _cloudRunBaseUrl = 'https://lefture-511705914929.us-west1.run.app';

  String get _jwt {
    final jwt = _supabase.auth.currentSession?.accessToken;
    if (jwt == null) {
      throw Exception('Not logged in.');
    }
    return jwt;
  }

  Future<CreditSummary> fetchSummary() async {
    final response = await http.get(
      Uri.parse('$_cloudRunBaseUrl/billing/summary'),
      headers: {'Authorization': 'Bearer $_jwt'},
    ).timeout(networkTimeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch credit summary (${response.statusCode}): ${response.body}');
    }

    return CreditSummary.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// 今claimできる(claim_mode='self_serve'かつ無効化されていない)プラン一覧。
  Future<List<PlanOption>> fetchClaimablePlans() async {
    final response = await http.get(
      Uri.parse('$_cloudRunBaseUrl/billing/plans'),
      headers: {'Authorization': 'Bearer $_jwt'},
    ).timeout(networkTimeout);

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
  Future<void> claimPlan(String planId) async {
    final response = await http.post(
      Uri.parse('$_cloudRunBaseUrl/billing/claim-plan'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_jwt',
      },
      body: jsonEncode({'plan_id': planId}),
    ).timeout(networkTimeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to claim plan (${response.statusCode}): ${response.body}');
    }
  }

  /// 1時間ごとのクレジット利用履歴を取得する。
  Future<List<CreditUsageItem>> fetchUsageHistory() async {
    final response = await http.get(
      Uri.parse('$_cloudRunBaseUrl/billing/history'),
      headers: {'Authorization': 'Bearer $_jwt'},
    ).timeout(networkTimeout);

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
