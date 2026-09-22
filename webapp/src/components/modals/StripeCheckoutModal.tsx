import React, { useEffect, useState } from 'react';
import { Loader2, X } from 'lucide-react';
import { loadStripe, type Appearance } from '@stripe/stripe-js';
import { Elements, PaymentElement, useElements, useStripe } from '@stripe/react-stripe-js';
import { STRIPE_PUBLISHABLE_KEY } from '../../lib/env';
import { useLanguage, type Translate } from '../../i18n/LanguageContext';
import { planIconAsset } from '../../lib/planTheme';
import { CreditPackIllustration } from '../account/CreditPackIllustration';

// loadStripeはPromiseをキャッシュする設計なので、レンダーごとに再生成せず
// モジュールスコープで一度だけ呼ぶ(Stripe公式推奨パターン)。
const stripePromise = loadStripe(STRIPE_PUBLISHABLE_KEY);

/**
 * 「今日いくら請求され、その後どうなるか」の開示に必要な情報。
 * カリフォルニア州自動更新法(ARL)/連邦ROSCAは、自動更新の条件・解約方法・
 * 金額を「同意ボタンの視覚的近傍に」明示することを求めるため、Plansページの
 * フッターではなくこのモーダル内の支払いボタン直上に出す。
 * amountCentsはStripeが実際に請求する額(Apple乗り換え割引等の適用後)。
 */
export interface CheckoutCharge {
  amountCents: number;
  currency: string;
  /** 自動更新サブスクなら定価と周期。クレジットパック(都度)ならnull。 */
  recurring: { priceUsd: number; intervalMonths: number } | null;
}

export interface StripeCheckoutModalProps {
  title: string;
  clientSecret: string;
  charge: CheckoutCharge;
  onClose: () => void;
  tierLevel?: number;
  creditAmount?: number;
  /**
   * 決済自体はここで完了するが、DB側のプラン反映はStripe→webhook→RevenueCat→
   * webhookという経路を経るため数秒遅れる。onSuccessはその反映確認まで待つ
   * (Promiseが解決するまで)実装を渡すこと。待っている間もこのモーダルを開いた
   * まま「処理中」表示を続ける(反映前にモーダルが消えて宙ぶらりんにしない)。
   */
  onSuccess: () => Promise<void>;
}

type CheckoutTheme = 'red' | 'blue' | 'purple' | 'gold';

export const StripeCheckoutModal: React.FC<StripeCheckoutModalProps> = ({
  title,
  clientSecret,
  charge,
  onClose,
  tierLevel,
  creditAmount,
  onSuccess,
}) => {
  const { t, locale, language } = useLanguage();

  const checkoutTheme: CheckoutTheme = React.useMemo(() => {
    if (creditAmount !== undefined) return 'purple';
    if (tierLevel === 2) return 'red';
    if (tierLevel === 1) return 'blue';
    if (tierLevel !== undefined && tierLevel >= 3) return 'purple';
    return 'gold';
  }, [creditAmount, tierLevel]);

  const appearance: Appearance = React.useMemo(() => {
    const primaryColorMap: Record<CheckoutTheme, string> = {
      red: '#FB7185',
      blue: '#38BDF8',
      purple: '#C084FC',
      gold: '#FFB300',
    };
    return {
      theme: 'night',
      variables: {
        colorPrimary: primaryColorMap[checkoutTheme],
        colorBackground: '#171b2b',
        colorText: '#f2f2f2',
        colorDanger: '#e53935',
        borderRadius: '12px',
      },
    };
  }, [checkoutTheme]);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose]);

  const formattedAmount = formatMoney(charge.amountCents, charge.currency, locale);

  return (
    <div className="lecture-modal-backdrop stripe-checkout-backdrop" onClick={onClose}>
      <div
        className={`stripe-checkout-modal-card theme-${checkoutTheme}`}
        onClick={(e) => e.stopPropagation()}
      >
        {/* ── ヒーローヘッダー ── */}
        <div className="stripe-checkout-hero">
          <div className="stripe-checkout-hero-aurora" aria-hidden="true" />
          <div className="stripe-checkout-hero-glow" aria-hidden="true" />

          {/* 背景にうっすら浮かび上がるプラン画像 / クレジットベクター */}
          {tierLevel !== undefined && (
            <img
              src={planIconAsset(tierLevel)}
              alt=""
              className="stripe-checkout-hero-bg-art"
              aria-hidden="true"
            />
          )}
          {creditAmount !== undefined && (
            <div className="stripe-checkout-hero-bg-art is-vector" aria-hidden="true">
              <CreditPackIllustration creditAmount={creditAmount} size={150} />
            </div>
          )}

          <button
            type="button"
            className="stripe-checkout-hero-close"
            onClick={onClose}
            aria-label="Close"
          >
            <X size={18} />
          </button>

          <h2 className="stripe-checkout-hero-title">{title}</h2>

          <div className="stripe-checkout-hero-price-row">
            <span className="stripe-checkout-hero-price">{formattedAmount}</span>
            {charge.recurring && (
              <span className="stripe-checkout-hero-interval">
                {charge.recurring.intervalMonths === 1
                  ? t('stripeCheckoutHeroMonth')
                  : t('stripeCheckoutHeroNMonths', { n: String(charge.recurring.intervalMonths) })}
              </span>
            )}
          </div>
        </div>

        {/* ── フォームコンテンツ ── */}
        <div className="stripe-checkout-body">
          <Elements stripe={stripePromise} options={{ clientSecret, appearance, locale: language }}>
            <CheckoutForm charge={charge} onClose={onClose} onSuccess={onSuccess} />
          </Elements>
        </div>
      </div>
    </div>
  );
};

