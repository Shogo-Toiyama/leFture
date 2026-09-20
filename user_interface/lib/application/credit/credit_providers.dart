import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/credit_pack_option.dart';
import '../../domain/entities/credit_summary.dart';
import '../../domain/entities/credit_usage_item.dart';
import '../../domain/entities/plan_option.dart';
import '../../domain/plan_features.dart' as plan_features;
import '../../infrastructure/repositories/credit_repository.dart';

/// このファイルだけ手書きのProvider(コード生成無し)にしている。他の多くの
/// providerは@riverpodコード生成を使っているが、クレジット関連はテーブルが
/// すべてRLSロックされておりバックエンドAPI呼び出し1本で完結するため、
/// 生成を挟むほどの複雑さが無い。将来ロジックが増えたらコード生成方式に
/// 揃えても良い。
final creditRepositoryProvider = Provider<CreditRepository>((ref) {
  return CreditRepository(Supabase.instance.client);
});

/// tokenRefreshed/signedInを検知してcreditSummaryProviderを再取得させる監視役。
///
/// ★ この監視役はcreditSummaryProvider自身からwatch/readしてはいけない
/// (app.dartのMyApp.buildからwatchして、アプリ起動と同時に独立して
/// 生き続けさせること)。
///
/// 経緯(2026-09-19に実際に2段階で踏んだ罠):
/// 1. 最初、creditSummaryProvider自身のbuild内でonAuthStateChangeをlisten
///    し、受信時にinvalidateSelf()していた。GoTrueのonAuthStateChangeは
///    BehaviorSubject(rxdart)であり.listen()した瞬間に「直前の1件」を必ず
///    即時再送してくるため、
///      invalidateSelf() → 自分がrebuild → build内で再度.listen()
///      → BehaviorSubjectが直前のイベントを即時再送 → 再度invalidateSelf()
///    というネットワークも遅延も一切介さない無限ループになった
///    (サインイン直後、Refresh sessionログと/sign_inへのredirectが高速に
///    無限発生する障害として発生)。
/// 2. それを直すため、この監視役をcreditSummaryProviderとは別のprovider に
///    切り出したが、creditSummaryProvider自身に`ref.watch(この監視役)`させて
///    いたため、Riverpodの依存グラフ上は「creditSummaryProviderは監視役に
///    依存している」→「監視役がcreditSummaryProviderをinvalidateする」という
///    循環になり、CircularDependencyErrorで落ちた(無限ループではなくなった
///    ものの、サインイン直後に例外が飛ぶ状態のままだった)。
/// 解決: creditSummaryProviderからは一切参照しない。app.dartの他の
/// アプリ全体監視役(creditPollingProvider等)と同じ場所でwatchし、
/// 依存グラフ上creditSummaryProviderと無関係な存在にする。
final Provider<void> creditSummaryAuthWatcherProvider = Provider<void>((ref) {
  final sub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
    // tokenRefreshed: 失効していたセッションが復帰した直後
    // signedIn:      別アカウントも含め、ログインし直した直後
    if (state.event == AuthChangeEvent.tokenRefreshed ||
        state.event == AuthChangeEvent.signedIn) {
      ref.invalidate(creditSummaryProvider);
    }
  });
  ref.onDispose(sub.cancel);
});

/// GET /billing/summary の結果。autoDisposeにしていない = アプリ内のどこかで
/// (主にCustomAppBar経由で)ほぼ常時watchされ続ける想定なので、通常のnavigation
/// では再フェッチされない。claim後などは`ref.invalidate(creditSummaryProvider)`
/// で明示的に更新する。
///
/// autoDisposeでない裏返しとして、一度エラーになるとそのエラーがキャッシュされ
/// 続け、画面遷移では再取得されない。2026-09-19にセッションが失効した際、
/// 原因が解消してもアプリを再起動するまでクレジットが読めないままだったのは
/// これが理由。認証状態が変わった時の再取得はcreditSummaryAuthWatcherProvider
/// (app.dartでwatch)が担う — このprovider自身が参照してはいけない、
/// 理由はそちらのコメント参照。
final FutureProvider<CreditSummary> creditSummaryProvider =
    FutureProvider<CreditSummary>((ref) async {
  return ref.watch(creditRepositoryProvider).fetchSummary();
});

/// 今claimできるプラン一覧(claim_mode='self_serve'かつ無効化されていないもの)。
/// autoDisposeにして、プランページを離れたら破棄・次回開いた時に再取得する
/// (claim後に古い一覧を見せ続けないようにするため)。
final claimablePlansProvider = FutureProvider.autoDispose<List<PlanOption>>((ref) async {
  return ref.watch(creditRepositoryProvider).fetchClaimablePlans();
});

/// 購入可能な追加クレジットパック一覧(都度課金、非サブスク)。
/// claimablePlansProviderと同じ理由でautoDisposeにしている。
final creditPacksProvider = FutureProvider.autoDispose<List<CreditPackOption>>((ref) async {
  return ref.watch(creditRepositoryProvider).fetchCreditPacks();
});

/// GET /billing/history の結果 (1時間ごとの利用履歴)。
final creditUsageHistoryProvider = FutureProvider.autoDispose<List<CreditUsageItem>>((ref) async {
  return ref.watch(creditRepositoryProvider).fetchUsageHistory();
});

/// creditSummaryProviderから今のtierLevelだけを取り出す軽量アクセサ。
/// ロード中・エラー時はtierFree(最も制限された状態)にフォールバックする —
/// 機能ゲート判定は「わからなければ閉じておく」方が安全なため
/// (ロード中に一瞬だけ全機能ロック表示になるだけで、実害は無い)。
final currentTierLevelProvider = Provider<int>((ref) {
  final summaryAsync = ref.watch(creditSummaryProvider);
  return summaryAsync.maybeWhen(
    data: (summary) => summary.tierLevel,
    orElse: () => plan_features.tierFree,
  );
});

/// creditSummaryProviderから今のgating_disabled(サーバー側kill-switchの
/// このユーザーへの適用有無)だけを取り出す軽量アクセサ。ロード中・エラー時は
/// true(全機能開放)にフォールバックする — 現状ほぼ全ユーザーがgating無効の
/// 状態なので、読み込み中に一瞬ロック表示がちらつくのを避けるため。
final currentGatingDisabledProvider = Provider<bool>((ref) {
  final summaryAsync = ref.watch(creditSummaryProvider);
  return summaryAsync.maybeWhen(
    data: (summary) => summary.gatingDisabled,
    orElse: () => true,
  );
});

/// 指定したfeatureKeyが現在のプランで使えるかどうか(plan_features.dart参照)。
/// 画面側は `ref.watch(hasFeatureProvider(plan_features.featureDeepNotesFull))`
/// のように使う。tierLevel/gatingDisabledが変わればcreditSummaryProvider経由で
/// 自動的に再評価される。
final hasFeatureProvider = Provider.family<bool, String>((ref, featureKey) {
  final tier = ref.watch(currentTierLevelProvider);
  final gatingDisabled = ref.watch(currentGatingDisabledProvider);
  return plan_features.hasFeature(tier, featureKey, gatingDisabled: gatingDisabled);
});
