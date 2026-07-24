import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
// import 'package:go_router/go_router.dart';
// import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/application/credit/credit_providers.dart';
import 'package:lecture_companion_ui/domain/entities/credit_summary.dart';
import 'package:lecture_companion_ui/domain/entities/credit_usage_item.dart';
import 'package:lecture_companion_ui/domain/entities/plan_option.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

/// クレジット残量の内訳を見せる詳細ページ。MyAccountPage上部のクレジット
/// タイルから遷移してくる。追加クレジット購入・履歴表示は今はUIだけ用意し、
/// 実際の購入導線(store_purchase)はまだ無いので全て無効化しておく。
///
/// 更新方法は3つ: (1) このページを開いている間は自動で定期的に再取得
/// (処理中のジョブがある間、消費されていく様子が見えるように)、
/// (2) Pull-to-refresh、(3) AppBarの更新ボタン。
class CreditDetailPage extends HookConsumerWidget {
  const CreditDetailPage({super.key});

  static const _autoRefreshInterval = Duration(seconds: 20);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(creditSummaryProvider);

    useEffect(() {
      final timer = Timer.periodic(_autoRefreshInterval, (_) {
        ref.invalidate(creditSummaryProvider);
        ref.invalidate(creditUsageHistoryProvider);
      });
      return timer.cancel;
    }, const []);

