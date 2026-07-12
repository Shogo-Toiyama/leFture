/// Supabase/R2など、外部ネットワーク呼び出し全般に使う既定のタイムアウト。
/// オフライン時にawaitがプラットフォーム依存で数十秒〜数分ハングし、
/// 呼び出し元(Pull-to-Refresh等)のローディング表示が固まったまま戻らなくなる
/// 不具合が実際に起きていたため、必ずこの時間で失敗させてtry/catchに
/// 処理を渡す。
const networkTimeout = Duration(seconds: 15);
