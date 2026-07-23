import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/credit_summary.dart';
import '../../domain/entities/credit_usage_item.dart';
import '../../domain/entities/plan_option.dart';
import '../../infrastructure/repositories/credit_repository.dart';

/// このファイルだけ手書きのProvider(コード生成無し)にしている。他の多くの
/// providerは@riverpodコード生成を使っているが、クレジット関連はテーブルが
/// すべてRLSロックされておりバックエンドAPI呼び出し1本で完結するため、
/// 生成を挟むほどの複雑さが無い。将来ロジックが増えたらコード生成方式に
/// 揃えても良い。
final creditRepositoryProvider = Provider<CreditRepository>((ref) {
  return CreditRepository(Supabase.instance.client);
});

/// GET /billing/summary の結果。autoDisposeにしていない = アプリ内のどこかで
/// (主にCustomAppBar経由で)ほぼ常時watchされ続ける想定なので、通常のnavigation
/// では再フェッチされない。claim後などは`ref.invalidate(creditSummaryProvider)`
/// で明示的に更新する。
final creditSummaryProvider = FutureProvider<CreditSummary>((ref) async {
  return ref.watch(creditRepositoryProvider).fetchSummary();
});

/// 今claimできるプラン一覧(claim_mode='self_serve'かつ無効化されていないもの)。
/// autoDisposeにして、プランページを離れたら破棄・次回開いた時に再取得する
/// (claim後に古い一覧を見せ続けないようにするため)。
final claimablePlansProvider = FutureProvider.autoDispose<List<PlanOption>>((ref) async {
  return ref.watch(creditRepositoryProvider).fetchClaimablePlans();
});

/// GET /billing/history の結果 (1時間ごとの利用履歴)。
final creditUsageHistoryProvider = FutureProvider.autoDispose<List<CreditUsageItem>>((ref) async {
  return ref.watch(creditRepositoryProvider).fetchUsageHistory();
});
