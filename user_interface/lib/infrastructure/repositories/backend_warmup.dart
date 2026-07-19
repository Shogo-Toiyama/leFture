import 'package:http/http.dart' as http;

const _cloudRunBaseUrl = 'https://lefture-511705914929.us-west1.run.app';

/// Supabase の Send Email Hook は、バックエンド(Cloud Run)からの応答を
/// 5秒以内に受け取れないと失敗する(ErrorCodeHookTimeout)。Cloud Runは
/// 未使用が続くとゼロにスケールダウンするため、コールドスタート中にこの
/// 5秒制限へ引っかかりやすい。
///
/// [start] はDB/外部APIアクセスの無い軽量な /health を叩くだけの
/// ウォームアップリクエストで、コールドスタートの待ち時間をこちら側で
/// 先に吸収するために使う。呼び出し側は、時間制限の厳しい本番リクエスト
/// (メールアドレス変更・パスワードリセット等)を送る"前"に、
/// 事前に開始しておいた同じFutureをawaitすることを想定している。
///
/// 失敗しても例外は投げない(ウォームアップの成否に関わらず、本番リクエストは
/// 通常どおり試行する)。
class BackendWarmup {
  BackendWarmup._();

  static Future<void> start() {
    return http
        .get(Uri.parse('$_cloudRunBaseUrl/health'))
        .timeout(const Duration(seconds: 15))
        .then((_) {})
        .catchError((_) {});
  }
}
