import React, { useState } from 'react';
import { Loader2 } from 'lucide-react';
import { loadStripe, type Appearance } from '@stripe/stripe-js';
import { Elements, PaymentElement, useElements, useStripe } from '@stripe/react-stripe-js';
import { ModalDialog } from './ModalDialog';
import { STRIPE_PUBLISHABLE_KEY } from '../../lib/env';
import { useLanguage } from '../../i18n/LanguageContext';
import type { TranslationKey } from '../../i18n/translations';

// loadStripeはPromiseをキャッシュする設計なので、レンダーごとに再生成せず
// モジュールスコープで一度だけ呼ぶ(Stripe公式推奨パターン)。
const stripePromise = loadStripe(STRIPE_PUBLISHABLE_KEY);

const APPEARANCE: Appearance = {
  theme: 'night',
  variables: {
    colorPrimary: '#FFB300',
    colorBackground: '#171b2b',
    colorText: '#f2f2f2',
    colorDanger: '#e53935',
    borderRadius: '10px',
  },
};

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
  /**
   * 決済自体はここで完了するが、DB側のプラン反映はStripe→webhook→RevenueCat→
   * webhookという経路を経るため数秒遅れる。onSuccessはその反映確認まで待つ
   * (Promiseが解決するまで)実装を渡すこと。待っている間もこのモーダルを開いた
   * まま「処理中」表示を続ける(反映前にモーダルが消えて宙ぶらりんにしない)。
   */
  onSuccess: () => Promise<void>;
}

export const StripeCheckoutModal: React.FC<StripeCheckoutModalProps> = ({
  title,
  clientSecret,
  charge,
  onClose,
  onSuccess,
}) => {
  return (
    <ModalDialog title={title} onClose={onClose} maxWidth={480}>
      <Elements stripe={stripePromise} options={{ clientSecret, appearance: APPEARANCE }}>
        <CheckoutForm charge={charge} onClose={onClose} onSuccess={onSuccess} />
      </Elements>
    </ModalDialog>
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

type Translate = (key: TranslationKey, params?: Record<string, string>) => string;

function buildPayLabel(charge: CheckoutCharge, language: string, t: Translate): string {
  const amount = formatMoney(charge.amountCents, charge.currency, language);
  return t('stripeCheckoutPayButton', { amount });
}

const CheckoutDisclosure: React.FC<{ charge: CheckoutCharge; language: string; t: Translate }> = ({
  charge,
  language,
  t,
}) => {
  const amount = formatMoney(charge.amountCents, charge.currency, language);
  const { recurring } = charge;

  if (!recurring) {
    return <p className="stripe-checkout-disclosure">{t('stripeCheckoutDisclosureOneTime', { amount })}</p>;
  }

  const renewal = formatMoney(Math.round(recurring.priceUsd * 100), 'usd', language);
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
  const { language, t } = useLanguage();
  const payLabel = buildPayLabel(charge, language, t);

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
      <CheckoutDisclosure charge={charge} language={language} t={t} />
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
        <button type="button" className="keyword-btn-cancel" onClick={onClose} disabled={submitting}>
          {t('stripeCheckoutCancelButton')}
        </button>
        <button type="submit" className="auth-submit-btn" disabled={!stripe || submitting}>
          {submitting && <Loader2 size={15} className="animate-spin" />}
          {submitting ? t('stripeCheckoutPayButtonProcessing') : payLabel}
        </button>
      </div>
    </form>
  );
};
