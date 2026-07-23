// lib/presentation/pages/profile/plans_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/credit/credit_providers.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

/// ユーザーに有料・無料のプラン選択肢を美しく見せる料金プラン一覧画面。
class PlansPage extends HookConsumerWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 年額/月額の切り替えトグル
    final isAnnual = useState<bool>(true);
    final summaryAsync = ref.watch(creditSummaryProvider);
    final hasActivePlan = summaryAsync.asData?.value.hasActivePlan ?? false;

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            floating: false,
            backgroundColor: AppColors.universe.voidBackground.withValues(alpha: 0.85),
            flexibleSpace: FlexibleSpaceBar(
              background: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(color: Colors.transparent),
              ),
            ),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text(
              'Plans & Pricing',
              style: TextStyle(
                color: Color(0xFFF2F2F2),
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  
                  // ヘッダーキャッチコピー
                  Text(
                    'Supercharge your learning journey',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.universe.textStarlight,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose the plan that fits your study pace. Upgrade or downgrade anytime.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.universe.textComet,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 月額 / 年額 切り替えスイッチ
                  _BillingToggle(
                    isAnnual: isAnnual.value,
                    onChanged: (val) => isAnnual.value = val,
                  ),
                  const SizedBox(height: 28),

                  // 1. Starter Plan (Free)
                  _PricingCard(
                    title: 'Starter',
                    subtitle: 'Essential tools for casual learners',
                    price: '\$0',
                    billingPeriod: 'forever free',
                    badgeLabel: !hasActivePlan ? 'CURRENT PLAN' : null,
                    badgeColor: const Color(0x33FFFFFF),
                    badgeTextColor: Colors.white70,
                    isHighlighted: false,
                    buttonLabel: !hasActivePlan
                        ? 'Current Active Plan'
                        : 'Downgrade to Starter',
                    isCurrentPlan: !hasActivePlan,
                    features: const [
                      '100 Monthly Credits',
                      'Standard AI Lecture Transcripts',
                      'Core Topic Map Generation',
                      'Basic AI Q&A Chat',
                    ],
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('You are already on the Starter plan.')),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // 2. Orbit Pro (Most Popular)
                  _PricingCard(
                    title: 'Orbit Pro',
                    subtitle: 'Maximum speed, unlimited insights',
                    price: isAnnual.value ? '\$11.99' : '\$14.99',
                    billingPeriod: isAnnual.value ? 'per month, billed yearly' : 'per month',
                    badgeLabel: '🔥 MOST POPULAR',
                    badgeColor: const Color(0xFFFFB300),
                    badgeTextColor: Colors.black,
                    isHighlighted: true,
                    buttonLabel: 'Upgrade to Pro',
                    isCurrentPlan: false,
                    features: const [
                      '1,200 Monthly Credits (12x boost)',
                      'Realtime On-Device & Whisper ASR',
                      'Unlimited Deep Notes & Review Cards',
                      'High-Priority AI Model Speed',
                      'Export Transcripts (PDF & Markdown)',
                      'Full Galaxy Knowledge Graph',
                    ],
                    onTap: () {
                      _showPlanSelectDialog(context, 'Orbit Pro');
                    },
                  ),
                  const SizedBox(height: 20),

                  // 3. Orbit Max (Unlimited)
                  _PricingCard(
                    title: 'Orbit Max',
                    subtitle: 'For heavy researchers & power users',
                    price: isAnnual.value ? '\$23.99' : '\$29.99',
                    billingPeriod: isAnnual.value ? 'per month, billed yearly' : 'per month',
                    badgeLabel: '⚡ BEST VALUE',
                    badgeColor: const Color(0xFF7C4DFF),
                    badgeTextColor: Colors.white,
                    isHighlighted: false,
                    buttonLabel: 'Get Orbit Max',
                    isCurrentPlan: false,
                    features: const [
                      '3,500 Monthly Credits',
                      'All Pro Features Included',
                      'Advanced Galaxy Knowledge Graph',
                      'Custom AI Model Context & Fine-tuning',
                      'Dedicated 24/7 Priority Support',
                      'Early Access to New Experimental Features',
                    ],
                    onTap: () {
                      _showPlanSelectDialog(context, 'Orbit Max');
                    },
                  ),
                  const SizedBox(height: 32),

                  // 安心注記
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.shield_outlined, color: Colors.white38, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Cancel anytime. Encrypted & secure.',
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPlanSelectDialog(BuildContext context, String planName) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1F29),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Select $planName',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '$planName purchasing flow is coming soon in the next update!',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it', style: TextStyle(color: AppColors.starGold)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 月額 / 年額 切り替えトグル Widget
// ─────────────────────────────────────────────────────────────────────────────

class _BillingToggle extends StatelessWidget {
  const _BillingToggle({required this.isAnnual, required this.onChanged});
  final bool isAnnual;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: const Color(0x2AFFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Monthly Button
          GestureDetector(
            onTap: () => onChanged(false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: !isAnnual ? AppColors.starGold : Colors.transparent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                'Monthly',
                style: TextStyle(
                  color: !isAnnual ? Colors.black : Colors.white70,
                  fontSize: 13,
                  fontWeight: !isAnnual ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Annual Button + Save Badge
          GestureDetector(
            onTap: () => onChanged(true),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isAnnual ? AppColors.starGold : Colors.transparent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                children: [
                  Text(
                    'Yearly',
                    style: TextStyle(
                      color: isAnnual ? Colors.black : Colors.white70,
                      fontSize: 13,
                      fontWeight: isAnnual ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isAnnual ? Colors.black.withValues(alpha: 0.2) : const Color(0xFF7C4DFF),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      'SAVE 20%',
                      style: TextStyle(
                        color: isAnnual ? Colors.black : Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 料金プランカード Widget
// ─────────────────────────────────────────────────────────────────────────────

class _PricingCard extends StatelessWidget {
  const _PricingCard({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.billingPeriod,
    required this.isHighlighted,
    required this.buttonLabel,
    required this.isCurrentPlan,
    required this.features,
    required this.onTap,
    this.badgeLabel,
    this.badgeColor,
    this.badgeTextColor,
  });

  final String title;
  final String subtitle;
  final String price;
  final String billingPeriod;
  final bool isHighlighted;
  final String buttonLabel;
  final bool isCurrentPlan;
  final List<String> features;
  final VoidCallback onTap;
  final String? badgeLabel;
  final Color? badgeColor;
  final Color? badgeTextColor;

  @override
  Widget build(BuildContext context) {
    final borderColor = isHighlighted
        ? AppColors.starGold
        : const Color(0x33FFFFFF);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: isHighlighted
                ? const Color(0x28FFB300)
                : const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: borderColor,
              width: isHighlighted ? 1.6 : 0.8,
            ),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: AppColors.starGold.withValues(alpha: 0.15),
                      blurRadius: 24,
                      spreadRadius: 0,
                    )
                  ]
                : [],
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header (Title + Badge)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: isHighlighted ? AppColors.starGold : Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: AppColors.universe.textComet,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (badgeLabel != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: badgeColor ?? AppColors.starGold,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          badgeLabel!,
                          style: TextStyle(
                            color: badgeTextColor ?? Colors.black,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 18),

                // Price Section
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      price,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      billingPeriod,
                      style: TextStyle(
                        color: AppColors.universe.textComet,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(color: Color(0x26FFFFFF), height: 1),
                const SizedBox(height: 18),

                // Features list
                for (final feature in features) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: isHighlighted ? AppColors.starGold : const Color(0xFF8E8EA9),
                          size: 17,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            feature,
                            style: const TextStyle(
                              color: Color(0xFFE2E2EC),
                              fontSize: 13.5,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),

                // Action Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isCurrentPlan ? null : onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isHighlighted
                          ? AppColors.starGold
                          : const Color(0x33FFFFFF),
                      foregroundColor: isHighlighted ? Colors.black : Colors.white,
                      disabledBackgroundColor: const Color(0x15FFFFFF),
                      disabledForegroundColor: Colors.white38,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isHighlighted
                              ? AppColors.starGold
                              : const Color(0x40FFFFFF),
                        ),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      buttonLabel,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: isCurrentPlan
                            ? Colors.white38
                            : (isHighlighted ? Colors.black : Colors.white),
                      ),
                    ),
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
