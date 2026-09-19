import React, { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { WifiOff, ChevronDown, Plus, Zap } from 'lucide-react';
import { useCreditSummary } from '../../hooks/useCreditSummary';
import { useCreditHistory } from '../../hooks/useCreditHistory';
import { usePlans } from '../../hooks/usePlans';
import { toDisplayCredits } from '../../types/billing';
import type { CreditHistoryItem, CreditSummary, PlanOption } from '../../types/billing';
import { useLanguage } from '../../i18n/LanguageContext';
import { CreditsPageSkeleton } from '../../components/account/CreditsPageSkeleton';
import { CreditsHistorySkeleton } from '../../components/account/CreditsHistorySkeleton';
import { tierAccent, planIconAsset } from '../../lib/planTheme';
import { CreditRateTableDialog } from '../../components/CreditRateTableDialog';

const HISTORY_PAGE_SIZE = 10;

/**
 * クレジット詳細ページ。credit_detail_page.dart 準拠:
 * 月間クレジット(残量+進捗バー) → 現在のプラン → 利用履歴、の3セクションのみ。
 * プランの一覧・変更や追加クレジットの購入は別ページ(/account/plans,
 * /account/credits/purchase)に切り出してあるので、ここには置かない。
 */
export const CreditsPage: React.FC = () => {
  const { summary, loading, error, refetch: refetchSummary } = useCreditSummary(true);
  const { history, loading: historyLoading, error: historyError, refetch: refetchHistory } = useCreditHistory();
  const { plans } = usePlans();
  const { language } = useLanguage();
  const isJa = language === 'ja';

  const [historyExpanded, setHistoryExpanded] = useState(false);
  const [creditRateOpen, setCreditRateOpen] = useState(false);

  const handleRetry = () => {
    void Promise.allSettled([refetchSummary(), refetchHistory()]);
  };

  if (loading) {
    return <CreditsPageSkeleton />;
  }

  if (error || !summary) {
    return (
      <div className="account-page">
        <div className="credits-error">
          <WifiOff size={36} />
          <p className="muted">
            {isJa
              ? 'クレジット情報を読み込めませんでした。接続を確認してもう一度お試しください。'
              : 'Could not load credit info. Check your connection and try again.'}
          </p>
          <button type="button" className="ghost" onClick={handleRetry}>
            {isJa ? '再試行' : 'Retry'}
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="account-page credits-page">
      <div className="credits-page-head">
        <Link to="/account" className="back-link">
          ← {isJa ? 'アカウント' : 'Account'}
        </Link>
      </div>
      <h1>{isJa ? 'クレジット' : 'Credits'}</h1>

      <MonthlyCreditCard summary={summary} isJa={isJa} />

      {summary.has_active_plan && (
        <CurrentPlanCard
          summary={summary}
          plans={plans}
          isJa={isJa}
          onCreditRateClick={() => setCreditRateOpen(true)}
        />
      )}

      <HistoryCard
        items={history}
        loading={historyLoading}
        error={historyError}
        expanded={historyExpanded}
        onExpand={() => setHistoryExpanded(true)}
        isJa={isJa}
      />

      {creditRateOpen && <CreditRateTableDialog onClose={() => setCreditRateOpen(false)} />}
    </div>
  );
};

// ─────────────────────────────────────────────────────────────────────────
// 月間クレジット
// ─────────────────────────────────────────────────────────────────────────

const MonthlyCreditCard: React.FC<{ summary: CreditSummary; isJa: boolean }> = ({ summary, isJa }) => {
  if (!summary.has_active_plan) return <NoActivePlanCard isJa={isJa} />;

  const totalBalance = toDisplayCredits(summary.credit_balance);
  const monthlyAllocation = toDisplayCredits(summary.monthly_allocation);
  const extraBalance = toDisplayCredits(summary.extra_credit_balance);

  // 月間クレジット残量: オーバードラフト時はマイナス値をそのまま反映、
  // それ以外は0〜月間枠に収める(_MonthlyCreditCard 準拠)。
  const monthlyBalance =
    totalBalance < 0 ? totalBalance : Math.max(0, Math.min(monthlyAllocation, totalBalance - extraBalance));
  const maxCapacity = Math.max(monthlyAllocation, totalBalance);
  const isDepleted = totalBalance <= 0;

  const monthlyFraction = isDepleted ? 0.03 : maxCapacity <= 0 ? 0 : Math.max(0, Math.min(1, monthlyBalance / maxCapacity));
  const totalFraction = isDepleted ? 0.03 : maxCapacity <= 0 ? 0 : Math.max(0, Math.min(1, totalBalance / maxCapacity));

  return (
    <section className="glass-card credits-card">
      <div className="credits-card-head">
        <span className="credits-card-title">{isJa ? '月間クレジット' : 'Monthly Credits'}</span>
        <span className="credits-balance-value">
          <span className={isDepleted ? 'is-depleted' : 'is-gold'}>{monthlyBalance}</span>
          <span className="credits-balance-denom"> / {monthlyAllocation}</span>
          {extraBalance > 0 && (
            <>
              <span className="credits-balance-denom"> + </span>
              <span className="is-extra">{extraBalance}</span>
            </>
          )}
        </span>
      </div>

      <div className="credits-dual-track">
        {isDepleted ? (
          <div className="credits-bar-depleted" />
        ) : (
          <>
            {totalFraction > 0 && <div className="credits-bar-extra" style={{ width: `${totalFraction * 100}%` }} />}
            {monthlyFraction > 0 && <div className="credits-bar-monthly" style={{ width: `${monthlyFraction * 100}%` }} />}
          </>
        )}
      </div>

      <div className="credits-card-foot">
        {summary.current_period_end ? (
          <span className="muted">
            {isJa
              ? `${new Date(summary.current_period_end).toLocaleDateString()}にリセット`
              : `Resets on ${new Date(summary.current_period_end).toLocaleDateString()}`}
          </span>
        ) : (
          <span />
        )}
        <Link to="/account/credits/purchase" className="credits-buy-link">
          {isJa ? 'クレジットを購入 ＞' : 'Buy Credits ＞'}
        </Link>
      </div>
    </section>
  );
};

const NoActivePlanCard: React.FC<{ isJa: boolean }> = ({ isJa }) => (
  <Link to="/account/plans" className="credits-noplan-card">
    <img src="/img/plan_icons/stardust.webp" alt="" className="credits-noplan-img" aria-hidden="true" />
    <span className="credits-noplan-title">{isJa ? '有効なプランがありません' : 'No active plan'}</span>
    <span className="credits-noplan-subtitle">
      {isJa ? 'プランを選んで、講義資料の生成を始めましょう。' : 'Choose a plan to start generating lecture materials.'}
    </span>
    <span className="credits-noplan-button">{isJa ? 'プランを見る' : 'View Plans'}</span>
  </Link>
);

// ─────────────────────────────────────────────────────────────────────────
// 現在のプラン
// ─────────────────────────────────────────────────────────────────────────

const CurrentPlanCard: React.FC<{
  summary: CreditSummary;
  plans: PlanOption[];
  isJa: boolean;
  onCreditRateClick: () => void;
}> = ({ summary, plans, isJa, onCreditRateClick }) => {
  // /billing/plans はstore_purchaseプランも含むため、単純な先頭要素ではなく
  // summaryが返す現在のplan_idで引く。
  const activePlan = useMemo(
    () => plans.find((p) => p.id === summary.plan_id),
    [plans, summary.plan_id]
  );

  if (!activePlan) {
    return <div className="glass-card credits-card credits-card-skeleton" aria-hidden="true" />;
  }

  const { accent, isPremium, isStandard } = tierAccent(activePlan.tier_level);
  const creditsCount = toDisplayCredits(summary.monthly_allocation ?? activePlan.monthly_credit_amount);

  const pendingPlan = plans.find((p) => p.id === summary.pending_plan_id);
  const pendingPlanNote =
    pendingPlan && summary.current_period_end
      ? isJa
        ? `${new Date(summary.current_period_end).toLocaleDateString()}に${pendingPlan.name}へ切り替わります`
        : `Switching to ${pendingPlan.name} on ${new Date(summary.current_period_end).toLocaleDateString()}`
      : null;

  return (
    <section
      className={`credits-plan-card ${isPremium ? 'is-premium' : isStandard ? 'is-standard' : ''}`}
      style={{ ['--plan-accent' as string]: accent }}
    >
      <img src={planIconAsset(activePlan.tier_level)} alt="" className="credits-plan-img" aria-hidden="true" />
      <div className="credits-plan-head">
        <span className="credits-plan-label">{isJa ? '現在のプラン' : 'Current Plan'}</span>
        <span className="credits-plan-badge">{isJa ? '有効' : 'ACTIVE'}</span>
      </div>
      <h2 className="credits-plan-name">{activePlan.name}</h2>
      <button type="button" className="credits-plan-credits" onClick={onCreditRateClick}>
        {isJa ? `${creditsCount}クレジット / 月` : `${creditsCount} credits / month`}
      </button>
      {summary.current_period_end && (
        <p className="credits-plan-reset">
          {isJa
            ? `${new Date(summary.current_period_end).toLocaleDateString()}にリセット`
            : `Resets on ${new Date(summary.current_period_end).toLocaleDateString()}`}
        </p>
      )}
      {pendingPlanNote && <p className="credits-plan-pending">{pendingPlanNote}</p>}
      <Link to="/account/plans" className="credits-plan-button">
        {isJa ? 'プランを見る・変更する' : 'View & Change Plans'}
      </Link>
    </section>
  );
};

// ─────────────────────────────────────────────────────────────────────────
// 利用履歴
// ─────────────────────────────────────────────────────────────────────────

const HistoryCard: React.FC<{
  items: CreditHistoryItem[];
  loading: boolean;
  error: string | null;
  expanded: boolean;
  onExpand: () => void;
  isJa: boolean;
}> = ({ items, loading, error, expanded, onExpand, isJa }) => {
  const displayItems = expanded ? items : items.slice(0, HISTORY_PAGE_SIZE);
  const hasMore = items.length > HISTORY_PAGE_SIZE;

  return (
    <section className="glass-card credits-card">
      <div className="credits-card-head">
        <span className="credits-card-title">{isJa ? '利用履歴' : 'Usage History'}</span>
        <span className="muted">{isJa ? '1時間ごとの集計' : 'Hourly summary'}</span>
      </div>

      {loading && <CreditsHistorySkeleton />}

      {!loading && error && <p className="muted">{isJa ? '利用履歴を読み込めませんでした。' : 'Could not load usage history.'}</p>}

      {!loading && !error && items.length === 0 && (
        <p className="muted">{isJa ? '最近の利用履歴はありません。' : 'No recent usage activity recorded.'}</p>
      )}

      {!loading && !error && items.length > 0 && (
        <ul className="credits-history-list">
          {displayItems.map((item) => (
            <li key={item.id}>
              <HistoryRow item={item} isJa={isJa} />
            </li>
          ))}
        </ul>
      )}

      {!loading && !error && hasMore && !expanded && (
        <button type="button" className="credits-history-more" onClick={onExpand}>
          <ChevronDown size={16} />
          {isJa ? `もっと見る（残り${items.length - HISTORY_PAGE_SIZE}件）` : `View More (${items.length - HISTORY_PAGE_SIZE} more)`}
        </button>
      )}
    </section>
  );
};

const HistoryRow: React.FC<{ item: CreditHistoryItem; isJa: boolean }> = ({ item, isJa }) => {
  if (item.kind === 'reset') {
    // 具体的な数字を出すと「クレジットを失った」という誤解を招くため、
    // 数字を持たない区切りラベルとして描く(_HistoryTile 準拠。plan_changed以外は
    // すべてRenewed扱いになるのはFlutter側と同じ仕様)。
    const label =
      item.reset_reason === 'plan_changed'
        ? isJa
          ? 'プランが変更されました'
          : 'Plan Changed'
        : isJa
          ? '更新されました'
          : 'Renewed';
    return (
      <div className="credits-history-reset">
        <span className="credits-history-reset-line" />
        <span className="credits-history-reset-label">{label}</span>
        <span className="credits-history-reset-line" />
      </div>
    );
  }

  const isPositive = Boolean(item.is_positive);
  return (
    <div className="credits-history-row">
      <span className={`credits-history-icon ${isPositive ? 'is-positive' : ''}`} aria-hidden="true">
        {isPositive ? <Plus size={16} /> : <Zap size={16} />}
      </span>
      <span className="credits-history-text">
        <span className="credits-history-time">{item.time_label}</span>
        <span className="credits-history-date muted">{item.date_label}</span>
      </span>
      <span className={`credits-history-delta ${isPositive ? 'is-positive' : ''}`}>
        {isJa ? `${item.formatted_delta} クレジット` : `${item.formatted_delta} credits`}
      </span>
    </div>
  );
};
