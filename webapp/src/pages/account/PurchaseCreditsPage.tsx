import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { RefreshCw, ExternalLink } from 'lucide-react';
import { CreditStarIcon } from '../../components/icons/CreditStarIcon';
import { useCreditSummary } from '../../hooks/useCreditSummary';
import { useCreditPacks } from '../../hooks/useCreditPacks';
import { createCreditPackPayment } from '../../lib/billing';
import { toDisplayCredits } from '../../types/billing';
import { ApiError } from '../../lib/api';
import { PageState } from '../../components/PageState';
import { AccountSuspendedNotice } from '../../components/AccountSuspendedNotice';
import { StripeCheckoutModal } from '../../components/modals/StripeCheckoutModal';
import { useLanguage } from '../../i18n/LanguageContext';
import { CreditPackIllustration } from '../../components/account/CreditPackIllustration';
import { PurchaseCreditsSkeleton } from '../../components/account/PurchaseCreditsSkeleton';

/** webhookの反映を待つための短時間リトライ。 */
async function waitAndRefetch(refetch: () => Promise<void>) {
  for (let i = 0; i < 4; i++) {
    await new Promise((resolve) => setTimeout(resolve, 3000));
    await refetch();
  }
}

export const PurchaseCreditsPage: React.FC = () => {
  const { summary, loading: summaryLoading, refetch } = useCreditSummary(false);
  const { packs, loading, error } = useCreditPacks();
  const { t, formatNumber } = useLanguage();

  const [startingCheckoutId, setStartingCheckoutId] = useState<string | null>(null);
  const [checkoutError, setCheckoutError] = useState<string | null>(null);
  const [pendingCheckout, setPendingCheckout] = useState<{
    title: string;
    clientSecret: string;
    amountCents: number;
    currency: string;
    creditAmount: number;
  } | null>(null);

  const totalBalance = summary ? toDisplayCredits(summary.credit_balance) : 0;

  const handleBuyPack = async (packId: string, packName: string, creditAmount: number) => {
    setStartingCheckoutId(packId);
    setCheckoutError(null);
    try {
      const { client_secret, amount_cents, currency } = await createCreditPackPayment(packId);
      setPendingCheckout({
        title: packName,
        clientSecret: client_secret,
        amountCents: amount_cents,
        currency,
        creditAmount,
      });
    } catch (err) {
      setCheckoutError(err instanceof ApiError ? err.message : t('purchaseCreditsFailed'));
    } finally {
      setStartingCheckoutId(null);
    }
  };

  const handleCheckoutSuccess = async () => {
    setPendingCheckout(null);
    await waitAndRefetch(refetch);
  };

  // クレジット量順にソート
  const sortedPacks = [...packs]
    .filter((pack) => pack.stripe_price_id)
    .sort((a, b) => a.credit_amount - b.credit_amount);

  return (
    <div className="purchase-credits-page">
      {/* 上部コズミックパープルグラデーション (Courseページ準拠) */}
      <div className="purchase-credits-top-gradient" aria-hidden="true" />

      <div className="purchase-credits-inner">
        {/* ── ヘッダー ── */}
        <div className="purchase-credits-head">
          <Link to="/account/credits" className="back-link">
            ← {t('creditsTitle')}
          </Link>
        </div>

        {summary?.suspended && <AccountSuspendedNotice />}

        <div className="purchase-credits-title-row">
          <div>
            <h1 className="purchase-credits-title">{t('purchaseCreditsTitle')}</h1>
            <p className="purchase-credits-subtitle">
              {t('purchaseCreditsSubtitle')}
            </p>
          </div>

          {/* 現在のクレジット残高バッジ */}
          <div className="purchase-credits-badge">
            <span className="purchase-credits-badge-label">
              {t('currentCreditsBalance')}
            </span>
            <div className="purchase-credits-badge-val">
              <CreditStarIcon size={15} color="var(--star-gold, #fbc02d)" />
              <span>
                {summaryLoading ? '…' : `${formatNumber(totalBalance)} ${t('credits')}`}
              </span>
            </div>
          </div>
        </div>

        {checkoutError && <p className="notice notice-error">{checkoutError}</p>}

        {/* ── メイン: 横幅いっぱいに広がるカードグリッド ── */}
        {loading && <PurchaseCreditsSkeleton />}
        {error && <PageState kind="error" message={error} />}

        {!loading && !error && sortedPacks.length === 0 && (
          <div className="purchase-credits-empty">
            <p className="muted">
              {t('noCreditPacksAvailable')}
            </p>
          </div>
        )}

        {!loading && !error && sortedPacks.length > 0 && (
          <div className="purchase-credits-grid">
            {sortedPacks.map((pack) => {
              const displayCredit = toDisplayCredits(pack.credit_amount);
              const isProcessing = startingCheckoutId === pack.id;
              const priceLabel = pack.price_usd != null ? `$${pack.price_usd}` : '—';

              return (
                <div key={pack.id} className="purchase-credit-card">
                  {/* 1. イラスト領域 */}
                  <div className="purchase-credit-card-illustration">
                    <CreditPackIllustration creditAmount={displayCredit} />
                  </div>

                  {/* 2. クレジット量ラベル(数字+単位を縦積みにして、幅が狭くても
                       「クレジット」等の単位ラベルが不格好に折り返さないようにする) */}
                  <div className="purchase-credit-card-amount">
                    <div className="purchase-credit-amount-row">
                      <CreditStarIcon size={18} color="#c084fc" className="purchase-credit-amount-star" />
                      <span className="purchase-credit-amount-num">{displayCredit}</span>
                    </div>
                    <span className="purchase-credit-amount-unit">{t('credits')}</span>
                  </div>

                  {/* 3. 購入ボタン（価格表示） */}
                  <button
                    type="button"
                    className="purchase-credit-card-btn"
                    onClick={() => handleBuyPack(pack.id, pack.name, displayCredit)}
                    disabled={isProcessing || startingCheckoutId !== null || Boolean(summary?.suspended)}
                  >
                    {isProcessing ? (
                      <span className="purchase-btn-loading">
                        <RefreshCw size={14} className="animate-spin" />
                        {t('purchaseCreditsStarting')}
                      </span>
                    ) : (
                      priceLabel
                    )}
                  </button>
                </div>
              );
            })}
          </div>
        )}

        {/* ── 下部説明 & リンク ── */}
        <div className="purchase-credits-footer">
          <p className="purchase-credits-disclosure">
            {t('purchaseCreditsDisclosure')}
          </p>

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
      </div>

      {pendingCheckout && (
        <StripeCheckoutModal
          title={pendingCheckout.title}
          creditAmount={pendingCheckout.creditAmount}
          clientSecret={pendingCheckout.clientSecret}
          clientSecretKind="payment"
          charge={{ amountCents: pendingCheckout.amountCents, currency: pendingCheckout.currency, recurring: null }}
          onClose={() => setPendingCheckout(null)}
          onSuccess={handleCheckoutSuccess}
        />
      )}
    </div>
  );
};

