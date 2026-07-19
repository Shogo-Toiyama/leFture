import 'package:http/http.dart' as http;

const _cloudRunBaseUrl = 'https://lefture-511705914929.us-west1.run.app';

/// Supabase の Send Email Hook は、バックエンド(Cloud Run)からの応答を
/// 5秒以内に受け取れないと失敗する(ErrorCodeHookTimeout)。Cloud Runは
/// 未使用が続くとゼロにスケールダウンし、実測でこのサービスのコールドスタートは
/// 20秒前後かかる(nltk等の重い依存の読み込みが主因)ため、この5秒制限へ
/// 引っかかりやすい。
///
/// [waitUntilReady] はDB/外部APIアクセスの無い軽量な /health を1秒間隔で
/// ポーリングし、200が返ってくるまで待つ。呼び出し側は、時間制限の厳しい
/// 本番リクエスト(メールアドレス変更・パスワードリセット等)を送る"前"に
/// これを呼び、**戻り値が false の場合は本番リクエストを送らないこと**。
/// (起動確認を諦めて見切り発車すると、まだ起動しきっていないインスタンスへ
/// 本番リクエストを投げてしまい、ウォームアップの意味が無くなるため)
///
/// 単発の長時間コネクションではなく短いポーリングにしているのは、モバイル
/// 回線切り替え(Wi-Fi⇔セルラー)やアプリのバックグラウンド遷移で、45秒間
/// 張りっぱなしの単一リクエストより途中で切れにくいと考えられるため。
class BackendWarmup {
  BackendWarmup._();

  static Future<bool> waitUntilReady({
    Duration maxWait = const Duration(seconds: 45),
    Duration pollInterval = const Duration(seconds: 1),
    Duration perAttemptTimeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(maxWait);
    while (true) {
      try {
        final response = await http
            .get(Uri.parse('$_cloudRunBaseUrl/health'))
            .timeout(perAttemptTimeout);
        if (response.statusCode == 200) return true;
      } catch (_) {
        // 起動中は接続失敗/タイムアウトが起こり得るので無視して再試行する。
      }

      if (DateTime.now().isAfter(deadline)) return false;
      await Future.delayed(pollInterval);
    }
  }
}
