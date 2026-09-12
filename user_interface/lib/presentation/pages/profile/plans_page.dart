// lib/presentation/pages/profile/plans_page.dart
import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:lefture/app/routes.dart';
import 'package:lefture/application/credit/credit_polling_provider.dart';
import 'package:lefture/application/credit/credit_providers.dart';
import 'package:lefture/application/purchases/purchases_providers.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/domain/entities/plan_option.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

import 'widgets/plan_card_carousel.dart';
import 'widgets/plan_change_dialogs.dart';
import 'widgets/plan_purchase_state.dart';
import 'widgets/plan_tab_bar.dart';
import 'widgets/plan_theme.dart';

/// クレジット配布プラン一覧画面。Freeプランはself_serve(/billing/claim-plan)で
/// 即時有効化、Entry/Standard/Premiumはstore_purchaseでRevenueCat経由の
/// App Store購入を行う。表示するプラン一覧・クレジット量はすべて
/// GET /billing/plans(DB)が真実の源で、価格文字列のみRevenueCatの
/// Offeringsから取得する。今回のスコープはプランごとの配布クレジット量の
/// 違いのみで、機能制限(feature gating)は行わない。
///
/// レイアウトは上から: 戻るボタン行(固定)→ タグライン+プラン切替タブ+
/// カードスタック+開示文言をまとめた1つのスクロール領域 → 常時画面下部に
/// 留まるフローティングContinueボタン。タブとカードスタックは
/// selectedIndex を共有する「制御されたコンポーネント」として双方向に同期する。
class PlansPage extends HookConsumerWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final summaryAsync = ref.watch(creditSummaryProvider);
    final plansAsync = ref.watch(claimablePlansProvider);
    final offeringsAsync = ref.watch(revenueCatOfferingsProvider);

    final purchasingPlanId = useState<String?>(null);

    // 初回表示カードの決定:
    // 未加入なら3番目(index 2)、何かに加入してたら一つ上のプラン、一番上のプランに加入してたらそのまま一番上を表示。
    final isDataReady = plansAsync.hasValue && (summaryAsync.hasValue || !summaryAsync.isLoading);
    final initialIndex = useMemoized(() {
      if (!isDataReady) return 0;
      final plans = plansAsync.asData?.value.toList();
      if (plans == null || plans.isEmpty) return 0;
      final sorted = [...plans]..sort((a, b) => a.tierLevel.compareTo(b.tierLevel));
      final summary = summaryAsync.asData?.value;
      final hasActivePlan = summary?.hasActivePlan ?? false;
      final currentPlan = sorted.where((p) => hasActivePlan && p.monthlyCreditAmountMicro == summary?.monthlyAllocationMicro).firstOrNull;
      if (!hasActivePlan || currentPlan == null) {
        return (sorted.length >= 3) ? 2 : (sorted.length - 1);
      }
      final currentIdx = sorted.indexOf(currentPlan);
      return (currentIdx + 1).clamp(0, sorted.length - 1);
    }, []);

    final selectedIndex = useState<int>(initialIndex);
    final isInitialIndexSet = useRef<bool>(isDataReady);

    useEffect(() {
      if (isInitialIndexSet.value) return null;
      final plans = plansAsync.asData?.value.toList();
      if (plans == null || plans.isEmpty) return null;
      if (summaryAsync.isLoading) return null;

      final sorted = [...plans]..sort((a, b) => a.tierLevel.compareTo(b.tierLevel));
      final summary = summaryAsync.asData?.value;
      final hasActivePlan = summary?.hasActivePlan ?? false;
      final currentPlan = sorted.where((p) => hasActivePlan && p.monthlyCreditAmountMicro == summary?.monthlyAllocationMicro).firstOrNull;

      final int targetIndex;
      if (!hasActivePlan || currentPlan == null) {
        targetIndex = (sorted.length >= 3) ? 2 : (sorted.length - 1);
      } else {
        final currentIdx = sorted.indexOf(currentPlan);
        targetIndex = (currentIdx + 1).clamp(0, sorted.length - 1);
      }

      selectedIndex.value = targetIndex;
      isInitialIndexSet.value = true;
      return null;
    }, [plansAsync.hasValue, summaryAsync.hasValue, summaryAsync.isLoading]);

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

    // 有料プラン中のユーザーがFreeを選んだ場合の説明ダイアログ。
    // handleClaimFreeは呼ばない: Apple側のサブスク解約を伴わずに内部の
    // プランマッピングだけをFreeへ書き換えると、次回更新時にApple側の
    // 課金・RevenueCatのRENEWALイベントによって有料プランへ勝手に戻って
    // しまう(=「Freeにしたのにまた課金されて有料に戻った」という実害)。
    // 解約は必ずApple側(設定アプリ/App Store)から行ってもらう必要がある
    // ため、ここでは案内のみ行い、直接リンクは意図的に置かない。
    Future<void> showManageSubscriptionDialog() async {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1E1F29),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(l10n.plansManageSubscriptionTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text(l10n.plansManageSubscriptionMessage, style: const TextStyle(color: Colors.white70)),
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

    Future<void> handlePurchase(PlanOption plan, Package package, {required PlanChangeOutcome outcome}) async {
      purchasingPlanId.value = plan.id;
      try {
        await Purchases.purchase(PurchaseParams.package(package));
        if (context.mounted) {
          // ダウングレードは即時反映されない(次回更新日まで元のプランのまま)ため、
          // お祝い演出は誤解を招く。
          switch (outcome) {
            case PlanChangeOutcome.downgrade:
              await showDowngradeDialog(context: context, l10n: l10n);
            case PlanChangeOutcome.upgrade:
              await showUpgradeCelebrationDialog(context: context, l10n: l10n, plan: plan);
          }
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
        // 診断用: どのエラーコードで終わったか(ユーザーによるキャンセルか、
        // それ以外の失敗か)を必ずログに残す。以前はここが完全に無音で、
        // 「購入シートは出たのにRevenueCatに取引が一切残らない」というケースの
        // 原因切り分けができなかった。
        DevLog.add('⚠️ [Plans] purchase failed: plan=${plan.name} errorCode=$errorCode message=${e.message}');
        if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
          await showErrorDialog();
        }
      } catch (e) {
        DevLog.add('⚠️ [Plans] purchase failed: plan=${plan.name} error=$e');
        await showErrorDialog();
      } finally {
        purchasingPlanId.value = null;
      }
    }

    Future<void> handleRestorePurchases() async {
      try {
        await Purchases.restorePurchases();
        ref.read(creditPollingProvider).invalidateCreditData();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.plansRestorePurchasesSuccessMessage)),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.plansRestorePurchasesErrorMessage)),
          );
        }
      }
    }

    if (plansAsync.isLoading) {
      return Scaffold(
        backgroundColor: AppColors.universe.voidBackground,
        body: const Center(child: CircularProgressIndicator(color: AppColors.starGold)),
      );
    }

    final plans = plansAsync.value ?? const <PlanOption>[];
    if (plansAsync.hasError || plans.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.universe.voidBackground,
        body: Center(
          child: Text(
            l10n.plansLoadError,
            style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
          ),
        ),
      );
    }

    final sortedPlans = [...plans]..sort((a, b) => a.tierLevel.compareTo(b.tierLevel));
    final summary = summaryAsync.asData?.value;
    final hasActivePlan = summary?.hasActivePlan ?? false;
    final currentPlan = sortedPlans.where((p) => hasActivePlan && p.monthlyCreditAmountMicro == summary?.monthlyAllocationMicro).firstOrNull;
    // 現在アクティブなプランが、次回更新日に切り替わる予定の別プラン
    // (ダウングレード/クロスグレードの予約)。無ければnull。
    final pendingPlan = sortedPlans.where((p) => p.id == summary?.pendingPlanId).firstOrNull;

    final safeIndex = selectedIndex.value.clamp(0, sortedPlans.length - 1);
    final selectedPlan = sortedPlans[safeIndex];
    final purchaseState = resolvePlanPurchaseState(
      l10n: l10n,
      plan: selectedPlan,
      summary: summary,
      offerings: offeringsAsync.asData?.value,
    );

    final String continueLabel;
    final VoidCallback? onContinue;
    final isPendingTargetSelected = pendingPlan != null && selectedPlan.id == pendingPlan.id;
    final isCurrentWithPendingChange = purchaseState.isCurrentPlan && pendingPlan != null;

    if (isPendingTargetSelected) {
      // 既にこのプランへの切り替えが予約済み。二重予約を避けるため無効化。
      continueLabel = l10n.plansScheduledButton;
      onContinue = null;
    } else if (isCurrentWithPendingChange) {
      // 予約されたdowngrade/crossgradeの取り消しは、アプリ内から直接は
      // 行えない(「現在のプランを再購入すると予約が取り消される」という
      // 非公式な方法を試したが、実機では新しい購入として処理されてしまい
      // 機能しなかった)。Apple自身の「サブスクリプションを管理」画面へ
      // 案内するのみに留める(showRevertGuideDialog参照)。
      continueLabel = l10n.plansRevertButton;
      onContinue = () => showRevertGuideDialog(context: context, l10n: l10n);
    } else if (purchaseState.isCurrentPlan) {
      continueLabel = l10n.plansCurrentPlanButton;
      onContinue = null;
    } else {
      // 未加入時はすべて「Continue」、加入中はCurrentPlanと比較して「Upgrade」または「Downgrade」
      final String actionLabel;
      var isDowngradePurchase = false;
      if (!hasActivePlan || currentPlan == null) {
        actionLabel = l10n.plansContinueButton;
      } else {
        final currentIdx = sortedPlans.indexOf(currentPlan);
        final selectedIdx = sortedPlans.indexOf(selectedPlan);
        final isUpgrade = selectedPlan.tierLevel != currentPlan.tierLevel
            ? selectedPlan.tierLevel > currentPlan.tierLevel
            : (selectedIdx > currentIdx);
        actionLabel = isUpgrade ? l10n.plansUpgradeButton : l10n.plansDowngradeButton;
        isDowngradePurchase = !isUpgrade;
      }

      // Freeを選んでいて、かつ今アクティブなのが有料プランの場合は
      // handleClaimFreeを呼ばない(上のshowManageSubscriptionDialog参照)。
      // 有料プラン未加入(=まだ一度もFreeをclaimしていない等)の場合のみ、
      // 通常通りその場でFreeをclaimしてよい。
      final isDowngradeToFreeFromPaid =
          selectedPlan.isSelfServe && hasActivePlan && currentPlan != null && !currentPlan.isSelfServe;
      if (isDowngradeToFreeFromPaid) {
        continueLabel = l10n.plansManageSubscriptionButton;
        onContinue = () => showManageSubscriptionDialog();
      } else if (selectedPlan.isSelfServe) {
        continueLabel = actionLabel;
        onContinue = () => handleClaimFree(selectedPlan);
      } else if (purchaseState.package != null) {
        continueLabel = actionLabel;
        onContinue = () => handlePurchase(
              selectedPlan,
              purchaseState.package!,
              outcome: isDowngradePurchase ? PlanChangeOutcome.downgrade : PlanChangeOutcome.upgrade,
            );
      } else {
        continueLabel = l10n.plansUnavailableButton;
        onContinue = null;
      }
    }
    final isContinueLoading = purchasingPlanId.value == selectedPlan.id;
    final continueColor = planThemeColor(selectedPlan.name);
    final isUpgradeAction = !purchaseState.isCurrentPlan &&
        hasActivePlan &&
        currentPlan != null &&
        (selectedPlan.tierLevel != currentPlan.tierLevel
            ? selectedPlan.tierLevel > currentPlan.tierLevel
            : (sortedPlans.indexOf(selectedPlan) > sortedPlans.indexOf(currentPlan)));

    final carouselHeight = MediaQuery.sizeOf(context).height * 0.49;

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              continueColor.withValues(alpha: 0.32),
              continueColor.withValues(alpha: 0.10),
              Colors.transparent,
            ],
            stops: const [0.0, 0.18, 0.35],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                children: [
                  SizedBox(
                    height: 52,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  // ここから下(タグライン〜開示文言)を1つのスクロール領域にまとめる。
                  // フローティングContinueボタンだけがこの外側(Stack)に留まり、常に見える。
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 140),
                      child: Column(
                        children: [
                          const SizedBox(height: 4),
                          const Text(
                            'Plans',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFFF2F2F2),
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.plansTagline,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.universe.textStarlight,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: PlanTabBar(
                              plans: sortedPlans,
                              selectedIndex: safeIndex,
                              onSelected: (i) => selectedIndex.value = i,
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: carouselHeight,
                            child: PlanCardCarousel(
                              plans: sortedPlans,
                              selectedIndex: safeIndex,
                              onPageChanged: (i) => selectedIndex.value = i,
                              summary: summary,
                              offerings: offeringsAsync.asData?.value,
                              purchasingPlanId: purchasingPlanId.value,
                              pendingPlanId: summary?.pendingPlanId,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _DisclosureContent(l10n: l10n, onRestorePurchases: handleRestorePurchases),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _FloatingContinueBar(
                  label: continueLabel,
                  color: continueColor,
                  isLoading: isContinueLoading,
                  isUpgrade: isUpgradeAction,
                  isPremiumPlan: selectedPlan.name == 'Premium' || selectedPlan.tierLevel >= 3,
                  onPressed: onContinue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 開示文言(利用規約・プライバシーポリシーへのリンク含む)
// ─────────────────────────────────────────────────────────────────────────────

class _DisclosureContent extends StatelessWidget {
  const _DisclosureContent({required this.l10n, required this.onRestorePurchases});
  final AppLocalizations l10n;
  final VoidCallback onRestorePurchases;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.plansDisclosure,
            style: TextStyle(color: AppColors.universe.textComet, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 12),
          RichText(
            text: TextSpan(
              style: TextStyle(color: AppColors.universe.textComet, fontSize: 12, height: 1.5),
              children: [
                TextSpan(
                  text: l10n.termsAndConditionsLink,
                  style: const TextStyle(color: AppColors.starGold, decoration: TextDecoration.underline),
                  recognizer: TapGestureRecognizer()..onTap = () => context.push(AppRoutes.termsOfService),
                ),
                const TextSpan(text: '   '),
                TextSpan(
                  text: l10n.privacyPolicyLink,
                  style: const TextStyle(color: AppColors.starGold, decoration: TextDecoration.underline),
                  recognizer: TapGestureRecognizer()..onTap = () => context.push(AppRoutes.privacyPolicy),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: onRestorePurchases,
              child: Text(
                l10n.plansRestorePurchasesButton,
                style: const TextStyle(color: AppColors.starGold, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// フローティングContinueボタン (Upgrade時は豪華なグロー・グラデーション装飾)
// ─────────────────────────────────────────────────────────────────────────────

class _FloatingContinueBar extends StatelessWidget {
  const _FloatingContinueBar({
    required this.label,
    required this.color,
    required this.isLoading,
    required this.isUpgrade,
    required this.isPremiumPlan,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final bool isLoading;
  final bool isUpgrade;
  final bool isPremiumPlan;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.universe.voidBackground.withValues(alpha: 0.75),
            border: Border(top: BorderSide(color: AppColors.universe.glassBorder)),
          ),
          padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: (isUpgrade && onPressed != null)
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: isPremiumPlan
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFF43F5E), // Rose Pink
                                Color(0xFFA855F7), // Cosmic Purple
                                Color(0xFF6366F1), // Indigo
                              ],
                            )
                          : LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                HSLColor.fromColor(color)
                                    .withLightness((HSLColor.fromColor(color).lightness + 0.12).clamp(0.0, 1.0))
                                    .toColor(),
                                color,
                                HSLColor.fromColor(color)
                                    .withLightness((HSLColor.fromColor(color).lightness - 0.08).clamp(0.0, 1.0))
                                    .toColor(),
                              ],
                            ),
                      boxShadow: isPremiumPlan
                          ? [
                              BoxShadow(
                                color: const Color(0xFFA855F7).withValues(alpha: 0.55),
                                blurRadius: 24,
                                spreadRadius: 1,
                                offset: const Offset(0, 4),
                              ),
                              BoxShadow(
                                color: const Color(0xFFF43F5E).withValues(alpha: 0.35),
                                blurRadius: 12,
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: color.withValues(alpha: 0.50),
                                blurRadius: 22,
                                spreadRadius: 1,
                                offset: const Offset(0, 4),
                              ),
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.15),
                                blurRadius: 8,
                              ),
                            ],
                      border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1.2),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: isLoading ? null : onPressed,
                        child: Center(
                          child: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 19),
                                    const SizedBox(width: 8),
                                    Text(
                                      label,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.6,
                                        shadows: [
                                          Shadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 1)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  )
                : ElevatedButton(
                    onPressed: isLoading ? null : onPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: onPressed != null ? color : const Color(0x1AFFFFFF),
                      foregroundColor: onPressed != null ? Colors.black : Colors.white38,
                      disabledBackgroundColor: const Color(0x1AFFFFFF),
                      disabledForegroundColor: Colors.white38,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : Text(label, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold)),
                  ),
          ),
        ),
      ),
    );
  }
}
