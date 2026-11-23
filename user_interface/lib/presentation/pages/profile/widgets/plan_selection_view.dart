import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:lefture/app/routes.dart';
import 'package:lefture/application/credit/credit_polling_provider.dart';
import 'package:lefture/application/credit/credit_providers.dart';
import 'package:lefture/application/device/device_identity_service.dart';
import 'package:lefture/application/purchases/purchases_providers.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/domain/entities/credit_summary.dart';
import 'package:lefture/domain/entities/plan_option.dart';
import 'package:lefture/infrastructure/repositories/credit_repository.dart' show DeviceAlreadyClaimedException;
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/account_suspended_gate.dart';
import 'package:lefture/presentation/widgets/android_web_redirect_notice_card.dart';

import 'plan_card_carousel.dart';
import 'plan_change_dialogs.dart';
import 'plan_purchase_state.dart';
import 'plan_tab_bar.dart';
import 'plan_theme.dart';

/// クレジット配布プラン一覧のUI本体(戻るボタン行〜タブ/カルーセル〜開示文言〜
/// フローティングContinueボタン)。単体画面の`PlansPage`(アカウント設定から
/// 遷移)と、オンボーディングのプラン選択ステップの両方から埋め込んで使う
/// 共有ビュー。Scaffoldは持たず、呼び出し側が背景色とナビゲーション文脈を
/// 用意する前提。ロジック(claim/purchase/RevenueCat連携)は元々`PlansPage`に
/// あったものをそのまま移設している。
class PlanSelectionView extends HookConsumerWidget {
  const PlanSelectionView({
    super.key,
    required this.header,
    required this.onBack,
    this.onPlanActivated,
    this.initialTierLevel,
  });

  /// スクロール領域先頭に表示するヘッダーWidget(オンボーディング用またはPlansPage用)。
  final Widget header;

  /// 戻る操作。単体画面では`Navigator.pop`、オンボーディングでは前ステップへ戻す。
  final VoidCallback onBack;

  /// Free plan の claim、または有料プランの購入が成功した直後に呼ばれる。
  /// オンボーディングでは次ステップへ進めるために使う。単体画面(アカウント設定)
  /// では未指定のままでよい(このページに留まって最新状態を表示する)。
  final VoidCallback? onPlanActivated;

  /// ダイアログ等から特定プランへの誘導時に初期表示するtierLevel(0: Free, 1: Lite, 2: Core, 3: Max)。
  /// 未指定時はデフォルトで4つ目(最上位/Recommended)が開く。
  final int? initialTierLevel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final summaryAsync = ref.watch(creditSummaryProvider);
    final plansAsync = ref.watch(claimablePlansProvider);
    final offeringsAsync = ref.watch(revenueCatOfferingsProvider);
    final introEligibilityAsync = ref.watch(revenueCatIntroEligibilityProvider);

    final purchasingPlanId = useState<String?>(null);

    // 診断用: onPlanActivated(オンボーディングでは次のステップへ進む)をどの経路が
    // 呼んだかをログに残す。プランを選ばずにDoneへ進んだ事例の切り分け用。
    void notifyPlanActivated(String reason) {
      if (onPlanActivated == null) return;
      DevLog.add('🧭 [Plans] onPlanActivated reason=$reason');
      onPlanActivated!.call();
    }

    // 初回表示カードの決定:
    // ダイアログ等からinitialTierLevelが指定されていればそのプランを、
    // それ以外はどのプランに加入していてもデフォルトで4つ目(最上位/Recommended)を開く。
    int resolveTargetIndex(List<PlanOption> sorted) {
      if (initialTierLevel != null) {
        final idx = sorted.indexWhere((p) => p.tierLevel == initialTierLevel);
        if (idx != -1) return idx;
      }
      return (sorted.length >= 4) ? 3 : (sorted.length - 1);
    }

    final isDataReady = plansAsync.hasValue && (summaryAsync.hasValue || !summaryAsync.isLoading);
    final initialIndex = useMemoized(() {
      if (!isDataReady) return 0;
      final plans = plansAsync.asData?.value.toList();
      if (plans == null || plans.isEmpty) return 0;
      final sorted = [...plans]..sort((a, b) => a.tierLevel.compareTo(b.tierLevel));
      return resolveTargetIndex(sorted);
    }, [initialTierLevel]);

    final selectedIndex = useState<int>(initialIndex);
    final isInitialIndexSet = useRef<bool>(isDataReady);
    final hasClaimedDeviceFree = useState<bool>(false);

