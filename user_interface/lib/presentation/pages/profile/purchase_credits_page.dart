import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';

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
import 'package:lefture/domain/entities/credit_pack_option.dart';
import 'package:lefture/domain/entities/credit_summary.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/android_web_redirect_notice_card.dart';

import 'widgets/credit_pack_illustration.dart';
import 'widgets/plan_purchase_state.dart';

/// 追加クレジットパック（都度課金・無期限）の購入画面。
/// 横3列のグリッドビューで統一されたパープルデザインのカードが並び、
/// 下部にはApple規約に準拠した開示文言・利用規約・プライバシーポリシー・購入復元ボタンを備える。
class PurchaseCreditsPage extends HookConsumerWidget {
  const PurchaseCreditsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final summaryAsync = ref.watch(creditSummaryProvider);
    final packsAsync = ref.watch(creditPacksProvider);
    final offeringsAsync = ref.watch(revenueCatOfferingsProvider);

    final purchasingPackId = useState<String?>(null);
    final isRestoringPurchases = useState<bool>(false);

    // 画面を開いている間はクレジット状態の自動更新を監視
    useEffect(() {
      final service = ref.read(creditPollingProvider);
      service.startPagePolling();
      return service.stopPagePolling;
    }, const []);

    Future<void> showErrorDialog() async {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1E1F29),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            l10n.plansPurchaseErrorTitle,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            l10n.plansPurchaseErrorMessage,
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK', style: TextStyle(color: Color(0xFFC084FC))),
            ),
          ],
        ),
      );
    }

    Future<void> showRestoreResultDialog({required String message}) async {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1E1F29),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            l10n.plansRestorePurchasesTitle,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(message, style: const TextStyle(color: Colors.white70, height: 1.4)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK', style: TextStyle(color: Color(0xFFC084FC))),
            ),
          ],
        ),
      );
    }

    Future<void> handlePurchase(CreditPackOption pack, Package package) async {
      purchasingPackId.value = pack.id;
      try {
        await Purchases.purchase(PurchaseParams.package(package));
        final polling = ref.read(creditPollingProvider);
        unawaited(() async {
          for (var i = 0; i < 3; i++) {
            await Future.delayed(const Duration(seconds: 3));
            await polling.refreshCreditData();
          }
        }());
      } on PlatformException catch (e) {
        final errorCode = PurchasesErrorHelper.getErrorCode(e);
        DevLog.add('⚠️ [Credits] pack purchase failed: pack=${pack.name} errorCode=$errorCode message=${e.message}');
        if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
          await showErrorDialog();
        }
      } catch (e) {
        DevLog.add('⚠️ [Credits] pack purchase failed: pack=${pack.name} error=$e');
        await showErrorDialog();
      } finally {
        purchasingPackId.value = null;
      }
    }

    Future<void> handleRestorePurchases() async {
      if (isRestoringPurchases.value) return;
      isRestoringPurchases.value = true;
      try {
        final customerInfo = await Purchases.restorePurchases();
        final hasActive = customerInfo.entitlements.active.isNotEmpty;
        if (hasActive) {
          ref.read(creditPollingProvider).invalidateCreditData();
          ref.invalidate(creditSummaryProvider);
        }
        await showRestoreResultDialog(
          message: hasActive
              ? l10n.plansRestorePurchasesSuccessMessage
              : l10n.plansRestorePurchasesNotFound,
        );
      } on PlatformException catch (e) {
        final errorCode = PurchasesErrorHelper.getErrorCode(e);
        DevLog.add('⚠️ [Credits] restore purchases failed errorCode=$errorCode message=${e.message}');
        final String message;
        if (errorCode == PurchasesErrorCode.receiptAlreadyInUseError ||
            errorCode == PurchasesErrorCode.receiptInUseByOtherSubscriberError) {
          message = l10n.plansRestorePurchasesAlreadyInUse;
        } else {
          message = l10n.plansRestorePurchasesErrorMessage;
        }
        await showRestoreResultDialog(message: message);
      } catch (e) {
        DevLog.add('⚠️ [Credits] restore purchases failed error=$e');
        await showRestoreResultDialog(message: l10n.plansRestorePurchasesErrorMessage);
      } finally {
        isRestoringPurchases.value = false;
      }
    }

    // Androidではストア課金導線(価格表示・購入ボタン)を一切出さない
    // (Google Play Consumption-onlyポリシーに沿うため)。クレジットパックの
    // 内容(クレジット量)は引き続き閲覧できるが、価格・購入ボタン・
    // 購入の復元リンクは非表示にし、代わりにウェブサイト誘導の開示文言を出す。
    final isAndroid = Platform.isAndroid;

    final rawPacks = packsAsync.asData?.value ?? const <CreditPackOption>[];
    // クレジット量順にソート
    final packs = [...rawPacks]..sort((a, b) => a.creditAmountMicro.compareTo(b.creditAmountMicro));
    final offerings = offeringsAsync.asData?.value;
    final summary = summaryAsync.asData?.value;

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFA855F7).withValues(alpha: 0.22),
              const Color(0xFF170D2C).withValues(alpha: 0.55),
              AppColors.universe.voidBackground,
            ],
            stops: const [0.0, 0.28, 0.70],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ヘッダー行 (戻るボタン + タイトル)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFFF2F2F2), size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isAndroid ? l10n.purchaseCreditsTitleAndroid : l10n.purchaseCreditsTitle,
                        style: const TextStyle(
                          color: Color(0xFFF2F2F2),
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 22),
                        tooltip: l10n.creditDetailRefreshTooltip,
                        onPressed: () => ref.read(creditPollingProvider).invalidateCreditData(),
                      ),
                    ],
                  ),
                ),

                // サブタイトル & 現在の残高バッジ
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          l10n.purchaseCreditsTagline,
                          style: TextStyle(
                            color: AppColors.universe.textStarlight.withValues(alpha: 0.85),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                      if (summary != null) ...[
                        const SizedBox(width: 12),
                        _CurrentBalanceMiniBadge(summary: summary),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // メイン: 横3列のグリッドビュー
                if (packsAsync.isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(
                      child: CircularProgressIndicator(color: Color(0xFFA855F7)),
                    ),
                  )
                else if (packs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        l10n.creditDetailBuyCreditsLoadError,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < packs.length; i += 3) ...[
                          if (i > 0) const SizedBox(height: 12),
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var j = 0; j < 3; j++) ...[
                                  if (j > 0) const SizedBox(width: 10),
                                  if (i + j < packs.length) ...[
                                    Expanded(
                                      child: _CreditPackGridCard(
                                        pack: packs[i + j],
                                        package: findPackageByProductId(offerings, packs[i + j].storeProductId),
                                        isPurchasing: purchasingPackId.value == packs[i + j].id,
                                        isDisabled: purchasingPackId.value != null && purchasingPackId.value != packs[i + j].id,
                                        isAndroid: isAndroid,
                                        onPurchase: () {
                                          final pkg = findPackageByProductId(offerings, packs[i + j].storeProductId);
                                          if (pkg != null) {
                                            handlePurchase(packs[i + j], pkg);
                                          }
                                        },
                                      ),
                                    ),
                                  ] else
                                    const Expanded(child: SizedBox.shrink()),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                const SizedBox(height: 20),

                // Android: ウェブサイト誘導の開示文言(テーマカラーであるゴールドのカード状ハイライトで目立たせる)。
                // iOS: Apple規約に基づく開示文言(通常テキスト)。
                if (isAndroid)
                  AndroidWebRedirectNoticeCard(
                    text: l10n.purchaseCreditsDisclosureAndroid,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      l10n.purchaseCreditsDisclosure,
                      style: TextStyle(
                        color: AppColors.universe.textComet,
                        fontSize: 11.5,
                        height: 1.45,
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                // 利用規約 • プライバシーポリシー • (iOSのみ)購入の復元 リンク
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => context.push(AppRoutes.termsOfService),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            l10n.termsAndConditionsLink,
                            style: TextStyle(
                              color: AppColors.universe.textComet,
                              fontSize: 11,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.universe.textComet,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        '•',
                        style: TextStyle(
                          color: AppColors.universe.textComet.withValues(alpha: 0.5),
                          fontSize: 10,
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => context.push(AppRoutes.privacyPolicy),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            l10n.privacyPolicyLink,
                            style: TextStyle(
                              color: AppColors.universe.textComet,
                              fontSize: 11,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.universe.textComet,
                            ),
                          ),
                        ),
                      ),
                      if (!isAndroid) ...[
                        Text(
                          '•',
                          style: TextStyle(
                            color: AppColors.universe.textComet.withValues(alpha: 0.5),
                            fontSize: 10,
                          ),
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: isRestoringPurchases.value ? null : handleRestorePurchases,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: isRestoringPurchases.value
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        l10n.plansRestorePurchasesButton,
                                        style: TextStyle(
                                          color: AppColors.universe.textComet.withValues(alpha: 0.5),
                                          fontSize: 11,
                                          decoration: TextDecoration.underline,
                                          decorationColor: AppColors.universe.textComet.withValues(alpha: 0.5),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const SizedBox(
                                        width: 9,
                                        height: 9,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: Color(0xFFC084FC),
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    l10n.plansRestorePurchasesButton,
                                    style: TextStyle(
                                      color: AppColors.universe.textComet,
                                      fontSize: 11,
                                      decoration: TextDecoration.underline,
                                      decorationColor: AppColors.universe.textComet,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 現在残高ミニバッジ (パープル系)
// ─────────────────────────────────────────────────────────────────────────────

class _CurrentBalanceMiniBadge extends StatelessWidget {
  const _CurrentBalanceMiniBadge({required this.summary});
  final CreditSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1135).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFA855F7).withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            l10n.purchaseCreditsCurrentBalance,
            style: TextStyle(color: AppColors.universe.textComet, fontSize: 9.5),
          ),
          const SizedBox(height: 1),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.stars_rounded, color: Color(0xFFC084FC), size: 15),
              const SizedBox(width: 3),
              Text(
                '${summary.creditBalanceDisplay ?? 0}',
                style: const TextStyle(
                  color: Color(0xFFF2F2F2),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 横3列グリッド用カード（統一パープルデザイン）
// ─────────────────────────────────────────────────────────────────────────────

class _CreditPackGridCard extends StatelessWidget {
  const _CreditPackGridCard({
    required this.pack,
    required this.package,
    required this.isPurchasing,
    required this.isDisabled,
    required this.isAndroid,
    required this.onPurchase,
  });

  final CreditPackOption pack;
  final Package? package;
  final bool isPurchasing;
  final bool isDisabled;
  final bool isAndroid;
  final VoidCallback onPurchase;

  @override
  Widget build(BuildContext context) {
    final priceString = package?.storeProduct.priceString ?? '—';
    final canPurchase = !isAndroid && package != null && !isDisabled && !isPurchasing;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF2B1445).withValues(alpha: 0.75),
                const Color(0xFF160D29).withValues(alpha: 0.88),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFA855F7).withValues(alpha: 0.50),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFA855F7).withValues(alpha: 0.18),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 画像埋め込み領域 (正方形プレースホルダー)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1035).withValues(alpha: 0.50),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFA855F7).withValues(alpha: 0.20),
                        width: 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Center(
                      child: CreditPackIllustration(
                        creditAmount: pack.creditAmountDisplay,
                      ),
                    ),
                  ),
                ),
              ),

              // 2. 星の記号 + 数字 ラベル
              Padding(
                padding: EdgeInsets.fromLTRB(4, 4, 4, isAndroid ? 10 : 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.stars_rounded,
                      size: 16,
                      color: Color(0xFFC084FC),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '${pack.creditAmountDisplay}',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFF2F2F2),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 3. 購入ボタン（「$XX」とだけ表示）。
              // Androidでは価格・購入ボタン自体を出さず、カードをコンパクトに表示する。
              if (!isAndroid)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                  child: SizedBox(
                    height: 36,
                    child: ElevatedButton(
                      onPressed: canPurchase ? onPurchase : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFA855F7),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFA855F7).withValues(alpha: 0.35),
                        elevation: 0,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: isPurchasing
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              priceString,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
