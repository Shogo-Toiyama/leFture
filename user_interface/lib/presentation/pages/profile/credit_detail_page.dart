import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lefture/app/routes.dart';
// import 'package:go_router/go_router.dart';
import 'package:lefture/application/credit/credit_polling_provider.dart';
import 'package:lefture/application/credit/credit_providers.dart';
import 'package:lefture/domain/entities/credit_summary.dart';
import 'package:lefture/domain/entities/credit_usage_item.dart';
import 'package:lefture/domain/entities/plan_option.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

import 'widgets/plan_theme.dart';

/// クレジット残量の内訳を見せる詳細ページ。MyAccountPage上部のクレジット
/// タイルから遷移してくる。追加クレジット購入・履歴表示は今はUIだけ用意し、
/// 実際の購入導線(store_purchase)はまだ無いので全て無効化しておく。
///
/// 更新方法は3つ: (1) このページを開いている間は自動で定期的に再取得 (5秒間隔ポーリング)
/// (処理中のジョブがある間、消費されていく様子が見えるように)、
/// (2) Pull-to-refresh、(3) AppBarの更新ボタン。
class CreditDetailPage extends HookConsumerWidget {
  const CreditDetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final summaryAsync = ref.watch(creditSummaryProvider);

    useEffect(() {
      final service = ref.read(creditPollingProvider);
      service.startPagePolling();
      return service.stopPagePolling;
    }, const []);

    Future<void> handleRefresh() async {
      await ref.read(creditPollingProvider).refreshCreditData();
    }

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.starGold.withValues(alpha: 0.30),
              AppColors.starGold.withValues(alpha: 0.08),
              Colors.transparent,
            ],
            stops: const [0.0, 0.18, 0.35],
          ),
        ),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: false,
              floating: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text(
                l10n.creditDetailTitle,
                style: const TextStyle(color: Color(0xFFF2F2F2), fontWeight: FontWeight.w600, fontSize: 20),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Color(0xFFF2F2F2)),
                  tooltip: l10n.creditDetailRefreshTooltip,
                  onPressed: () {
                    ref.read(creditPollingProvider).invalidateCreditData();
                  },
                ),
              ],
            ),
          CupertinoSliverRefreshControl(onRefresh: handleRefresh),
          SliverToBoxAdapter(
            child: summaryAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator(color: AppColors.starGold)),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    const Icon(Icons.wifi_off_rounded, color: Colors.white38, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      l10n.creditDetailLoadErrorMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => ref.read(creditPollingProvider).invalidateCreditData(),
                      child: Text(l10n.creditDetailRetryButton),
                    ),
                  ],
                ),
              ),
              data: (summary) => _CreditDetailBody(summary: summary),
            ),
          ),
        ],
      ),
    ),
  );
 }
}

class _CreditDetailBody extends StatelessWidget {
  const _CreditDetailBody({required this.summary});
  final CreditSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _MonthlyCreditCard(summary: summary),
        if (summary.hasActivePlan) ...[
          const SizedBox(height: 20),
          _CurrentPlanCard(summary: summary),
        ],
        // const SizedBox(height: 20),
        // _ExtraCreditCard(summary: summary),
        const SizedBox(height: 20),
        _HistorySection(),
        const SizedBox(height: 48),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Current Plan カード (アクティブプラン情報の表示・プラン変更画面への導線)
// ─────────────────────────────────────────────────────────────────────────────

class _CurrentPlanCard extends ConsumerWidget {
  const _CurrentPlanCard({required this.summary});
  final CreditSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plansAsync = ref.watch(claimablePlansProvider);
    final plans = plansAsync.asData?.value ?? const <PlanOption>[];
    // /billing/plansはstore_purchaseプランも含むため、単純にfirstOrNullではなく
    // summaryのmonthly_allocationと一致するプランを探す(見つからなければ
    // フォールバック表示のまま)。
    final activePlan = plans
        .where((p) => p.monthlyCreditAmountMicro == summary.monthlyAllocationMicro)
        .firstOrNull;

