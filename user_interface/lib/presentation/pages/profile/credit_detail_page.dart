import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lecture_companion_ui/application/credit/credit_providers.dart';
import 'package:lecture_companion_ui/domain/entities/credit_summary.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

/// クレジット残量の内訳を見せる詳細ページ。MyAccountPage上部のクレジット
/// タイルから遷移してくる。追加クレジット購入・履歴表示は今はUIだけ用意し、
/// 実際の購入導線(store_purchase)はまだ無いので全て無効化しておく。
class CreditDetailPage extends ConsumerWidget {
  const CreditDetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(creditSummaryProvider);

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
          ),
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
        const SizedBox(height: 20),
        _ExtraCreditCard(summary: summary),
        const SizedBox(height: 20),
        _HistorySection(),
        const SizedBox(height: 48),
      ],
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
      return _GlassCard(
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
                'You need an active plan to generate lecture materials.',
                style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
              ),
            ],
          ),
        ),
      );
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
// 追加クレジット (将来のストア課金購入分。今はUIだけ)
// ─────────────────────────────────────────────────────────────────────────────

class _ExtraCreditCard extends StatelessWidget {
  const _ExtraCreditCard({required this.summary});
  final CreditSummary summary;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Additional Credits',
                  style: TextStyle(color: Color(0xFFF2F2F2), fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Text(
                    'Coming Soon',
                    style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${summary.extraCreditBalanceDisplay} credits',
              style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: null, // ストア課金が実装されるまで無効化
                child: const Text('Buy More Credits'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 履歴 (今はプレースホルダー)
// ─────────────────────────────────────────────────────────────────────────────

class _HistorySection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Usage History',
              style: TextStyle(color: Color(0xFFF2F2F2), fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Per-lecture usage history is coming soon.',
              style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
            ),
          ],
        ),
      ),
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
