import React, { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { Check, X, ExternalLink, Loader2 } from 'lucide-react';
import { useCreditSummary } from '../../hooks/useCreditSummary';
import { usePlans } from '../../hooks/usePlans';
import { switchPlan, resumePlan, getCreditSummary, type SwitchPlanResult } from '../../lib/billing';
import { ApiError, extractErrorCode } from '../../lib/api';
import { toDisplayCredits } from '../../types/billing';
import type { CreditSummary, PlanOption } from '../../types/billing';
import { tierAccent, planIconAsset } from '../../lib/planTheme';
import { PageState } from '../../components/PageState';
import { AccountSuspendedNotice } from '../../components/AccountSuspendedNotice';
import { StripeCheckoutModal } from '../../components/modals/StripeCheckoutModal';
import { PlanCelebrationDialog } from '../../components/modals/PlanCelebrationDialog';
import { ConfirmModal } from '../../components/modals/ConfirmModal';
import { useLanguage } from '../../i18n/LanguageContext';
import { CreditStarIcon } from '../../components/icons/CreditStarIcon';
import { PlansSkeleton } from '../../components/account/PlansSkeleton';
import { CreditRateTableDialog } from '../../components/CreditRateTableDialog';
import { CosmicPlanCanvas } from '../../components/account/CosmicPlanCanvas';
import type { TranslationKey } from '../../i18n/translations';

/** plan_card.dartの5行と全く同じ、必要tierのしきい値。 */
const FEATURE_ROWS: { minTier: number; key: TranslationKey }[] = [
  { minTier: 0, key: 'plansFeatureReviewCards' },
  { minTier: 1, key: 'plansFeatureDeepNotes' },
  { minTier: 2, key: 'plansFeatureTranscript' },
  { minTier: 2, key: 'plansFeatureKeywords' },
  { minTier: 3, key: 'plansFeatureRealtime' },
];

/** plan_card.dart と同じ概算式(1講義≒100クレジット、月4.1週)。 */
function weeklyLectureEstimate(monthlyCreditsMicro: number): number {
  return Math.max(1, Math.round(toDisplayCredits(monthlyCreditsMicro) / 100 / 4.1));
}

/**
 * switch-planのレスポンス(claimed/switched)はStripe側の処理完了時点のもので、
 * DBへの反映はStripe→webhook→RevenueCat→webhookという経路を経て数秒遅れて届く。
 * ここで実際にplan_idが切り替わるまで待ってから「完了」を伝える —
 * でないと、ローディングが消えた直後にまだ古いプランのまま、ということが起こる。
 * 最大約9.6秒待って確認できなければ静かに諦める(反映自体は裏側で続くので、
 * 画面は変わらないままだが失敗扱いにはしない)。
 */
async function waitForPlanSync(targetPlanId: string): Promise<boolean> {
  for (let i = 0; i < 12; i++) {
    await new Promise((resolve) => setTimeout(resolve, 800));
    try {
      const s = await getCreditSummary();
      if (s.plan_id === targetPlanId) return true;
    } catch {
      // 一時的な取得失敗は無視してリトライを続ける。
    }
  }
  return false;
}

function formatPrice(plan: PlanOption, freeLabel: string): string {
  if (plan.price_usd == null || plan.price_usd === 0) return freeLabel;
  const perMonth = plan.price_usd / Math.max(1, plan.billing_interval_months);
  const amount = `$${perMonth % 1 === 0 ? perMonth.toFixed(0) : perMonth.toFixed(2)}`;
  return amount;
}

type PendingCheckout = { plan: PlanOption; clientSecret: string; amountDueCents: number; currency: string };
type PendingAppleDiscount = { plan: PlanOption; discountUsd: number; chargeUsd: number };

export interface PlansContentProps {
  /**
   * デフォルトの見出し(戻るリンク + タイトル + タグライン)の代わりに表示するヘッダー。
   * onboarding_plan_step.dartがPlanSelectionViewへ`OnboardingStepHeader`を渡すのと同じ役割。
   */
  header?: React.ReactNode;
  /**
   * plan_selection_view.dartのonPlanActivated相当。Freeプランのclaim成立、または
   * 有料プランへの切り替え成立(お祝いダイアログを閉じた時点)で呼ばれる。
   * オンボーディングでのみ渡し、渡された場合のみ「今のプランのまま続ける」
   * バーも表示する。
   */
  onPlanActivated?: () => void;
}

/**
 * プラン一覧・比較。plan_selection_view.dart / plan_card.dart の
 * トンマナ(ダークガラス+ティア別ネオン+惑星画像)を踏襲しつつ、ウェブは横幅が
 * 使えるので、モバイル版のカルーセルではなくプランを横に並べて比較する。
 *
 * 上段は表の一部にせず独立したカード、下段が揃った比較表という構成。
 * 課金は iOS(RevenueCat/Apple)とウェブ(Stripe)の両対応で、実体は
 * /billing/stripe/switch-plan 1本(新規契約・アップグレード・ダウングレード予約・
 * Apple購読との衝突ブロックを全て内包する)。
 *
 * `/account/plans`ページと、オンボーディングのPlanステップの両方から
 * (header/onPlanActivatedだけ差し替えて)埋め込まれる共通の中身。
 */
export const PlansContent: React.FC<PlansContentProps> = ({ header, onPlanActivated }) => {
  const { summary, loading: summaryLoading, error: summaryError, refetch } = useCreditSummary(false);
  const { plans, loading: plansLoading, error: plansError } = usePlans();
  const { t, formatNumber } = useLanguage();

  const [switchingId, setSwitchingId] = useState<string | null>(null);
  const [resuming, setResuming] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pendingCheckout, setPendingCheckout] = useState<PendingCheckout | null>(null);
  const [pendingAppleDiscount, setPendingAppleDiscount] = useState<PendingAppleDiscount | null>(null);
  const [celebration, setCelebration] = useState<PlanOption | null>(null);
  const [creditRateOpen, setCreditRateOpen] = useState(false);

  const sortedPlans = useMemo(() => [...plans].sort((a, b) => a.tier_level - b.tier_level), [plans]);
  const currentTierLevel = summary?.has_active_plan ? summary.tier_level : 0;

  const applySwitchPlanResult = async (plan: PlanOption, result: SwitchPlanResult) => {
    if ('client_secret' in result) {
      setPendingCheckout({
        plan,
        clientSecret: result.client_secret,
        amountDueCents: result.amount_due_cents,
        currency: result.currency,
      });
      return;
    }
    switch (result.status) {
      case 'claimed':
        // Freeプランの初回claimは同一リクエスト内でDBを直接更新するため、
        // 反映待ちは不要(Flutter版もここはお祝い演出の対象外)。onboarding_plan_step.dart
        // のhandleClaimFreeと同じく、claim成立の時点で即座に次へ進める。
        await refetch();
        onPlanActivated?.();
        break;
      case 'switched': {
        // 即時アップグレード。DBへの反映(RevenueCat往復)を確認できたら祝う。
        // 次へ進むのはお祝いダイアログを閉じたタイミング(PlanCelebrationDialogのonClose)。
        const synced = await waitForPlanSync(plan.id);
        await refetch();
        if (synced) setCelebration(plan);
        break;
      }
      case 'already_current':
        await refetch();
        break;
      case 'scheduled_downgrade':
        setNotice(t('plansScheduledDowngrade'));
        await refetch();
        break;
      case 'scheduled_cancel':
        setNotice(t('plansScheduledCancel'));
        await refetch();
        break;
      case 'requires_confirmation':
        // App Storeで解約予約済み: Apple残存期間分の割引額を確認してもらってから
        // 実際の契約(confirm_apple_discount=true)に進む。
        setPendingAppleDiscount({ plan, discountUsd: result.discount_usd, chargeUsd: result.charge_usd });
        break;
    }
  };

  const handlePlanActionError = (err: unknown) => {
    const code = extractErrorCode(err);
    if (code === 'APPLE_SUBSCRIPTION_ACTIVE') {
      setError(t('plansAppleSubscriptionActive'));
    } else {
      setError(err instanceof ApiError ? err.message : t('plansFailedChange'));
    }
  };

  const handlePlanAction = async (plan: PlanOption) => {
    setSwitchingId(plan.id);
    setError(null);
    setNotice(null);
    try {
      const result: SwitchPlanResult = await switchPlan(plan.id);
      await applySwitchPlanResult(plan, result);
    } catch (err) {
      handlePlanActionError(err);
    } finally {
      setSwitchingId(null);
    }
  };

  const handleConfirmAppleDiscount = async () => {
    if (!pendingAppleDiscount) return;
    const { plan } = pendingAppleDiscount;
    setPendingAppleDiscount(null);
    setSwitchingId(plan.id);
    setError(null);
    try {
      const result = await switchPlan(plan.id, { confirmAppleDiscount: true });
      await applySwitchPlanResult(plan, result);
    } catch (err) {
      handlePlanActionError(err);
    } finally {
      setSwitchingId(null);
    }
  };

  const handleCheckoutSuccess = async () => {
    if (!pendingCheckout) return;
    const { plan } = pendingCheckout;
    // モーダルは(StripeCheckoutModal側で)この関数が解決するまで開いたままになる。
    const synced = await waitForPlanSync(plan.id);
    await refetch();
    setPendingCheckout(null);
    if (synced) setCelebration(plan);
  };

  const handleResumePlan = async () => {
    setResuming(true);
    setError(null);
    setNotice(null);
    try {
      await resumePlan();
      await refetch();
      setNotice(t('plansScheduledCancelled'));
    } catch (err) {
      const code = extractErrorCode(err);
      if (code === 'APPLE_MANAGED_SUBSCRIPTION') {
        setError(t('plansAppleManagedCancelError'));
      } else {
        setError(err instanceof ApiError ? err.message : t('plansFailedCancel'));
      }
    } finally {
      setResuming(false);
    }
  };

  const loading = summaryLoading || plansLoading;
  // カード列と比較表で同じ列定義を共有し、上下の列をぴたりと揃える。
  // 幅が十分にある時は横幅いっぱいに自然に広がり、横スクロールなしでそのまま表示される。
  const gridColumns = `minmax(150px, 1.1fr) repeat(${sortedPlans.length}, minmax(160px, 1fr))`;

  const showContinueWithCurrent = Boolean(onPlanActivated) && Boolean(summary?.has_active_plan);

  return (
    <div className="plans-content">
      {header ?? (
        <>
          <Link to="/account/credits" className="back-link">
            ← {t('plansBackToCredits')}
          </Link>
          <h1 className="plans-title">{t('plansTitle')}</h1>
          <p className="plans-tagline">{t('plansTagline')}</p>
        </>
      )}

      {loading && <PlansSkeleton />}
      {(summaryError || plansError) && <PageState kind="error" message={summaryError ?? plansError ?? undefined} />}

      {summary?.suspended && <AccountSuspendedNotice variant="plans" />}
      {notice && <p className="notice">{notice}</p>}
      {error && <p className="notice notice-error">{error}</p>}

      {!loading && !summaryError && !plansError && summary && sortedPlans.length > 0 && (
        <div className="plans-content-area">
          {/* ── 上段: 独立したプランカード(960px以下では横幅100%均等、横スクロールなし) ── */}
          <div className="plans-cards-section">
            <div className="plans-card-row" style={{ ['--plans-grid-columns' as string]: gridColumns }}>
              <div className="plans-row-label-spacer" aria-hidden="true" />
              {sortedPlans.map((plan) => (
                <PlanCard
                  key={plan.id}
                  plan={plan}
                  summary={summary}
                  currentTierLevel={currentTierLevel}
                  switching={switchingId === plan.id}
                  onAction={() => handlePlanAction(plan)}
                  resuming={resuming}
                  onResume={handleResumePlan}
                  onCreditRateClick={() => setCreditRateOpen(true)}
                />
              ))}
            </div>
          </div>

          {/* ── 下段: 独立した比較表(枠線で囲わず、狭い画面では独立して横スクロール可能) ── */}
          <div className="plans-table-scroll">
            <div className="plans-compare" style={{ gridTemplateColumns: gridColumns }}>
              {/* 960px以下で表が独立した際に各列の上に表示するプラン名 & アイコン行 */}
              <div className="plans-compare-cell plans-compare-label is-plan-head">
                <span className="plans-table-head-title">{t('plansFeatures')}</span>
              </div>
              {sortedPlans.map((plan) => {
                const { accent } = tierAccent(plan.tier_level);
                return (
                  <div
                    key={plan.id}
                    className="plans-compare-cell plans-plan-head-cell is-plan-head"
                    style={{ ['--plan-accent' as string]: accent }}
                  >
                    <img src={planIconAsset(plan.tier_level)} alt="" className="plans-table-plan-icon" />
                    <span className="plans-table-plan-name">{plan.name}</span>
                  </div>
                );
              })}

              <div className="plans-compare-cell plans-compare-label is-head">{t('plansMonthlyCredits')}</div>
              {sortedPlans.map((plan) => {
                const { accent } = tierAccent(plan.tier_level);
                return (
                  <button
                    key={plan.id}
                    type="button"
                    className="plans-compare-cell plans-credits-cell is-head"
                    style={{ ['--plan-accent' as string]: accent }}
                    onClick={() => setCreditRateOpen(true)}
                  >
                    <span className="plans-credits-amount">
                      {formatNumber(toDisplayCredits(plan.monthly_credit_amount))}
                    </span>
                    <span className="plans-credits-unit">{t('creditsUnitMonthly')}</span>
                    <span className="plans-credits-estimate">
                      {t('plansApproxLecturesPerWeek', {
                        count: weeklyLectureEstimate(plan.monthly_credit_amount),
                        unit: weeklyLectureEstimate(plan.monthly_credit_amount) === 1 ? 'lecture' : 'lectures',
                      })}
                    </span>
                  </button>
                );
              })}

              {FEATURE_ROWS.map((row, i) => (
                <React.Fragment key={i}>
                  <div className="plans-compare-cell plans-compare-label">{t(row.key)}</div>
                  {sortedPlans.map((plan) => {
                    const included = plan.tier_level >= row.minTier;
                    return (
                      <div
                        key={plan.id}
                        className={`plans-compare-cell plans-check-cell ${included ? 'is-included' : ''}`}
                        style={{ ['--plan-accent' as string]: tierAccent(plan.tier_level).accent }}
                      >
                        {included ? <Check size={18} /> : <X size={16} />}
                      </div>
                    );
                  })}
                </React.Fragment>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* ── フッター注意書き & リンク (追加クレジットページと同一) ── */}
      <div className="purchase-credits-footer">
        <p className="purchase-credits-disclosure">{t('plansDisclosure')}</p>

        <div className="purchase-credits-links">
          <a href="https://lefture.com/terms" target="_blank" rel="noopener noreferrer">
            {t('termsOfService')}
            <ExternalLink size={11} />
          </a>
          <span className="purchase-credits-dot">•</span>
          <a href="https://lefture.com/privacy" target="_blank" rel="noopener noreferrer">
            {t('privacyPolicy')}
            <ExternalLink size={11} />
          </a>
          <span className="purchase-credits-dot">•</span>
          <a href="https://lefture.com/contact" target="_blank" rel="noopener noreferrer">
            {t('contactUs')}
            <ExternalLink size={11} />
          </a>
        </div>
      </div>

      {showContinueWithCurrent && (
        <div className="onb-plan-continue-bar">
          <button type="button" className="onb-cta-btn" onClick={onPlanActivated}>
            {t('onboardingPlanContinueWithCurrent')}
          </button>
        </div>
      )}

      {pendingCheckout && (
        <StripeCheckoutModal
          title={pendingCheckout.plan.name}
          tierLevel={pendingCheckout.plan.tier_level}
          clientSecret={pendingCheckout.clientSecret}
          charge={{
            amountCents: pendingCheckout.amountDueCents,
            currency: pendingCheckout.currency,
            recurring: {
              priceUsd: pendingCheckout.plan.price_usd ?? 0,
              intervalMonths: pendingCheckout.plan.billing_interval_months,
            },
          }}
          onClose={() => setPendingCheckout(null)}
          onSuccess={handleCheckoutSuccess}
        />
      )}

      {celebration && (
        <PlanCelebrationDialog
          plan={celebration}
          onClose={() => {
            setCelebration(null);
            onPlanActivated?.();
          }}
        />
      )}

      <ConfirmModal
        open={pendingAppleDiscount != null}
        onClose={() => setPendingAppleDiscount(null)}
        onConfirm={handleConfirmAppleDiscount}
        title={t('plansAppleDiscountTitle')}
        message={
          pendingAppleDiscount
            ? t('plansAppleDiscountMessage', {
                discount: pendingAppleDiscount.discountUsd.toFixed(2),
                charge: pendingAppleDiscount.chargeUsd.toFixed(2),
              })
            : null
        }
        confirmLabel={t('plansAppleDiscountConfirm')}
        cancelLabel={t('cancel')}
      />

      {creditRateOpen && <CreditRateTableDialog onClose={() => setCreditRateOpen(false)} />}
    </div>
  );
};

// ─────────────────────────────────────────────────────────────────────────
// プランカード(独立したカード。画像は背景として大きく敷く)
// ─────────────────────────────────────────────────────────────────────────

const PlanCard: React.FC<{
  plan: PlanOption;
  summary: CreditSummary;
  currentTierLevel: number;
  switching: boolean;
  onAction: () => void;
  resuming: boolean;
  onResume: () => void;
  onCreditRateClick: () => void;
}> = ({ plan, summary, currentTierLevel, switching, onAction, resuming, onResume, onCreditRateClick }) => {
  const { t, formatNumber } = useLanguage();
  const { accent, isPremium, isStandard } = tierAccent(plan.tier_level);
  const isCurrentPlan = summary.has_active_plan && summary.plan_id === plan.id;
  const isPendingTarget = summary.pending_plan_id === plan.id;
  // 今のプランから、次回更新日に別プランへ切り替わることが予約されているか。
  // (isPendingTargetはその「切り替え先」のカードを指すのに対し、こちらは
  // 「切り替え元(今のプラン)」のカードで予約取り消しボタンを出すために使う)
  const hasScheduledChange = isCurrentPlan && Boolean(summary.pending_plan_id);
  // store_purchaseかつStripe価格が無いプランは、ウェブからは購入できない(Apple専用)。
  const isPurchasableOnWeb = plan.claim_mode === 'self_serve' || Boolean(plan.stripe_price_id);

  // 停止中は有料プランへの操作(購入・アップグレード・解約取消)をすべて塞ぐ。
  // Free(self_serve)への切り替え=解約だけは通す。
  const blockedBySuspension = summary.suspended && plan.claim_mode !== 'self_serve';

  let action: React.ReactNode;
  if (isCurrentPlan) {
    action = (
      <>
        <span className="plans-badge is-current">{t('plansCurrentBadge')}</span>
        {hasScheduledChange && !summary.suspended && (
          <button type="button" className="plans-resume-btn" onClick={onResume} disabled={resuming}>
            {resuming && <Loader2 size={13} className="animate-spin" />}
            {resuming ? t('plansWorking') : t('plansKeepCurrent')}
          </button>
        )}
      </>
    );
  } else if (isPendingTarget) {
    action = <span className="plans-badge is-pending">{t('plansScheduledBadge')}</span>;
  } else if (blockedBySuspension) {
    action = <span className="plans-badge is-ios-only">{t('plansUnavailableSuspended')}</span>;
  } else if (!isPurchasableOnWeb) {
    action = <span className="plans-badge is-ios-only">{t('plansIosOnlyBadge')}</span>;
  } else {
    const isStartFree = !summary.has_active_plan && plan.claim_mode === 'self_serve';
    const isUpgrade = !isStartFree && plan.tier_level > currentTierLevel;
    const label = isStartFree ? t('plansStartFree') : isUpgrade ? t('plansUpgrade') : t('plansDowngrade');
    const btnClass = `plans-action-btn ${
      isUpgrade ? (isPremium ? 'is-upgrade is-premium-upgrade' : 'is-upgrade') : 'is-downgrade'
    }`;
    action = (
      <button type="button" className={btnClass} onClick={onAction} disabled={switching}>
        {switching && <Loader2 size={14} className="animate-spin" />}
        {switching ? t('plansWorking') : label}
      </button>
    );
  }

  return (
    <article
      className={`plans-card ${isPremium ? 'is-premium' : isStandard ? 'is-standard' : ''} ${
        isCurrentPlan ? 'is-current' : ''
      }`}
      style={{ ['--plan-accent' as string]: accent }}
    >
      {/* Core 専用エフェクト: ソーラーコロナ・温かい呼吸光彩と黄金の火の粉 (約1.3倍の密度と速度) */}
      {isStandard && (
        <div className="plans-effect-solar-corona" aria-hidden="true">
          <div className="solar-corona-glow" />
          <div className="solar-ember ember-1" />
          <div className="solar-ember ember-2" />
          <div className="solar-ember ember-3" />
          <div className="solar-ember ember-4" />
          <div className="solar-ember ember-5" />
          <div className="solar-ember ember-6" />
          <div className="solar-ember ember-7" />
          <div className="solar-ember ember-8" />
        </div>
      )}

      {/* Max 専用エフェクト: コズミック星雲オーロラ・ホログラフィック偏光光帯・連動ラメパーティクル */}
      {isPremium && (
        <div className="plans-effect-cosmic" aria-hidden="true">
          <CosmicPlanCanvas />
        </div>
      )}

      {/* 背景に大きく溶け込む固定サイズ画像 */}
      <img src={planIconAsset(plan.tier_level)} alt="" className="plans-card-bg-fixed" aria-hidden="true" />

      <div className="plans-card-body">
        <div className="plans-card-info">
          <h2 className="plans-card-name">{plan.name}</h2>
          <p className="plans-card-price">
            <span className="plans-card-price-amount">{formatPrice(plan, t('planPriceFree'))}</span>
            {plan.price_usd != null && plan.price_usd > 0 && (
              <span className="plans-card-price-unit">{t('perMonth')}</span>
            )}
          </p>
          <button type="button" className="plans-card-credits-compact" onClick={onCreditRateClick}>
            <CreditStarIcon size={12} color="var(--star-gold, #fbc02d)" />
            <span>
              {formatNumber(toDisplayCredits(plan.monthly_credit_amount))} {t('creditsUnitMo')}
            </span>
          </button>
        </div>
        <div className="plans-card-action">{action}</div>
      </div>
    </article>
  );
};