    Future<void> handleRefresh() async {
      ref.invalidate(creditSummaryProvider);
      ref.invalidate(creditUsageHistoryProvider);
      await Future.wait([
        ref.read(creditSummaryProvider.future),
        ref.read(creditUsageHistoryProvider.future),
      ]);
    }

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: false,
            floating: true,
            backgroundColor: AppColors.universe.voidBackground,
            title: const Text(
              'Credits',
              style: TextStyle(color: Color(0xFFF2F2F2), fontWeight: FontWeight.w600, fontSize: 20),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFFF2F2F2)),
                tooltip: 'Refresh',
                onPressed: () {
                  ref.invalidate(creditSummaryProvider);
                  ref.invalidate(creditUsageHistoryProvider);
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
                      'Could not load credit info. Check your connection and try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(creditSummaryProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (summary) => _CreditDetailBody(summary: summary),
            ),
          ),
        ],
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
    final plansAsync = ref.watch(claimablePlansProvider);
    final activePlan = plansAsync.asData?.value.firstOrNull;

    final planTitle = activePlan?.name ?? 'Active Plan';
    final creditsCount = summary.monthlyAllocationDisplay ?? activePlan?.monthlyCreditAmountDisplay;
    final creditsSubtitle = creditsCount != null
        ? '$creditsCount credits / month'
        : 'Enjoy full access to your lecture companion features.';

    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Current Plan',
                  style: TextStyle(
                    color: Color(0xFFF2F2F2),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.starGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: AppColors.starGold.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(
                      color: AppColors.starGold,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              planTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              creditsSubtitle,
              style: TextStyle(
                color: AppColors.universe.textComet,
                fontSize: 12.5,
              ),
            ),
            // const SizedBox(height: 16),
            // SizedBox(
            //   width: double.infinity,
            //   child: OutlinedButton.icon(
            //     onPressed: () => context.push(AppRoutes.plans),
            //     style: OutlinedButton.styleFrom(
            //       foregroundColor: Colors.white,
            //       side: const BorderSide(color: Color(0x40FFFFFF)),
            //       padding: const EdgeInsets.symmetric(vertical: 12),
            //       shape: RoundedRectangleBorder(
            //         borderRadius: BorderRadius.circular(12),
            //       ),
            //     ),
            //     icon: const Icon(Icons.stars_rounded, size: 18, color: AppColors.starGold),
            //     label: const Text(
            //       'View & Change Plans',
            //       style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
            //     ),
            //   ),
            // ),
          ],
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
    if (!summary.hasActivePlan) {
      return const _PlanPickerSection();
    }

    // 残高が0以下でも、バー自体は完全な0にはせず薄く赤色を残す(視認性のため)。
    final rawFraction = summary.remainingFraction;
    final isDepleted = (summary.creditBalanceDisplay ?? 0) <= 0;
    final displayFraction = isDepleted ? 0.03 : rawFraction;
    final barColors = isDepleted
        ? const [Color(0xFFFF5252), Color(0xFFD32F2F)]
        : const [Color(0xFFFFB300), Color(0xFFFF8F00)];

    final resetLabel = summary.currentPeriodEnd != null
        ? 'Resets on ${DateFormat.yMMMd().format(summary.currentPeriodEnd!.toLocal())}'
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
                const Text(
                  'Monthly Credits',
                  style: TextStyle(color: Color(0xFFF2F2F2), fontSize: 15, fontWeight: FontWeight.w600),
                ),
                RichText(
                  text: TextSpan(children: [
                    TextSpan(
                      text: '${isDepleted ? 0 : (summary.creditBalanceDisplay ?? 0)}',
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
// プラン選択 (未加入ユーザー向け)
// ─────────────────────────────────────────────────────────────────────────────
//
// GET /billing/plans が返す「今claimできる本物のプラン」をタイルとして並べ、
// その下に将来の課金プラン(Monthly Pro / Annual Pro)のモックタイルを無効化した
// 状態で並べておく。実際に有効なplan_idをFlutter側にハードコードしないため、
// 本物のプランはすべて動的に取得する。

class _PlanPickerSection extends HookConsumerWidget {
  const _PlanPickerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(claimablePlansProvider);
    final claimingPlanId = useState<String?>(null);

    Future<void> handleClaim(PlanOption plan) async {
      claimingPlanId.value = plan.id;
      try {
        await ref.read(creditRepositoryProvider).claimPlan(plan.id);
        ref.invalidate(creditSummaryProvider);
        ref.invalidate(claimablePlansProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${plan.name} activated!')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Could not activate plan'),
              content: Text('$e'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      } finally {
        claimingPlanId.value = null;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No active plan',
                  style: TextStyle(color: Color(0xFFF2F2F2), fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose a plan below to start generating lecture materials.',
                  style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        plansAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Center(child: CircularProgressIndicator(color: AppColors.starGold)),
          ),
          error: (err, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Text(
              'Could not load plans. Pull to refresh and try again.',
              style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
            ),
          ),
          data: (plans) => Column(
            children: [
              for (final plan in plans) ...[
                _PlanTile(
                  title: plan.name,
                  subtitle: '${plan.monthlyCreditAmountDisplay} credits'
                      '${plan.billingIntervalMonths > 1 ? ' / ${plan.billingIntervalMonths} months' : ' / month'}',
                  priceLabel: (plan.priceUsd == null || plan.priceUsd == 0)
                      ? 'Free'
                      : '\$${plan.priceUsd!.toStringAsFixed(2)}',
                  enabled: true,
                  isLoading: claimingPlanId.value == plan.id,
                  onTap: () => handleClaim(plan),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.title,
    required this.subtitle,
    required this.priceLabel,
    required this.enabled,
    this.isLoading = false,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String priceLabel;
  final bool enabled;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled && !isLoading ? onTap : null,
        child: _GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(color: Color(0xFFF2F2F2), fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(color: AppColors.universe.textComet, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.starGold),
                  )
                else
                  Text(
                    priceLabel,
                    style: TextStyle(
                      color: enabled ? AppColors.starGold : Colors.white38,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
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
                const Text(
                  'Usage History',
                  style: TextStyle(
                    color: Color(0xFFF2F2F2),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Hourly summary',
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
                        'Could not load usage history.',
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
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No recent usage activity recorded.',
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
                            'View More (${items.length - 10} more)',
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
            children: [
              Row(
                children: [
                  Text(
                    item.localTimeLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${item.localDateLabel})',
                    style: TextStyle(
                      color: AppColors.universe.textComet,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                item.reasonSummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.universe.textComet,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${item.formattedDelta} credits',
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