function formatMoney(amountCents: number, currency: string, locale: string): string {
  return new Intl.NumberFormat(locale, { style: 'currency', currency: currency.toUpperCase() }).format(amountCents / 100);
}

/**
 * "{key}"トークンを含むテンプレート文字列を、対応するReactノードで置き換える。
 * 語順は言語辞書側(translations.ts)のテンプレート文字列だけが決める — ここでは
 * トークンの位置を探して差し込むだけなので、新しい言語を追加しても、その言語の
 * 辞書内でトークンの順序を自由に入れ替えられれば正しく動く。
 */
function interpolate(template: string, values: Record<string, React.ReactNode>): React.ReactNode {
  const tokenPattern = /\{([a-zA-Z]+)\}/g;
  const parts: React.ReactNode[] = [];
  let lastIndex = 0;
  let match: RegExpExecArray | null;
  while ((match = tokenPattern.exec(template)) !== null) {
    if (match.index > lastIndex) parts.push(template.slice(lastIndex, match.index));
    const value = values[match[1]];
    parts.push(value !== undefined ? <React.Fragment key={match.index}>{value}</React.Fragment> : match[0]);
    lastIndex = tokenPattern.lastIndex;
  }
  if (lastIndex < template.length) parts.push(template.slice(lastIndex));
  return parts;
}

function buildPayLabel(charge: CheckoutCharge, locale: string, t: Translate): string {
  const amount = formatMoney(charge.amountCents, charge.currency, locale);
  return t('stripeCheckoutPayButton', { amount });
}

const CheckoutDisclosure: React.FC<{ charge: CheckoutCharge; locale: string; t: Translate }> = ({
  charge,
  locale,
  t,
}) => {
  const amount = formatMoney(charge.amountCents, charge.currency, locale);
  const { recurring } = charge;

  if (!recurring) {
    return <p className="stripe-checkout-disclosure">{t('stripeCheckoutDisclosureOneTime', { amount })}</p>;
  }

  const renewal = formatMoney(Math.round(recurring.priceUsd * 100), 'usd', locale);
  const interval =
    recurring.intervalMonths === 1
      ? t('stripeCheckoutEveryMonth')
      : t('stripeCheckoutEveryNMonths', { n: String(recurring.intervalMonths) });
  return (
    <p className="stripe-checkout-disclosure">
      {t('stripeCheckoutDisclosureRecurring', { amount, renewal, interval })}
    </p>
  );
};

const CheckoutForm: React.FC<{ charge: CheckoutCharge; onClose: () => void; onSuccess: () => Promise<void> }> = ({
  charge,
  onClose,
  onSuccess,
}) => {
  const stripe = useStripe();
  const elements = useElements();
  const { locale, t } = useLanguage();
  const payLabel = buildPayLabel(charge, locale, t);

  const [submitting, setSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!stripe || !elements) return;

    setSubmitting(true);
    setErrorMessage(null);

    const { error, paymentIntent } = await stripe.confirmPayment({
      elements,
      redirect: 'if_required',
      confirmParams: { return_url: window.location.href },
    });

    if (error) {
      setErrorMessage(error.message ?? t('stripeCheckoutPaymentFailed'));
      setSubmitting(false);
      return;
    }

    if (paymentIntent && (paymentIntent.status === 'succeeded' || paymentIntent.status === 'processing')) {
      // 決済自体は完了。ここから先(反映確認)もsubmitting=trueのまま続け、
      // onSuccess側が実際にプランが切り替わるまで待ってからこのモーダルを閉じる。
      await onSuccess();
      return;
    }

    setErrorMessage(t('stripeCheckoutPaymentIncomplete'));
    setSubmitting(false);
  };

  return (
    <form className="stripe-checkout-form" onSubmit={handleSubmit}>
      <PaymentElement />
      {errorMessage && <p className="notice notice-error">{errorMessage}</p>}
      <CheckoutDisclosure charge={charge} locale={locale} t={t} />
      <p className="stripe-checkout-consent">
        {interpolate(t('stripeCheckoutConsent', { payLabel }), {
          terms: (
            <a href="https://lefture.com/terms" target="_blank" rel="noopener noreferrer">
              {t('stripeCheckoutTermsLink')}
            </a>
          ),
          privacy: (
            <a href="https://lefture.com/privacy" target="_blank" rel="noopener noreferrer">
              {t('stripeCheckoutPrivacyLink')}
            </a>
          ),
        })}
      </p>
      <div className="stripe-checkout-actions">
        <button type="button" className="stripe-checkout-btn-cancel" onClick={onClose} disabled={submitting}>
          {t('stripeCheckoutCancelButton')}
        </button>
        <button type="submit" className="stripe-checkout-btn-pay" disabled={!stripe || submitting}>
          {submitting ? (
            <>
              <Loader2 size={16} className="animate-spin" />
              <span>{t('stripeCheckoutPayButtonProcessing')}</span>
            </>
          ) : (
            <span>{payLabel}</span>
          )}
        </button>
      </div>
    </form>
  );
};