    // プランデータ取得前やオフライン時は、Freeプランを仮表示せずグレータイルを表示する。
    if (activePlan == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: const Color(0x0DFFFFFF),
                border: Border.all(color: const Color(0x1FFFFFFF), width: 1.0),
              ),
            ),
          ),
        ),
      );
    }

    final planName = activePlan.name;
    final planTitle = activePlan.name;
    final themeColor = planThemeColor(planName);
    final isPremium = planName == 'Premium' || activePlan.tierLevel >= 3;
    final isStandard = planName == 'Standard' || activePlan.tierLevel == 2;
    final accentColor = isPremium
        ? const Color(0xFFC084FC)
        : isStandard
            ? const Color(0xFFFB7185)
            : themeColor;

    final creditsCount = summary.monthlyAllocationDisplay ?? activePlan.monthlyCreditAmountDisplay;
    final creditsSubtitle = l10n.creditDetailCreditsPerMonth(creditsCount);

    // 現在のプランが、次回更新日に別プランへ切り替わる予約(ダウングレード/
    // クロスグレード)を持っている場合の一言。Apple同一サブスクグループの
    // 仕様で即時には反映されないため、これが無いと「何も起きていない」と
    // 誤解される。
    final pendingPlan = plans.where((p) => p.id == summary.pendingPlanId).firstOrNull;
    final pendingPlanNote = (pendingPlan != null && summary.currentPeriodEnd != null)
        ? l10n.creditDetailPendingPlanNote(
            pendingPlan.name,
            DateFormat.yMMMd(l10n.localeName).format(summary.currentPeriodEnd!.toLocal()),
          )
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              gradient: isPremium
                  ? const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      stops: [0.0, 0.45, 0.78, 1.0],
                      colors: [
                        Color(0xFF090A14),
                        Color(0xFF131026),
                        Color(0xFF1E1036),
                        Color(0xFF121E3B),
                      ],
                    )
                  : isStandard
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          stops: [0.0, 0.40, 0.75, 1.0],
                          colors: [
                            Color(0xFF140A0F),
                            Color(0xFF240E18),
                            Color(0xFF38141F),
                            Color(0xFF4A1A18),
                          ],
                        )
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          stops: const [0.0, 0.75],
                          colors: [
                            themeColor.withValues(alpha: 0.22),
                            AppColors.universe.voidBackground.withValues(alpha: 0.85),
                          ],
                        ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: accentColor,
                width: (isPremium || isStandard) ? 1.6 : 1.4,
              ),
              boxShadow: isPremium
                  ? [
                      BoxShadow(color: const Color(0xFFA855F7).withValues(alpha: 0.40), blurRadius: 30, spreadRadius: 1),
                      BoxShadow(color: const Color(0xFF06B6D4).withValues(alpha: 0.24), blurRadius: 40, spreadRadius: 1),
                    ]
                  : isStandard
                      ? [
                          BoxShadow(color: const Color(0xFFE11D48).withValues(alpha: 0.35), blurRadius: 28, spreadRadius: 1),
                          BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.22), blurRadius: 40, spreadRadius: 1),
                        ]
                      : [
                          BoxShadow(
                            color: themeColor.withValues(alpha: 0.25),
                            blurRadius: 24,
                          ),
                        ],
            ),
            child: Stack(
              children: [
                // Planページのカードと同じ右下の巨大背景アイコン (はみ出し配置)
                Positioned(
                  bottom: -30,
                  right: -30,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: isPremium ? 0.32 : (isStandard ? 0.26 : 0.15),
                      child: Image.asset(
                        planIconAsset(planName),
                        width: 160,
                        height: 160,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            l10n.creditDetailCurrentPlanTitle,
                            style: TextStyle(
                              color: AppColors.universe.textComet,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(color: accentColor.withValues(alpha: 0.55)),
                            ),
                            child: Text(
                              l10n.creditDetailActiveBadge,
                              style: TextStyle(
                                color: accentColor,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Planページと同じネオン発光のプラン名
                      Text(
                        planTitle,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                          shadows: isPremium
                              ? const [
                                  Shadow(color: Color(0xFF38BDF8), blurRadius: 6),
                                  Shadow(color: Color(0xFFEC4899), blurRadius: 14),
                                  Shadow(color: Color(0xFFA855F7), blurRadius: 24),
                                ]
                              : isStandard
                                  ? const [
                                      Shadow(color: Color(0xFFFB7185), blurRadius: 6),
                                      Shadow(color: Color(0xFFE11D48), blurRadius: 14),
                                      Shadow(color: Color(0xFFF59E0B), blurRadius: 24),
                                    ]
                                  : [
                                      Shadow(color: themeColor, blurRadius: 6),
                                      Shadow(color: themeColor, blurRadius: 14),
                                      Shadow(color: themeColor.withValues(alpha: 0.8), blurRadius: 24),
                                    ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        creditsSubtitle,
                        style: TextStyle(
                          color: AppColors.universe.textStarlight,
                          fontSize: 13,
                        ),
                      ),
                      if (pendingPlanNote != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          pendingPlanNote,
                          style: TextStyle(
                            color: AppColors.universe.textComet,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => context.push(AppRoutes.plans),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: accentColor.withValues(alpha: 0.55), width: 1.1),
                            backgroundColor: accentColor.withValues(alpha: 0.12),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            l10n.creditDetailViewPlansButton,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 月次クレジット
// ─────────────────────────────────────────────────────────────────────────────

class _MonthlyCreditCard extends StatelessWidget {
  const _MonthlyCreditCard({required this.summary});
  final CreditSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!summary.hasActivePlan) {
      return const _NoActivePlanCard();
    }

    // 残高が0以下でも、バー自体は完全な0にはせず薄く赤色を残す(視認性のため)。
    final rawFraction = summary.remainingFraction;
    final isDepleted = (summary.creditBalanceDisplay ?? 0) <= 0;
    final displayFraction = isDepleted ? 0.03 : rawFraction;
    final barColors = isDepleted
        ? const [Color(0xFFFF5252), Color(0xFFD32F2F)]
        : const [Color(0xFFFFB300), Color(0xFFFF8F00)];

    final resetLabel = summary.currentPeriodEnd != null
        ? l10n.creditDetailResetsOn(DateFormat.yMMMd(l10n.localeName).format(summary.currentPeriodEnd!.toLocal()))
        : null;

    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    l10n.creditDetailMonthlyCreditsTitle,
                    style: const TextStyle(color: Color(0xFFF2F2F2), fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                RichText(
                  text: TextSpan(children: [
                    TextSpan(
                      // ★ 以前はisDepletedの時に実際の値を無視して0を表示していたが、
                      // このアプリはオーバードラフト(残高がマイナスに大きく振れること)を
                      // 許容する設計のため、0に丸めると「実際どれだけマイナスか」が
                      // 分からなくなってしまう。実際の値をそのまま表示する。
                      text: '${summary.creditBalanceDisplay ?? 0}',
                      style: const TextStyle(color: AppColors.starGold, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text: ' / ${summary.monthlyAllocationDisplay ?? 0}',
                      style: TextStyle(color: AppColors.universe.textComet, fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: Stack(
                children: [
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0x1AFFFFFF),
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: displayFraction,
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: barColors),
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (resetLabel != null) ...[
              const SizedBox(height: 10),
              Text(resetLabel, style: TextStyle(color: AppColors.universe.textComet, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// プラン未加入カード (有効なプランがない時の表示・プラン一覧への導線)
// ─────────────────────────────────────────────────────────────────────────────

class _NoActivePlanCard extends StatelessWidget {
  const _NoActivePlanCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.0, 0.75],
                colors: [
                  AppColors.starGold.withValues(alpha: 0.18),
                  AppColors.universe.voidBackground.withValues(alpha: 0.85),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.starGold.withValues(alpha: 0.45),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.starGold.withValues(alpha: 0.15),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => context.push(AppRoutes.plans),
                child: Stack(
                  children: [
                    Positioned(
                      bottom: -20,
                      right: -20,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: 0.10,
                          child: Icon(
                            Icons.stars_rounded,
                            size: 150,
                            color: AppColors.starGold,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.creditDetailNoActivePlanTitle,
                            style: const TextStyle(
                              color: Color(0xFFF2F2F2),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n.creditDetailNoActivePlanSubtitle,
                            style: TextStyle(
                              color: AppColors.universe.textComet,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () => context.push(AppRoutes.plans),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: AppColors.starGold.withValues(alpha: 0.55),
                                  width: 1.1,
                                ),
                                backgroundColor: AppColors.starGold.withValues(alpha: 0.12),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                l10n.creditDetailViewPlansUnsubscribedButton,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 追加クレジット (将来のストア課金購入分。今はUIだけ)
// ─────────────────────────────────────────────────────────────────────────────

// /*
// class _ExtraCreditCard extends StatelessWidget {
//   const _ExtraCreditCard({required this.summary});
//   final CreditSummary summary;
// 
//   @override
//   Widget build(BuildContext context) {
//     return _GlassCard(
//       child: Padding(
//         padding: const EdgeInsets.all(20),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Row(
//               children: [
//                 const Text(
//                   'Additional Credits',
//                   style: TextStyle(color: Color(0xFFF2F2F2), fontSize: 15, fontWeight: FontWeight.w600),
//                 ),
//                 const SizedBox(width: 8),
//                 Container(
//                   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
//                   decoration: BoxDecoration(
//                     color: Colors.white.withValues(alpha: 0.08),
//                     borderRadius: BorderRadius.circular(100),
//                   ),
//                   child: const Text(
//                     'Coming Soon',
//                     style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600),
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 6),
//             Text(
//               '${summary.extraCreditBalanceDisplay} credits',
//               style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
//             ),
//             const SizedBox(height: 14),
//             SizedBox(
//               width: double.infinity,
//               child: OutlinedButton(
//                 onPressed: null, // ストア課金が実装されるまで無効化
//                 child: const Text('Buy More Credits'),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
// */

// ─────────────────────────────────────────────────────────────────────────────
// 1時間ごとの利用履歴 セクション
// ─────────────────────────────────────────────────────────────────────────────

class _HistorySection extends HookConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final historyAsync = ref.watch(creditUsageHistoryProvider);
    final isExpanded = useState<bool>(false);

    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    l10n.creditDetailUsageHistoryTitle,
                    style: const TextStyle(
                      color: Color(0xFFF2F2F2),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.creditDetailHourlySummaryLabel,
                  style: TextStyle(
                    color: AppColors.universe.textComet,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            historyAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.starGold,
                  ),
                ),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.creditDetailUsageHistoryLoadError,
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(creditUsageHistoryProvider),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.starGold,
                      ),
                      child: Text(l10n.creditDetailRetryButton),
                    ),
                  ],
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      l10n.creditDetailNoUsageActivity,
                      style: TextStyle(
                        color: AppColors.universe.textComet,
                        fontSize: 13,
                      ),
                    ),
                  );
                }

                final displayItems = isExpanded.value
                    ? items
                    : items.take(10).toList();
                final hasMore = items.length > 10;

                return Column(
                  children: [
                    for (int i = 0; i < displayItems.length; i++) ...[
                      if (i > 0)
                        const Divider(color: Color(0x1AFFFFFF), height: 16),
                      _HistoryTile(item: displayItems[i]),
                    ],
                    if (hasMore && !isExpanded.value) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: () => isExpanded.value = true,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.starGold,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(Icons.expand_more_rounded, size: 18),
                          label: Text(
                            l10n.creditDetailViewMoreButton(items.length - 10),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});
  final CreditUsageItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // プラン更新/切り替えの区切り。具体的な数字を出すと「クレジットを
    // 失った」という誤解を招くため、数字を持たないラベルだけの行として
    // 通常のトランザクション行とは別に描画する。
    if (item.isReset) {
      final label = item.resetReason == 'plan_changed'
          ? l10n.creditDetailHistoryPlanChanged
          : l10n.creditDetailHistoryRenewed;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Divider(color: AppColors.universe.glassBorder, height: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                label,
                style: TextStyle(
                  color: AppColors.universe.textComet,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            Expanded(child: Divider(color: AppColors.universe.glassBorder, height: 1)),
          ],
        ),
      );
    }

    final isPos = item.isPositive;
    final color = isPos ? const Color(0xFF4CAF50) : const Color(0xFFE2E2EC);
    final icon = isPos ? Icons.add_circle_outline_rounded : Icons.bolt_rounded;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isPos ? 0.12 : 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.localTimeLabel(l10n.localeName),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                item.localDateLabel(l10n.localeName, todayLabel: l10n.dateToday, yesterdayLabel: l10n.dateYesterday),
                style: TextStyle(
                  color: AppColors.universe.textComet,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          l10n.creditDetailCreditsSuffix(item.formattedDelta),
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Glass Card (my_account_page.dartの_GlassCardと同じ見た目。privateなので複製)
// ─────────────────────────────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: const Color(0x1AFFFFFF),
              border: Border.all(color: const Color(0x33FFFFFF), width: 0.8),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
