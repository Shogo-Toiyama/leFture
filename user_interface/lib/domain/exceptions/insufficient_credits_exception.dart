/// バックエンドが402で返す {"error_code": "...", "message": "..."} を
/// 型付きで表現する例外。error_codeは "NO_CREDIT_ALLOCATION"(プラン未加入)
/// または "INSUFFICIENT_CREDITS"(使い切り)のどちらか。
/// UI層はこれを捕まえたら、汎用エラーダイアログの代わりにクレジット
/// ページへの誘導ダイアログを出す。
class InsufficientCreditsException implements Exception {
  const InsufficientCreditsException({required this.errorCode, required this.message});

  final String errorCode;
  final String message;

  bool get isNoAllocation => errorCode == 'NO_CREDIT_ALLOCATION';

  @override
  String toString() => 'InsufficientCreditsException($errorCode): $message';
}
