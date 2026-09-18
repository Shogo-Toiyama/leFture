import React, { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { Check, X, ExternalLink } from 'lucide-react';
import { useCreditSummary } from '../../hooks/useCreditSummary';
import { usePlans } from '../../hooks/usePlans';
import { switchPlan, type SwitchPlanResult } from '../../lib/billing';
import { ApiError, extractErrorCode } from '../../lib/api';
import { toDisplayCredits } from '../../types/billing';
import type { CreditSummary, PlanOption } from '../../types/billing';
import { tierAccent, planIconAsset } from '../../lib/planTheme';
import { PageState } from '../../components/PageState';
import { StripeCheckoutModal } from '../../components/modals/StripeCheckoutModal';
import { useLanguage } from '../../i18n/LanguageContext';
import { CreditStarIcon } from '../../components/icons/CreditStarIcon';
import { PlansSkeleton } from '../../components/account/PlansSkeleton';


/** plan_card.dartの5行と全く同じ、必要tierのしきい値。 */
const FEATURE_ROWS: { minTier: number; en: string; ja: string }[] = [
  { minTier: 0, en: 'Review Cards & Fun Facts generation', ja: 'Review CardsとFun Fact生成' },
  { minTier: 1, en: 'DeepNotes (detailed notes) generation', ja: 'DeepNotes（詳細ノート）生成' },
  { minTier: 2, en: 'Transcript, audio playback & source search', ja: '文字起こし・音声再生・出典検索' },
  { minTier: 2, en: 'Keyword & announcement generation', ja: 'キーワード・アナウンスメント生成' },
  { minTier: 3, en: 'Real-time transcription', ja: 'リアルタイム文字起こし' },
];

/** plan_card.dart と同じ概算式(1講義≒100クレジット、月4.1週)。 */
function weeklyLectureEstimate(monthlyCreditsMicro: number): number {
  return Math.max(1, Math.round(toDisplayCredits(monthlyCreditsMicro) / 100 / 4.1));
}

/** webhookの反映(RevenueCat往復含む)を待つための短時間リトライ。他ページと同じ考え方。 */
async function waitAndRefetch(refetch: () => Promise<void>) {
  for (let i = 0; i < 4; i++) {
    await new Promise((resolve) => setTimeout(resolve, 3000));
    await refetch();
  }
}

function formatPrice(plan: PlanOption, isJa: boolean): string {
  if (plan.price_usd == null || plan.price_usd === 0) return isJa ? '無料' : 'Free';
  const perMonth = plan.price_usd / Math.max(1, plan.billing_interval_months);
  const amount = `$${perMonth % 1 === 0 ? perMonth.toFixed(0) : perMonth.toFixed(2)}`;
  return amount;
}

type PendingCheckout = { planId: string; planName: string; clientSecret: string };

/**
 * プラン一覧・比較ページ。plan_selection_view.dart / plan_card.dart の
 * トンマナ(ダークガラス+ティア別ネオン+惑星画像)を踏襲しつつ、ウェブは横幅が
 * 使えるので、モバイル版のカルーセルではなくプランを横に並べて比較する。
 *
 * 上段は表の一部にせず独立したカード、下段が揃った比較表という構成。
 * 課金は iOS(RevenueCat/Apple)とウェブ(Stripe)の両対応で、実体は
 * /billing/stripe/switch-plan 1本(新規契約・アップグレード・ダウングレード予約・
 * Apple購読との衝突ブロックを全て内包する)。
 */
export const PlansPage: React.FC = () => {
  const { summary, loading: summaryLoading, error: summaryError, refetch } = useCreditSummary(false);
  const { plans, loading: plansLoading, error: plansError } = usePlans();
  const { language } = useLanguage();
  const isJa = language === 'ja';

  const [switchingId, setSwitchingId] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pendingCheckout, setPendingCheckout] = useState<PendingCheckout | null>(null);

  const sortedPlans = useMemo(() => [...plans].sort((a, b) => a.tier_level - b.tier_level), [plans]);
  const currentTierLevel = summary?.has_active_plan ? summary.tier_level : 0;

  const handlePlanAction = async (plan: PlanOption) => {
    setSwitchingId(plan.id);
    setError(null);
    setNotice(null);
    try {
      const result: SwitchPlanResult = await switchPlan(plan.id);
      if ('client_secret' in result) {
        setPendingCheckout({ planId: plan.id, planName: plan.name, clientSecret: result.client_secret });
        return;
      }
      switch (result.status) {
        case 'claimed':
        case 'switched':
        case 'already_current':
          await refetch();
          break;
        case 'scheduled_downgrade':
          setNotice(
            isJa
              ? 'プランの変更は次回更新日から反映されます。それまでは現在のプランのままです。'
              : 'Your plan change will take effect at your next renewal. Until then, your current plan stays active.'
          );
          await refetch();
          break;
        case 'scheduled_cancel':
          setNotice(
            isJa
              ? '次回更新日にFreeプランへ切り替わります。それまでは現在のプランのままです。'
              : 'You will switch to the Free plan at your next renewal. Until then, your current plan stays active.'
          );
          await refetch();
          break;
      }
    } catch (err) {
      const code = extractErrorCode(err);
      if (code === 'APPLE_SUBSCRIPTION_ACTIVE') {
        setError(
          isJa
            ? 'すでにApp Store経由の購読が有効です。ウェブで購読する前に、iOS端末の設定でその購読を解約してください。'
            : 'You already have an active subscription through the App Store. Please cancel it in your iOS device settings before subscribing on the web.'
        );
      } else {
        setError(err instanceof ApiError ? err.message : isJa ? 'プランの変更に失敗しました' : 'Failed to change plan');
      }
    } finally {
      setSwitchingId(null);
    }
  };

  const handleCheckoutSuccess = () => {
    setPendingCheckout(null);
    void waitAndRefetch(refetch);
  };

  const loading = summaryLoading || plansLoading;
  // カード列と比較表で同じ列定義を共有し、上下の列をぴたりと揃える。
  // 幅が十分にある時は横幅いっぱいに自然に広がり、横スクロールなしでそのまま表示される。
  const gridColumns = `minmax(150px, 1.1fr) repeat(${sortedPlans.length}, minmax(160px, 1fr))`;

  return (
    <div className="plans-page">
      {/* 上部コズミックスペクトラム極光グラデーション (Core:黄 → Standard:青 → Pro:赤 → Max:紫) */}
      <div className="plans-top-gradient" aria-hidden="true" />
      <div className="plans-page-inner">
        <Link to="/account/credits" className="back-link">
          ← {isJa ? 'クレジット' : 'Credits'}
        </Link>
        <h1 className="plans-title">{isJa ? 'プラン' : 'Plans'}</h1>
        <p className="plans-tagline">
          {isJa ? 'leFtureでプレミアム機能を解放しよう' : 'Get premium access on leFture'}
        </p>

        {loading && <PlansSkeleton />}
        {(summaryError || plansError) && (
          <PageState kind="error" message={summaryError ?? plansError ?? undefined} />
        )}

        {notice && <p className="notice">{notice}</p>}
        {error && <p className="notice notice-error">{error}</p>}

        {!loading && !summaryError && !plansError && summary && sortedPlans.length > 0 && (
          <div className="plans-content-area">
            {/* ── 上段: 独立したプランカード(960px以下では横幅100%均等、横スクロールなし) ── */}
            <div className="plans-cards-section">
              <div
                className="plans-card-row"
                style={{ ['--plans-grid-columns' as string]: gridColumns }}
              >
                <div className="plans-row-label-spacer" aria-hidden="true" />
                {sortedPlans.map((plan) => (
                  <PlanCard
                    key={plan.id}
                    plan={plan}
                    summary={summary}
                    currentTierLevel={currentTierLevel}
                    switching={switchingId === plan.id}
                    onAction={() => handlePlanAction(plan)}
                    isJa={isJa}
                  />
                ))}
              </div>
            </div>

            {/* ── 下段: 独立した比較表(枠線で囲わず、狭い画面では独立して横スクロール可能) ── */}
            <div className="plans-table-scroll">
              <div className="plans-compare" style={{ gridTemplateColumns: gridColumns }}>
                {/* 960px以下で表が独立した際に各列の上に表示するプラン名 & アイコン行 */}
                <div className="plans-compare-cell plans-compare-label is-plan-head">
                  <span className="plans-table-head-title">{isJa ? '機能' : 'Features'}</span>
                </div>
                {sortedPlans.map((plan) => {
                  const { accent } = tierAccent(plan.tier_level);
                  return (
                    <div
                      key={plan.id}
                      className="plans-compare-cell plans-plan-head-cell is-plan-head"
                      style={{ ['--plan-accent' as string]: accent }}
                    >
                      <img
                        src={planIconAsset(plan.tier_level)}
                        alt=""
                        className="plans-table-plan-icon"
                      />
                      <span className="plans-table-plan-name">{plan.name}</span>
                    </div>
                  );
                })}

                <div className="plans-compare-cell plans-compare-label is-head">
                  {isJa ? '月間クレジット' : 'Monthly credits'}
                </div>
                {sortedPlans.map((plan) => {
                  const { accent } = tierAccent(plan.tier_level);
                  return (
                    <div
                      key={plan.id}
                      className="plans-compare-cell plans-credits-cell is-head"
                      style={{ ['--plan-accent' as string]: accent }}
                    >
                      <span className="plans-credits-amount">
                        {toDisplayCredits(plan.monthly_credit_amount).toLocaleString()}
                      </span>
                      <span className="plans-credits-unit">
                        {isJa ? 'クレジット / 月' : 'credits / month'}
                      </span>
                      <span className="plans-credits-estimate">
                        {isJa
                          ? `約週${weeklyLectureEstimate(plan.monthly_credit_amount)}回の講義`
                          : `Approx. ${weeklyLectureEstimate(plan.monthly_credit_amount)} ${
                              weeklyLectureEstimate(plan.monthly_credit_amount) === 1 ? 'lecture' : 'lectures'
                            } / week`}
                      </span>
                    </div>
                  );
                })}

                {FEATURE_ROWS.map((row, i) => (
                  <React.Fragment key={i}>
                    <div className="plans-compare-cell plans-compare-label">{isJa ? row.ja : row.en}</div>
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
          <p className="purchase-credits-disclosure">
            {isJa
              ? 'プランは期間終了の24時間前までにキャンセルしない限り、毎月自動的に更新されます。ダウングレードは即時ではなく次回請求期間の開始時に反映され、それまでは現在のプランとクレジットがそのまま有効です。App Store経由で購読中のプランは、iOS端末のアカウント設定からのみ解約・変更できます。'
              : "Plans renew automatically each month unless canceled at least 24 hours before the end of the current period. Downgrades take effect at the start of your next billing period, not immediately — your current plan and credits stay active until then. A subscription purchased through the App Store can only be managed or canceled in your iOS device's account settings."}
          </p>

          <div className="purchase-credits-links">
            <a href="https://lefture.com/terms" target="_blank" rel="noopener noreferrer">
              {isJa ? '利用規約' : 'Terms of Service'}
              <ExternalLink size={11} />
            </a>
            <span className="purchase-credits-dot">•</span>
            <a href="https://lefture.com/privacy" target="_blank" rel="noopener noreferrer">
              {isJa ? 'プライバシーポリシー' : 'Privacy Policy'}
              <ExternalLink size={11} />
            </a>
            <span className="purchase-credits-dot">•</span>
            <a href="https://lefture.com/contact" target="_blank" rel="noopener noreferrer">
              {isJa ? 'お問い合わせ' : 'Contact Us'}
              <ExternalLink size={11} />
            </a>
          </div>
        </div>
      </div>

      {pendingCheckout && (
        <StripeCheckoutModal
          title={pendingCheckout.planName}
          clientSecret={pendingCheckout.clientSecret}
          onClose={() => setPendingCheckout(null)}
          onSuccess={handleCheckoutSuccess}
        />
      )}
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
  isJa: boolean;
}> = ({ plan, summary, currentTierLevel, switching, onAction, isJa }) => {
  const { accent, isPremium, isStandard } = tierAccent(plan.tier_level);
  const isCurrentPlan = summary.has_active_plan && plan.monthly_credit_amount === summary.monthly_allocation;
  const isPendingTarget = summary.pending_plan_id === plan.id;
  // store_purchaseかつStripe価格が無いプランは、ウェブからは購入できない(Apple専用)。
  const isPurchasableOnWeb = plan.claim_mode === 'self_serve' || Boolean(plan.stripe_price_id);

  let action: React.ReactNode;
  if (isCurrentPlan) {
    action = <span className="plans-badge is-current">{isJa ? '現在のプラン' : 'CURRENT PLAN'}</span>;
  } else if (isPendingTarget) {
    action = <span className="plans-badge is-pending">{isJa ? '変更予約中' : 'SCHEDULED'}</span>;
  } else if (!isPurchasableOnWeb) {
    action = <span className="plans-badge is-ios-only">{isJa ? 'iOSアプリのみ' : 'iOS app only'}</span>;
  } else {
    const isStartFree = !summary.has_active_plan && plan.claim_mode === 'self_serve';
    const isUpgrade = !isStartFree && plan.tier_level > currentTierLevel;
    const label = isStartFree
      ? isJa
        ? 'Freeプランで始める'
        : 'Start with Free'
      : isUpgrade
        ? isJa
          ? 'アップグレード'
          : 'Upgrade'
        : isJa
          ? 'ダウングレード'
          : 'Downgrade';
    const btnClass = `plans-action-btn ${
      isUpgrade ? (isPremium ? 'is-upgrade is-premium-upgrade' : 'is-upgrade') : 'is-downgrade'
    }`;
    action = (
      <button type="button" className={btnClass} onClick={onAction} disabled={switching}>
        {switching ? (isJa ? '処理中…' : 'Working…') : label}
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
      {/* Core 専用エフェクト: ソーラーコロナ・温かい呼吸光彩と黄金の火の粉 */}
      {isStandard && (
        <div className="plans-effect-solar-corona" aria-hidden="true">
          <div className="solar-corona-glow" />
          <div className="solar-ember ember-1" />
          <div className="solar-ember ember-2" />
          <div className="solar-ember ember-3" />
          <div className="solar-ember ember-4" />
          <div className="solar-ember ember-5" />
        </div>
      )}

      {/* Max 専用エフェクト: コズミック星雲オーロラ・ホログラフィックスイープ・瞬く星屑 */}
      {isPremium && (
        <div className="plans-effect-cosmic" aria-hidden="true">
          <div className="cosmic-nebula nebula-violet" />
          <div className="cosmic-nebula nebula-cyan" />
          <div className="cosmic-holographic-sweep" />
          <div className="cosmic-star star-1" />
          <div className="cosmic-star star-2" />
          <div className="cosmic-star star-3" />
          <div className="cosmic-star star-4" />
          <div className="cosmic-star star-5" />
          <div className="cosmic-star star-6" />
        </div>
      )}

      {/* 背景に大きく溶け込む固定サイズ画像 */}
      <img
        src={planIconAsset(plan.tier_level)}
        alt=""
        className="plans-card-bg-fixed"
        aria-hidden="true"
      />

      <div className="plans-card-body">
        <div className="plans-card-info">
          <h2 className="plans-card-name">{plan.name}</h2>
          <p className="plans-card-price">
            <span className="plans-card-price-amount">{formatPrice(plan, isJa)}</span>
            {plan.price_usd != null && plan.price_usd > 0 && (
              <span className="plans-card-price-unit">{isJa ? ' / 月' : ' / mo'}</span>
            )}
          </p>
          <div className="plans-card-credits-compact">
            <CreditStarIcon size={12} color="var(--star-gold, #fbc02d)" />
            <span>
              {toDisplayCredits(plan.monthly_credit_amount).toLocaleString()} {isJa ? 'クレジット / 月' : 'credits / mo'}
            </span>
          </div>
        </div>
        <div className="plans-card-action">{action}</div>
      </div>
    </article>
  );
};
