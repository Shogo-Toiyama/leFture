// lib/presentation/pages/profile/plans_page.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:lefture/application/credit/credit_polling_provider.dart';
import 'package:lefture/application/credit/credit_providers.dart';
import 'package:lefture/application/purchases/purchases_providers.dart';
import 'package:lefture/domain/entities/credit_summary.dart';
import 'package:lefture/domain/entities/plan_option.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// クレジット配布プラン一覧画面。Freeプランはself_serve(/billing/claim-plan)で
/// 即時有効化、Entry/Standard/Premiumはstore_purchaseでRevenueCat経由の
/// App Store購入を行う。表示するプラン一覧・クレジット量はすべて
/// GET /billing/plans(DB)が真実の源で、価格文字列のみRevenueCatの
/// Offeringsから取得する。今回のスコープはプランごとの配布クレジット量の
/// 違いのみで、機能制限(feature gating)は行わない。
class PlansPage extends HookConsumerWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final summaryAsync = ref.watch(creditSummaryProvider);
    final plansAsync = ref.watch(claimablePlansProvider);
    final offeringsAsync = ref.watch(revenueCatOfferingsProvider);

    final purchasingPlanId = useState<String?>(null);

    Future<void> showErrorDialog() async {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1E1F29),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(l10n.plansPurchaseErrorTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text(l10n.plansPurchaseErrorMessage, style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.creditDetailOkButton, style: const TextStyle(color: AppColors.starGold)),
            ),
          ],
        ),
      );
    }

    Future<void> handleClaimFree(PlanOption plan) async {
      purchasingPlanId.value = plan.id;
      try {
        await ref.read(creditRepositoryProvider).claimPlan(plan.id);
        ref.invalidate(creditSummaryProvider);
        ref.invalidate(claimablePlansProvider);
      } catch (e) {
        await showErrorDialog();
      } finally {
        purchasingPlanId.value = null;
      }
    }

    Future<void> handlePurchase(PlanOption plan, Package package) async {
      purchasingPlanId.value = plan.id;
      try {
        await Purchases.purchase(PurchaseParams.package(package));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.plansCreditingInProgressMessage)),
          );
        }
        // クレジット付与はRevenueCat→バックエンドWebhook経由の非同期処理のため、
        // 即座には反映されない可能性が高い。数回リトライしつつ、最終的には
        // 既存のポーリング(CreditDetailPage表示中や録音中の定期更新)に委ねる。
        final polling = ref.read(creditPollingProvider);
        unawaited(() async {
          for (var i = 0; i < 3; i++) {
            await Future.delayed(const Duration(seconds: 3));
            await polling.refreshCreditData();
          }
        }());
      } on PlatformException catch (e) {
        final errorCode = PurchasesErrorHelper.getErrorCode(e);
        if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
          await showErrorDialog();
        }
      } catch (e) {
        await showErrorDialog();
      } finally {
        purchasingPlanId.value = null;
      }
    }

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
            title: Text(
              l10n.plansTitle,
              style: const TextStyle(
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
                  Text(
                    l10n.plansHeadline,
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
                    l10n.plansSubheadline,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.universe.textComet,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),

                  if (plansAsync.isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator(color: AppColors.starGold)),
                    )
                  else if (plansAsync.hasError)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        l10n.plansLoadError,
                        style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
                      ),
                    )
                  else
                    _PlanCards(
                      plans: plansAsync.value ?? const [],
                      summary: summaryAsync.asData?.value,
                      offerings: offeringsAsync.asData?.value,
                      purchasingPlanId: purchasingPlanId.value,
                      onClaimFree: handleClaimFree,
                      onPurchase: handlePurchase,
                    ),

                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.shield_outlined, color: Colors.white38, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        l10n.plansFooterNote,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// プランカード一覧(DB由来のプランをFree→Entry→Standard→Premiumの並びで表示)
// ─────────────────────────────────────────────────────────────────────────────

class _PlanCards extends StatelessWidget {
  const _PlanCards({
    required this.plans,
    required this.summary,
    required this.offerings,
    required this.purchasingPlanId,
    required this.onClaimFree,
    required this.onPurchase,
  });

