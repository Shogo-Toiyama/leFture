import React, { useState } from 'react';
import { Loader2 } from 'lucide-react';
import { loadStripe, type Appearance } from '@stripe/stripe-js';
import { Elements, PaymentElement, useElements, useStripe } from '@stripe/react-stripe-js';
import { ModalDialog } from './ModalDialog';
import { STRIPE_PUBLISHABLE_KEY } from '../../lib/env';
import { useLanguage } from '../../i18n/LanguageContext';

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

const CheckoutDisclosure: React.FC<{ charge: CheckoutCharge; isJa: boolean }> = ({ charge, isJa }) => {
  const locale = isJa ? 'ja-JP' : 'en-US';
  const today = formatMoney(charge.amountCents, charge.currency, locale);
  const { recurring } = charge;

  if (!recurring) {
    return (
      <p className="stripe-checkout-disclosure">
        {isJa
          ? `本日のご請求額: ${today}（1回限りのお支払いです。自動更新はありません）。`
          : `Today's charge: ${today}. This is a one-time payment and will not renew.`}
      </p>
    );
  }

  const renewal = formatMoney(Math.round(recurring.priceUsd * 100), 'usd', locale);
  const every =
    recurring.intervalMonths === 1
      ? isJa ? '毎月' : 'every month'
      : isJa ? `${recurring.intervalMonths}か月ごと` : `every ${recurring.intervalMonths} months`;
  return (
    <p className="stripe-checkout-disclosure">
      {isJa
        ? `本日のご請求額: ${today}。以降、解約されるまで${every}${renewal}が自動的に請求されます。解約はいつでもPlansページから行え、現在の請求期間の終了時に反映されます。`
        : `Today's charge: ${today}. Your subscription then renews automatically at ${renewal} ${every} until you cancel. You can cancel anytime from the Plans page; cancellation takes effect at the end of the current billing period.`}
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
  const { language } = useLanguage();
  const isJa = language === 'ja';
  const payLabel = `${isJa ? '支払う' : 'Pay'} ${formatMoney(charge.amountCents, charge.currency, isJa ? 'ja-JP' : 'en-US')}`;

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
      setErrorMessage(error.message ?? (isJa ? '決済に失敗しました' : 'Payment failed'));
      setSubmitting(false);
      return;
    }

    if (paymentIntent && (paymentIntent.status === 'succeeded' || paymentIntent.status === 'processing')) {
      // 決済自体は完了。ここから先(反映確認)もsubmitting=trueのまま続け、
      // onSuccess側が実際にプランが切り替わるまで待ってからこのモーダルを閉じる。
      await onSuccess();
      return;
    }

    setErrorMessage(isJa ? '決済が完了しませんでした' : 'Payment did not complete');
    setSubmitting(false);
  };

  return (
    <form className="stripe-checkout-form" onSubmit={handleSubmit}>
      <PaymentElement />
      {errorMessage && <p className="notice notice-error">{errorMessage}</p>}
      <CheckoutDisclosure charge={charge} isJa={isJa} />
      <p className="stripe-checkout-consent">
        {isJa ? (
          <>
            「{payLabel}」を押すことで、
            <a href="https://lefture.com/terms" target="_blank" rel="noopener noreferrer">利用規約</a>
            および
            <a href="https://lefture.com/privacy" target="_blank" rel="noopener noreferrer">プライバシーポリシー</a>
            に同意したものとみなされます。
          </>
        ) : (
          <>
            By clicking "{payLabel}" you agree to the{' '}
            <a href="https://lefture.com/terms" target="_blank" rel="noopener noreferrer">Terms of Service</a> and{' '}
            <a href="https://lefture.com/privacy" target="_blank" rel="noopener noreferrer">Privacy Policy</a>.
          </>
        )}
      </p>
      <div className="stripe-checkout-actions">
        <button type="button" className="keyword-btn-cancel" onClick={onClose} disabled={submitting}>
          {isJa ? 'キャンセル' : 'Cancel'}
        </button>
        <button type="submit" className="auth-submit-btn" disabled={!stripe || submitting}>
          {submitting && <Loader2 size={15} className="animate-spin" />}
          {submitting ? (isJa ? '処理中…' : 'Processing…') : payLabel}
        </button>
      </div>
    </form>
  );
};
