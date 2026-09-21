import 'dart:convert';

/// バックエンドが403で返す {"error_code": "ACCOUNT_SUSPENDED", ...} を
/// 型付きで表現する例外。停止は待っても解けないので、アップロードキューは
/// これを見たら自動リトライを止める(InsufficientCreditsExceptionと同じ扱い)。
class AccountSuspendedException implements Exception {
  const AccountSuspendedException([this.message = 'This account has been suspended.']);

  final String message;

  static const errorCode = 'ACCOUNT_SUSPENDED';

  /// 403レスポンスがアカウント停止によるものなら例外を投げる。それ以外は何もしない。
  static void throwIfMatches(int statusCode, String body) {
    if (statusCode != 403) return;
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final detail = decoded['detail'] as Map<String, dynamic>?;
      if (detail?['error_code'] == errorCode) {
        throw AccountSuspendedException(detail?['message'] as String? ?? 'This account has been suspended.');
      }
    } on AccountSuspendedException {
      rethrow;
    } catch (_) {
      // 403だが停止ではない(パース不能含む)。呼び出し元の汎用処理に任せる。
    }
  }

  @override
  String toString() => 'AccountSuspendedException: $message';
}