  final List<PlanOption> plans;
  final CreditSummary? summary;
  final Offerings? offerings;
  final String? purchasingPlanId;
  final void Function(PlanOption plan) onClaimFree;
  final void Function(PlanOption plan, Package package) onPurchase;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sorted = [...plans]..sort((a, b) => a.monthlyCreditAmountMicro.compareTo(b.monthlyCreditAmountMicro));
    final availablePackages = offerings?.current?.availablePackages ?? const <Package>[];

    return Column(
      children: [
        for (final plan in sorted) ...[
          Builder(
            builder: (context) {
              final hasActivePlan = summary?.hasActivePlan ?? false;
              final monthlyAllocationMicro = summary?.monthlyAllocationMicro;
              final isCurrentPlan = hasActivePlan && monthlyAllocationMicro == plan.monthlyCreditAmountMicro;
              final isHighlighted = plan.name == 'Standard';

              Package? package;
              if (plan.isStorePurchase && plan.storeProductId != null) {
                for (final pkg in availablePackages) {
                  if (pkg.storeProduct.identifier == plan.storeProductId) {
                    package = pkg;
                    break;
                  }
                }
              }

              final String priceLabel;
              if (plan.isSelfServe) {
                priceLabel = l10n.creditDetailPriceFree;
              } else if (package != null) {
                priceLabel = package.storeProduct.priceString;
              } else {
                priceLabel = '—';
              }

              final String buttonLabel;
              final bool buttonEnabled;
              final VoidCallback? onTap;
              if (isCurrentPlan) {
                buttonLabel = l10n.plansCurrentPlanButton;
                buttonEnabled = false;
                onTap = null;
              } else if (plan.isSelfServe) {
                buttonLabel = l10n.plansClaimFreeButton;
                buttonEnabled = true;
                onTap = () => onClaimFree(plan);
              } else if (package != null) {
                buttonLabel = l10n.plansSubscribeButton;
                buttonEnabled = true;
                onTap = () => onPurchase(plan, package!);
              } else {
                buttonLabel = l10n.plansUnavailableButton;
                buttonEnabled = false;
                onTap = null;
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: _PricingCard(
                  title: plan.name,
                  subtitle: l10n.creditDetailPlanSubtitle(plan.monthlyCreditAmountDisplay, plan.billingIntervalMonths),
                  price: priceLabel,
                  // クレジット/月の説明はsubtitle側(creditDetailPlanSubtitle)に
                  // 既に含まれているため、価格の隣には何も表示しない。
                  billingPeriod: '',
                  isHighlighted: isHighlighted,
                  badgeLabel: isCurrentPlan
                      ? l10n.plansCurrentPlanBadge
                      : (isHighlighted ? l10n.plansMostPopularBadge : null),
                  badgeColor: isCurrentPlan ? const Color(0x33FFFFFF) : const Color(0xFFFFB300),
                  badgeTextColor: isCurrentPlan ? Colors.white70 : Colors.black,
                  buttonLabel: buttonLabel,
                  isCurrentPlan: !buttonEnabled,
                  isLoading: purchasingPlanId == plan.id,
                  onTap: onTap ?? () {},
                ),
              );
            },
          ),
        ],
      ],
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
    required this.onTap,
    this.isLoading = false,
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
  final bool isLoading;
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
                    if (billingPeriod.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        billingPeriod,
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(color: Color(0x26FFFFFF), height: 1),
                const SizedBox(height: 18),

                _FeatureRow(label: AppLocalizations.of(context).plansFeatureAllToolsIncluded, isHighlighted: isHighlighted),
                const SizedBox(height: 10),
                _FeatureRow(label: AppLocalizations.of(context).plansFeatureCancelAnytime, isHighlighted: isHighlighted),
                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isCurrentPlan || isLoading ? null : onTap,
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
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : Text(
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

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.label, required this.isHighlighted});
  final String label;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Row(
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
            label,
            style: const TextStyle(
              color: Color(0xFFE2E2EC),
              fontSize: 13.5,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
