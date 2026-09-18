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
  const { language } = useLanguage();
  const isJa = language === 'ja';

  const [startingCheckoutId, setStartingCheckoutId] = useState<string | null>(null);
  const [checkoutError, setCheckoutError] = useState<string | null>(null);
  const [pendingCheckout, setPendingCheckout] = useState<{ title: string; clientSecret: string } | null>(null);

  const totalBalance = summary ? toDisplayCredits(summary.credit_balance) : 0;

  const handleBuyPack = async (packId: string, packName: string) => {
    setStartingCheckoutId(packId);
    setCheckoutError(null);
    try {
      const { client_secret } = await createCreditPackPayment(packId);
      setPendingCheckout({ title: packName, clientSecret: client_secret });
    } catch (err) {
      setCheckoutError(err instanceof ApiError ? err.message : isJa ? '購入開始に失敗しました' : 'Failed to start purchase');
    } finally {
      setStartingCheckoutId(null);
    }
  };

  const handleCheckoutSuccess = () => {
    setPendingCheckout(null);
    void waitAndRefetch(refetch);
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
            ← {isJa ? 'クレジット' : 'Credits'}
          </Link>
        </div>

        <div className="purchase-credits-title-row">
          <div>
            <h1 className="purchase-credits-title">{isJa ? 'クレジットを購入' : 'Buy Credits'}</h1>
            <p className="purchase-credits-subtitle">
              {isJa
                ? '有効期限なし・必要なときにいつでも使える追加クレジットです。'
                : 'Non-expiring additional credits for generating notes, cards, and more.'}
            </p>
          </div>

          {/* 現在のクレジット残高バッジ */}
          <div className="purchase-credits-badge">
            <span className="purchase-credits-badge-label">
              {isJa ? '現在のクレジット残高' : 'Current Credits'}
            </span>
            <div className="purchase-credits-badge-val">
              <CreditStarIcon size={15} color="var(--star-gold, #fbc02d)" />
              <span>
                {summaryLoading ? (isJa ? '…' : '…') : `${totalBalance.toLocaleString()} ${isJa ? 'クレジット' : 'credits'}`}
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
              {isJa ? '現在購入可能なクレジットパックはありません。' : 'No credit packs currently available.'}
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

                  {/* 2. クレジット量ラベル */}
                  <div className="purchase-credit-card-amount">
                    <CreditStarIcon size={18} color="#c084fc" className="purchase-credit-amount-star" />
                    <span className="purchase-credit-amount-num">{displayCredit}</span>
                    <span className="purchase-credit-amount-unit">{isJa ? 'クレジット' : 'credits'}</span>
                  </div>

                  {/* 3. 購入ボタン（価格表示） */}
                  <button
                    type="button"
                    className="purchase-credit-card-btn"
                    onClick={() => handleBuyPack(pack.id, pack.name)}
                    disabled={isProcessing || startingCheckoutId !== null}
                  >
                    {isProcessing ? (
                      <span className="purchase-btn-loading">
                        <RefreshCw size={14} className="animate-spin" />
                        {isJa ? '準備中…' : 'Starting…'}
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
            {isJa
              ? '購入した追加クレジットは有効期限がなく、月間クレジットが不足した際に自動的に消費されます。'
              : 'Purchased additional credits never expire and are automatically consumed when monthly credits are depleted.'}
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
          title={pendingCheckout.title}
          clientSecret={pendingCheckout.clientSecret}
          onClose={() => setPendingCheckout(null)}
          onSuccess={handleCheckoutSuccess}
        />
      )}
    </div>
  );
};