    useEffect(() {
      ref.read(deviceIdentityServiceProvider).hasClaimedDeviceFree().then((value) {
        hasClaimedDeviceFree.value = value;
      });
      return null;
    }, const []);

    useEffect(() {
      if (isInitialIndexSet.value) return null;
      final plans = plansAsync.asData?.value.toList();
      if (plans == null || plans.isEmpty) return null;
      if (summaryAsync.isLoading) return null;

      final sorted = [...plans]..sort((a, b) => a.tierLevel.compareTo(b.tierLevel));
      selectedIndex.value = resolveTargetIndex(sorted);
      isInitialIndexSet.value = true;
      return null;
    }, [plansAsync.hasValue, summaryAsync.hasValue, summaryAsync.isLoading, initialTierLevel]);

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

    Future<void> showDeviceAlreadyClaimedDialog() async {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1E1F29),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(l10n.plansDeviceAlreadyClaimedTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text(l10n.plansDeviceAlreadyClaimedMessage, style: const TextStyle(color: Colors.white70, height: 1.5)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push(AppRoutes.contact);
              },
              child: Text(
                l10n.plansContactSupportButton,
                style: const TextStyle(color: AppColors.starGold, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.creditDetailOkButton, style: const TextStyle(color: Colors.white60)),
            ),
          ],
        ),
      );
    }

    Future<void> handleClaimFree(PlanOption plan) async {
      purchasingPlanId.value = plan.id;
      final deviceService = ref.read(deviceIdentityServiceProvider);
      try {
        final deviceId = await deviceService.getOrCreateDeviceId();
        await ref.read(creditRepositoryProvider).claimPlan(plan.id, deviceId: deviceId);
        await deviceService.markDeviceFreeClaimed();
        hasClaimedDeviceFree.value = true;
        ref.invalidate(creditSummaryProvider);
        ref.invalidate(claimablePlansProvider);
        notifyPlanActivated('claim_free');
      } on DeviceAlreadyClaimedException {
        hasClaimedDeviceFree.value = true;
        await deviceService.markDeviceFreeClaimed();
        await showDeviceAlreadyClaimedDialog();
      } catch (e) {
        if (e.toString().contains('DEVICE_ALREADY_CLAIMED')) {
          hasClaimedDeviceFree.value = true;
          await deviceService.markDeviceFreeClaimed();
          await showDeviceAlreadyClaimedDialog();
        } else {
          await showErrorDialog();
        }
      } finally {
        purchasingPlanId.value = null;
      }
    }

    // 購入前の予告ダイアログ。RevenueCatのオンデバイスCustomerInfoはUXの
    // ためのヒントに過ぎず(古い/不正確な場合がありうる)、安全性はここに
    // 依存させない — 実際の解約はバックエンドがStripe APIをライブに
    // 問い合わせて行う(cancelStripeForPlatformSwitch)。ユーザーがここで
    // キャンセルすればApple購入自体を中止する。
    Future<bool> confirmWebSubscriptionWillBeCancelled() async {
      if (!context.mounted) return false;
      final result = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1E1F29),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(l10n.plansWebSubscriptionActiveTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text(l10n.plansWebSubscriptionActiveMessage, style: const TextStyle(color: Colors.white70, height: 1.5)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.plansWebSubscriptionActiveCancelButton, style: const TextStyle(color: Colors.white60)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.plansWebSubscriptionActiveConfirmButton, style: const TextStyle(color: AppColors.starGold, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
      return result ?? false;
    }

    Future<void> showWebSubscriptionCancelFailedDialog() async {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1E1F29),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(l10n.plansWebSubscriptionCancelFailedTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text(l10n.plansWebSubscriptionCancelFailedMessage, style: const TextStyle(color: Colors.white70, height: 1.5)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.creditDetailOkButton, style: const TextStyle(color: AppColors.starGold)),
            ),
          ],
        ),
      );
    }

    Future<void> handlePurchase(PlanOption plan, Package package, {required PlanChangeOutcome outcome}) async {
      purchasingPlanId.value = plan.id;
      try {
        bool webSubscriptionMayBeActive = false;
        try {
          webSubscriptionMayBeActive = await ref.read(creditRepositoryProvider).hasActiveStripeSubscription();
        } catch (e) {
          DevLog.add('⚠️ [Plans] failed to check active web subscription: $e');
        }
        if (webSubscriptionMayBeActive) {
          final shouldContinue = await confirmWebSubscriptionWillBeCancelled();
          if (!shouldContinue) {
            purchasingPlanId.value = null;
            return;
          }
        }

        await Purchases.purchase(PurchaseParams.package(package));

        // Apple購入が成立した後にWeb(Stripe)側を解約する(この順序が重要:
        // 逆順だとユーザーがApple購入シートをキャンセルした時点で「解約・
        // 返金だけ実行され、何も買えていない」という損失が発生するため)。
        // 失敗してもブロックしない(バックエンド側のパトロールが後から
        // 回収するため、購入自体は成立させる)。
        if (webSubscriptionMayBeActive) {
          try {
            final status = await ref.read(creditRepositoryProvider).cancelStripeForPlatformSwitch();
            if (status != 'cancelled' && status != 'no_active_subscription' && context.mounted) {
              await showWebSubscriptionCancelFailedDialog();
            }
          } catch (e) {
            DevLog.add('⚠️ [Plans] failed to cancel web subscription after Apple purchase: $e');
            if (context.mounted) {
              await showWebSubscriptionCancelFailedDialog();
            }
          }
        }

        if (context.mounted) {
          // ダウングレードは即時反映されない(次回更新日まで元のプランのまま)ため、
          // お祝い演出は誤解を招く。
          switch (outcome) {
            case PlanChangeOutcome.downgrade:
              await showDowngradeDialog(context: context, l10n: l10n);
            case PlanChangeOutcome.upgrade:
              await showUpgradeCelebrationDialog(context: context, l10n: l10n, plan: plan);
          }
          notifyPlanActivated('store_purchase:${outcome.name}');
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

    final isRestoringPurchases = useState<bool>(false);

    Future<void> showRestoreResultDialog({String? title, required String message}) async {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1E1F29),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            title ?? l10n.plansRestorePurchasesTitle,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            message,
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.creditDetailOkButton, style: const TextStyle(color: AppColors.starGold)),
            ),
          ],
        ),
      );
    }

    Future<void> handleRestorePurchases() async {
      if (isRestoringPurchases.value) return;
      isRestoringPurchases.value = true;
      try {
        final customerInfo = await Purchases.restorePurchases();
        final hasActive = customerInfo.entitlements.active.isNotEmpty;
        if (hasActive) {
          // 復元で有効になった契約がwebhookで届かない場合(alias等)に備え、
          // バックエンドにRevenueCatとの突き合わせを依頼してから再取得する。
          final syncAction = await ref.read(creditRepositoryProvider).syncStoreSubscription();
          DevLog.add('💳 [Plans] restore -> backend store sync action=$syncAction');
          ref.read(creditPollingProvider).invalidateCreditData();
          ref.invalidate(claimablePlansProvider);
          ref.invalidate(creditSummaryProvider);
        }
        await showRestoreResultDialog(
          message: hasActive
              ? l10n.plansRestorePurchasesSuccessMessage
              : l10n.plansRestorePurchasesNotFound,
        );
      } on PlatformException catch (e) {
        final errorCode = PurchasesErrorHelper.getErrorCode(e);
        DevLog.add('⚠️ [Plans] restore purchases failed errorCode=$errorCode message=${e.message}');
        final String message;
        if (errorCode == PurchasesErrorCode.receiptAlreadyInUseError ||
            errorCode == PurchasesErrorCode.receiptInUseByOtherSubscriberError) {
          message = l10n.plansRestorePurchasesAlreadyInUse;
        } else {
          message = l10n.plansRestorePurchasesErrorMessage;
        }
        await showRestoreResultDialog(message: message);
      } catch (e) {
        DevLog.add('⚠️ [Plans] restore purchases failed error=$e');
        await showRestoreResultDialog(message: l10n.plansRestorePurchasesErrorMessage);
      } finally {
        isRestoringPurchases.value = false;
      }
    }

    final isRedeemingCode = useState<bool>(false);

    // Appleのオファーコード引き換えシート(iOSのみ)。ログイン後にアプリ内で
    // 引き換えるので、購入は最初からSupabaseのuser idに紐づき、uid宛ての
    // INITIAL_PURCHASE webhookでプランが付与される(URLから引き換えた場合の
    // 「匿名ID → logInでalias」を経由しない)。
    //
    // presentCodeRedemptionSheet()は結果を返さないため、次の2つで新しい契約を検知する:
    //   1. CustomerInfoの更新通知(SDKがStoreKitの新しい取引を処理した時)
    //   2. アプリが前面に戻った時のsyncPurchases(RevenueCat公式の推奨手順)
    // 前面に戻ってから一定時間内に検知できなければ、キャンセル(またはApple側で
    // コードが使えなかった)とみなして何も表示しない。エラーはAppleのシート内に出る。
    //
    // 引き換えの成立からプラン反映までは10秒前後かかる(Sandbox実測: Apple→RevenueCat
    // が約7秒、webhook処理が約1秒)。その間はシートを閉じた時点から画面中央に
    // 進行状況のダイアログを出す。キャンセルした場合も確認の間は表示されるため、
    // 「閉じる」で待つのをやめられるようにしてある(反映中に閉じた場合は裏で続け、
    // 終わったら結果だけ出す)。
    Future<void> handleRedeemCode() async {
      if (!Platform.isIOS || isRedeemingCode.value) return;
      isRedeemingCode.value = true;
      // 現在のプラン判定はbuild後半のcurrentPlanと同じ(月間配分の一致)。
      final plansAtStart = plansAsync.value ?? const <PlanOption>[];
      PlanOption? planOf(CreditSummary? s) => s == null || !s.hasActivePlan
          ? null
          : plansAtStart.where((p) => p.monthlyCreditAmountMicro == s.monthlyAllocationMicro).firstOrNull;
      final previousPlanId = planOf(summaryAsync.asData?.value)?.id;
      final detected = Completer<bool>();
      void complete(bool value) {
        if (!detected.isCompleted) detected.complete(value);
      }

      // 進行状況ダイアログ(シートを閉じて戻った時点で表示)。
      final phase = ValueNotifier<_RedeemProgressPhase>(_RedeemProgressPhase.checking);
      var progressOpen = false;
      var progressShown = false;
      var closedByUser = false;
      BuildContext? progressContext;
      void showProgress() {
        if (progressOpen || !context.mounted) return;
        progressOpen = true;
        progressShown = true;
        unawaited(showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            progressContext = dialogContext;
            return _RedeemProgressDialog(
              phase: phase,
              l10n: l10n,
              onClose: () {
                closedByUser = true;
                Navigator.of(dialogContext).pop();
              },
            );
          },
        ).then((_) {
          progressOpen = false;
          progressContext = null;
          // 確認中に閉じられた = 待つのをやめる(反映中なら既に検知済みなので何もしない)。
          complete(false);
        }));
      }

      void closeProgress() {
        final c = progressContext;
        if (progressOpen && c != null && c.mounted) Navigator.of(c).pop();
      }

      Set<String> activeKeys(CustomerInfo info) =>
          {...info.entitlements.active.keys, ...info.activeSubscriptions};
      Set<String> before = const {};
      bool hasNewActive(CustomerInfo info) => activeKeys(info).difference(before).isNotEmpty;

      void onCustomerInfo(CustomerInfo info) {
        if (hasNewActive(info)) complete(true);
      }

      Timer? resumeGraceTimer;
      var resumeHandled = false;
      final lifecycleListener = AppLifecycleListener(
        onResume: () {
          if (resumeHandled || detected.isCompleted) return;
          resumeHandled = true;
          showProgress();
          unawaited(() async {
            try {
              await Purchases.syncPurchases();
              final info = await Purchases.getCustomerInfo();
              if (hasNewActive(info)) {
                complete(true);
                return;
              }
            } catch (e) {
              DevLog.add('⚠️ [Plans] redeem code: syncPurchases on resume failed error=$e');
            }
            // 取引の反映がシートを閉じた後に少し遅れて届くことがある(Sandbox実測で
            // 約7秒、Apple Developer Forumsでも報告あり)ので、更新通知をもう少しだけ待つ。
            resumeGraceTimer = Timer(const Duration(seconds: 15), () => complete(false));
          }());
        },
      );
      // 前面復帰が発火しない場合の保険。
      final overallTimer = Timer(const Duration(minutes: 3), () => complete(false));

      try {
        before = activeKeys(await Purchases.getCustomerInfo());
        Purchases.addCustomerInfoUpdateListener(onCustomerInfo);
        DevLog.add('💳 [Plans] redeem code: presenting sheet (active before=$before)');
        await Purchases.presentCodeRedemptionSheet();

        final redeemed = await detected.future;
        DevLog.add(
          '💳 [Plans] redeem code: new active subscription detected=$redeemed '
          '(progressShown=$progressShown closedByUser=$closedByUser)',
        );
        if (!redeemed) {
          // 「確認中」を出したまま何も検知できずに終わった場合は、黙って閉じずに
          // 理由の候補と次の手を伝える(自分で「閉じる」を押した場合は何も出さない)。
          // 例: このApple IDで既に同じオファーを使っていた、契約が別アカウントから
          // 移ってきていて「新しい契約」として検知できなかった(→ 購入を復元で直る)。
          closeProgress();
          if (progressShown && !closedByUser) {
            await showRestoreResultDialog(
              title: l10n.plansRedeemCodeTitle,
              message: l10n.plansRedeemCodeNotDetectedMessage,
            );
          }
          return;
        }
        phase.value = _RedeemProgressPhase.applying;
        // 前面復帰より先に更新通知で検知した場合も、ここでダイアログを出す。
        // (確認中に「閉じる」を押した後で検知した場合は出し直さない)
        if (!resumeHandled) showProgress();

        // webhookが届かない場合に備えてバックエンドにも突き合わせを依頼する
        // (購入直後10分以内はwebhook待ちで何もしないが、害はない)。
        final syncAction = await ref.read(creditRepositoryProvider).syncStoreSubscription();
        DevLog.add('💳 [Plans] redeem code -> backend store sync action=$syncAction');

        // クレジット付与はRevenueCat→バックエンドwebhook経由の非同期処理なので、
        // プランが切り替わるまで再取得する。webhookは検知とほぼ同時に処理されている
        // ことが多い(Sandbox実測: 検知の約1秒後)ため、最初は短い間隔で見る。
        final polling = ref.read(creditPollingProvider);
        PlanOption? activatedPlan;
        for (final delaySeconds in const [1, 2, 2, 3, 3, 4]) {
          await Future.delayed(Duration(seconds: delaySeconds));
          if (!context.mounted) return;
          await polling.refreshCreditData();
          final plan = planOf(await ref.read(creditSummaryProvider.future));
          if (plan != null && plan.id != previousPlanId) {
            activatedPlan = plan;
            break;
          }
        }
        ref.invalidate(claimablePlansProvider);
        DevLog.add('💳 [Plans] redeem code: activated plan=${activatedPlan?.name}');

        closeProgress();
        if (!context.mounted) return;
        if (activatedPlan != null) {
          await showUpgradeCelebrationDialog(context: context, l10n: l10n, plan: activatedPlan);
          notifyPlanActivated('redeem_code');
        } else {
          // RevenueCatでは有効だがDBへの反映がまだ。webhook/定期更新で後から反映される。
          await showRestoreResultDialog(
            title: l10n.plansRedeemCodeTitle,
            message: l10n.plansRedeemCodePendingMessage,
          );
        }
      } catch (e) {
        DevLog.add('⚠️ [Plans] redeem code failed error=$e');
        closeProgress();
        await showRestoreResultDialog(
          title: l10n.plansRedeemCodeTitle,
          message: l10n.plansRedeemCodeErrorMessage,
        );
      } finally {
        closeProgress();
        Purchases.removeCustomerInfoUpdateListener(onCustomerInfo);
        lifecycleListener.dispose();
        resumeGraceTimer?.cancel();
        overallTimer.cancel();
        if (context.mounted) isRedeemingCode.value = false;
      }
    }

    final plans = plansAsync.value ?? const <PlanOption>[];
    final isLoadingPlans = plansAsync.isLoading;
    final hasPlansError = plansAsync.hasError || (!isLoadingPlans && plans.isEmpty);

    final sortedPlans = [...plans]..sort((a, b) => a.tierLevel.compareTo(b.tierLevel));
    // ★ summaryAsync.asData?.valueは再フェッチ中(AsyncLoading with previous
    // data)でも直前の取得結果を保持する(RiverpodのcopyWithPrevious挙動)。
    // これがnullになるのは「このセッションでまだ一度もデータを取得できていない」
    // 場合(初回ロード中、または初回取得がエラーで終わった場合)に限られる —
    // そのケースをhasActivePlan=falseとして扱うと「有料ユーザーが一瞬Freeに
    // 見える」問題になるため、summaryIsUnknownとして明示的に区別する。
    final summary = summaryAsync.asData?.value;
    final summaryIsUnknown = summary == null;
    final hasActivePlan = summary?.hasActivePlan ?? false;
    final currentPlan = sortedPlans.where((p) => hasActivePlan && p.monthlyCreditAmountMicro == summary?.monthlyAllocationMicro).firstOrNull;
    // 現在アクティブなプランが、次回更新日に切り替わる予定の別プラン
    // (ダウングレード/クロスグレードの予約)。無ければnull。
    final pendingPlan = sortedPlans.where((p) => p.id == summary?.pendingPlanId).firstOrNull;

    final String continueLabel;
    final VoidCallback? onContinue;
    final bool isContinueLoading;
    final Color continueColor;
    final bool isUpgradeAction;
    final bool isPremiumPlan;
    final int safeIndex;

    if (isLoadingPlans || sortedPlans.isEmpty || summaryIsUnknown) {
      // summaryIsUnknown(=このユーザーの現在の加入状況をまだ一度も取得できて
      // いない)間は、hasActivePlan=falseを前提にした購入/ダウングレード判定を
      // 一切走らせない。判定を進めてしまうと「本当は有料プラン加入中なのに
      // まだ未加入として扱われ、Freeへのダウングレードや新規購入ボタンが
      // 誤って有効になる」ことがあり得るため、Continueボタンごと無効化して
      // 安全側に倒す。
      continueLabel = l10n.plansContinueButton;
      onContinue = null;
      isContinueLoading = false;
      continueColor = AppColors.starGold;
      isUpgradeAction = false;
      isPremiumPlan = false;
      safeIndex = 0;
    } else {
      safeIndex = selectedIndex.value.clamp(0, sortedPlans.length - 1);
      final selectedPlan = sortedPlans[safeIndex];
      final purchaseState = resolvePlanPurchaseState(
        l10n: l10n,
        plan: selectedPlan,
        summary: summary,
        offerings: offeringsAsync.asData?.value,
        introEligibility: introEligibilityAsync.asData?.value,
      );

      final isPendingTargetSelected = pendingPlan != null && selectedPlan.id == pendingPlan.id;
      final isCurrentWithPendingChange = purchaseState.isCurrentPlan && pendingPlan != null;

      if (summary.suspended && !selectedPlan.isSelfServe) {
        // 停止中は有料プランへの操作(購入・アップグレード・ダウングレード予約)を
        // すべて塞ぐ。Freeへの切り替え(=解約)だけは下の分岐のまま通す。
        continueLabel = l10n.plansSuspendedButton;
        onContinue = null;
      } else if (isPendingTargetSelected) {
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
        if (onPlanActivated != null) {
          // オンボーディング等: すでにこのプランに加入している場合でも、
          // アップグレードを強制せず「現在のプランで続ける」としてそのまま次へ進める(購入・更新は行わない)。
          continueLabel = l10n.plansContinueWithCurrentPlanButton;
          onContinue = () => notifyPlanActivated('continue_with_current_plan');
        } else {
          continueLabel = l10n.plansCurrentPlanButton;
          onContinue = null;
        }
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
          if (hasClaimedDeviceFree.value) {
            continueLabel = l10n.plansUnavailableButton;
            onContinue = null;
          } else {
            continueLabel = actionLabel;
            onContinue = () => handleClaimFree(selectedPlan);
          }
        } else if (purchaseState.package != null) {
          // カードにトライアルのバッジを出している時は、CTAの文言も揃える
          // (カードは「無料」なのにボタンは「アップグレード」という
          //  食い違いを作らない)。購入処理自体は通常と同じ経路。
          continueLabel = purchaseState.trialPeriod != null
              ? l10n.plansStartFreeTrialButton(purchaseState.trialPeriod!.localizedDuration(l10n))
              : actionLabel;
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
      isContinueLoading = purchasingPlanId.value == selectedPlan.id;
      continueColor = planThemeColor(selectedPlan.tierLevel);
      isUpgradeAction = !purchaseState.isCurrentPlan &&
          hasActivePlan &&
          currentPlan != null &&
          (selectedPlan.tierLevel != currentPlan.tierLevel
              ? selectedPlan.tierLevel > currentPlan.tierLevel
              : (sortedPlans.indexOf(selectedPlan) > sortedPlans.indexOf(currentPlan)));
      isPremiumPlan = selectedPlan.isPremiumTier;
    }

    // Androidではストア課金導線を一切出さない(Google Play Consumption-only
    // ポリシーに沿うため、購入ボタン自体を無効化ではなく非表示にする)。
    // 有料プランの内容(内容・カード)は引き続き閲覧できるが、フローティング
    // Continueボタンの代わりに、ウェブサイト誘導の開示文言と、
    // (オンボーディング文脈=onPlanActivated != nullの時のみ)常に固定で
    // 「Freeプランで始める」ボタンを通常のスクロール内に置く。
    final isAndroid = Platform.isAndroid;
    final freePlan = sortedPlans.where((p) => p.isSelfServe).firstOrNull;

    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final baseCardHeight = 450.0 * math.max(1.0, textScale);
    final carouselHeight = math.max(baseCardHeight, MediaQuery.sizeOf(context).height * 0.49);

    return AnimatedContainer(
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
                // ヘッダー〜開示文言を1つのスクロール領域にまとめる。
                // フローティングContinueボタンだけがこの外側(Stack)に留まり、常に見える。
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 160),
                    child: Column(
                      children: [
                        header,
                        if (summary != null && summary.suspended) const AccountSuspendedBanner(),
                        if (isLoadingPlans) ...[
                          SizedBox(
                            height: carouselHeight + 56,
                            child: const Center(
                              child: CircularProgressIndicator(color: AppColors.starGold, strokeWidth: 2.5),
                            ),
                          ),
                        ] else if (hasPlansError) ...[
                          SizedBox(
                            height: carouselHeight + 56,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    l10n.plansLoadError,
                                    style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
                                  ),
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: () => ref.invalidate(claimablePlansProvider),
                                    child: Text(
                                      l10n.commonRetryButton,
                                      style: const TextStyle(color: AppColors.starGold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ] else ...[
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
                              introEligibility: introEligibilityAsync.asData?.value,
                              purchasingPlanId: purchasingPlanId.value,
                              pendingPlanId: summary?.pendingPlanId,
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (isAndroid) ...[
                            _PlanAndroidWebRedirectNotice(l10n: l10n),
                            const SizedBox(height: 16),
                            _PlanLegalLinksRow(l10n: l10n),
                            if (onPlanActivated != null && !summaryIsUnknown) ...[
                              const SizedBox(height: 20),
                              if (hasActivePlan)
                                // Web/他プラットフォームで既に何らかのプラン(Freeも含む)に
                                // 加入済みなら、Androidではプラン変更ができないため
                                // 常にそのまま先へ進めるだけにする。ここでFreeの
                                // claim_planを呼ぶと、既存プランが残ったまま
                                // Freeプラン分のクレジットが二重付与されてしまう。
                                _PlanContinueWithCurrentButton(
                                  label: currentPlan != null
                                      ? l10n.plansContinueWithPlanButton(currentPlan.name)
                                      : l10n.plansContinueWithCurrentPlanButton,
                                  onPressed: () => notifyPlanActivated('android_continue_with_current'),
                                )
                              else if (freePlan != null)
                                _PlanStartFreeButton(
                                  l10n: l10n,
                                  isLoading: purchasingPlanId.value == freePlan.id,
                                  isAlreadyClaimed: hasClaimedDeviceFree.value,
                                  onPressed: () => handleClaimFree(freePlan),
                                ),
                            ],
                            const SizedBox(height: 24),
                          ] else
                            _PlanDisclosureContent(l10n: l10n),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (!isAndroid)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _PlanFloatingContinueBar(
                  label: continueLabel,
                  color: continueColor,
                  isLoading: isContinueLoading,
                  isUpgrade: isUpgradeAction,
                  isPremiumPlan: isPremiumPlan,
                  onPressed: onContinue,
                  l10n: l10n,
                  onRestorePurchases: handleRestorePurchases,
                  isRestoring: isRestoringPurchases.value,
                  onRedeemCode: handleRedeemCode,
                  isRedeeming: isRedeemingCode.value,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 開示文言(利用規約・プライバシーポリシーへのリンク含む)
// ─────────────────────────────────────────────────────────────────────────────

class _PlanDisclosureContent extends StatelessWidget {
  const _PlanDisclosureContent({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        l10n.plansDisclosure,
        style: TextStyle(color: AppColors.universe.textComet, fontSize: 12, height: 1.5),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Android向け: ウェブサイト誘導の開示文言(通常のカード状ハイライトで目立たせる)
// ─────────────────────────────────────────────────────────────────────────────

class _PlanAndroidWebRedirectNotice extends StatelessWidget {
  const _PlanAndroidWebRedirectNotice({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return AndroidWebRedirectNoticeCard(
      text: l10n.plansDisclosureAndroid,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 利用規約・プライバシーポリシーのリンク行(Android版はRestore Purchasesを含まない)
// ─────────────────────────────────────────────────────────────────────────────

class _PlanLegalLinksRow extends StatelessWidget {
  const _PlanLegalLinksRow({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
          Text('•', style: TextStyle(color: AppColors.universe.textComet.withValues(alpha: 0.5), fontSize: 10)),
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
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Android向けオンボーディング専用:「Freeプランで始める」固定ボタン
// カルーセルの選択状態とは無関係に、常にFreeプランのアクティベートだけを行う。
// ─────────────────────────────────────────────────────────────────────────────

class _PlanStartFreeButton extends StatelessWidget {
  const _PlanStartFreeButton({
    required this.l10n,
    required this.isLoading,
    required this.isAlreadyClaimed,
    required this.onPressed,
  });

  final AppLocalizations l10n;
  final bool isLoading;
  final bool isAlreadyClaimed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: (isLoading || isAlreadyClaimed) ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.starGold,
            foregroundColor: Colors.black,
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
              : Text(
                  isAlreadyClaimed ? l10n.plansUnavailableButton : l10n.plansStartFreeButton,
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Android向けオンボーディング専用:「{プラン名}プランで続ける」固定ボタン
// 既に何らかのプラン(Web加入分を含む)がactiveな場合に表示し、購入も
// claim_planも呼ばずそのまま次のステップへ進める。
// ─────────────────────────────────────────────────────────────────────────────

class _PlanContinueWithCurrentButton extends StatelessWidget {
  const _PlanContinueWithCurrentButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.starGold,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// フローティングContinueボタン (Upgrade時は豪華なグロー・グラデーション装飾)
// ─────────────────────────────────────────────────────────────────────────────

class _PlanFloatingContinueBar extends StatelessWidget {
  const _PlanFloatingContinueBar({
    required this.label,
    required this.color,
    required this.isLoading,
    required this.isUpgrade,
    required this.isPremiumPlan,
    required this.onPressed,
    required this.l10n,
    required this.onRestorePurchases,
    required this.isRestoring,
    required this.onRedeemCode,
    required this.isRedeeming,
  });

  final String label;
  final Color color;
  final bool isLoading;
  final bool isUpgrade;
  final bool isPremiumPlan;
  final VoidCallback? onPressed;
  final AppLocalizations l10n;
  final VoidCallback onRestorePurchases;
  final bool isRestoring;
  final VoidCallback onRedeemCode;
  final bool isRedeeming;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final bottomPadding = math.max(bottomInset, 8.0) + 4.0;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.universe.voidBackground.withValues(alpha: 0.82),
            border: Border(top: BorderSide(color: AppColors.universe.glassBorder)),
          ),
          padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 50,
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
              const SizedBox(height: 8),
              Wrap(
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
                  Text(
                    '•',
                    style: TextStyle(
                      color: AppColors.universe.textComet.withValues(alpha: 0.5),
                      fontSize: 10,
                    ),
                  ),
                  _FooterActionLink(
                    label: l10n.plansRestorePurchasesButton,
                    isLoading: isRestoring,
                    // 復元とコード引き換えは同時に走らせない(どちらもRevenueCatの状態を更新する)。
                    onTap: isRedeeming ? null : onRestorePurchases,
                  ),
                  Text(
                    '•',
                    style: TextStyle(
                      color: AppColors.universe.textComet.withValues(alpha: 0.5),
                      fontSize: 10,
                    ),
                  ),
                  _FooterActionLink(
                    label: l10n.plansRedeemCodeButton,
                    isLoading: isRedeeming,
                    onTap: isRestoring ? null : onRedeemCode,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// フッターの小さな下線リンク(「購入を復元」「コードを使う」)。処理中は薄く表示して小さなスピナーを添える。
class _FooterActionLink extends StatelessWidget {
  const _FooterActionLink({required this.label, required this.isLoading, required this.onTap});

  final String label;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = isLoading
        ? AppColors.universe.textComet.withValues(alpha: 0.5)
        : AppColors.universe.textComet;
    final text = Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 11,
        decoration: TextDecoration.underline,
        decorationColor: color,
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isLoading ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: isLoading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  text,
                  const SizedBox(width: 4),
                  const SizedBox(
                    width: 9,
                    height: 9,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.starGold),
                  ),
                ],
              )
            : text,
      ),
    );
  }
}

enum _RedeemProgressPhase { checking, applying }

/// オファーコード引き換え後、プランが反映されるまでの進行状況ダイアログ。
/// 「確認中」→「反映中」と文言が切り替わる。閉じるボタンは待つのをやめるだけ
/// (反映中に閉じた場合も、裏で反映を待って結果は別途表示される)。
class _RedeemProgressDialog extends StatelessWidget {
  const _RedeemProgressDialog({required this.phase, required this.l10n, required this.onClose});

  final ValueListenable<_RedeemProgressPhase> phase;
  final AppLocalizations l10n;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1E1F29),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          l10n.plansRedeemCodeTitle,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: ValueListenableBuilder<_RedeemProgressPhase>(
          valueListenable: phase,
          builder: (context, value, _) => Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.starGold),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  value == _RedeemProgressPhase.checking
                      ? l10n.plansRedeemCodeCheckingMessage
                      : l10n.plansRedeemCodeApplyingMessage,
                  style: const TextStyle(color: Colors.white70, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: onClose,
            child: Text(l10n.plansRedeemCodeCloseButton, style: const TextStyle(color: Colors.white60)),
          ),
        ],
      ),
    );
  }
}
