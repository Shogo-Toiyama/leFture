import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/network_constants.dart';
import '../../domain/entities/credit_summary.dart';

class CreditRepository {
  final SupabaseClient _supabase;
  CreditRepository(this._supabase);

  static const _cloudRunBaseUrl = 'https://lefture-511705914929.us-west1.run.app';

  Future<CreditSummary> fetchSummary() async {
    final jwt = _supabase.auth.currentSession?.accessToken;
    if (jwt == null) {
      throw Exception('Not logged in. Cannot fetch credit summary.');
    }

    final response = await http.get(
      Uri.parse('$_cloudRunBaseUrl/billing/summary'),
      headers: {'Authorization': 'Bearer $jwt'},
    ).timeout(networkTimeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch credit summary (${response.statusCode}): ${response.body}');
    }

    return CreditSummary.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
