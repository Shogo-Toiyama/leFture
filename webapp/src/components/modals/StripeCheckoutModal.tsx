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

export interface StripeCheckoutModalProps {
  title: string;
  clientSecret: string;
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
  onClose,
  onSuccess,
}) => {
  return (
    <ModalDialog title={title} onClose={onClose} maxWidth={480}>
      <Elements stripe={stripePromise} options={{ clientSecret, appearance: APPEARANCE }}>
        <CheckoutForm onClose={onClose} onSuccess={onSuccess} />
      </Elements>
    </ModalDialog>
  );
};

const CheckoutForm: React.FC<{ onClose: () => void; onSuccess: () => Promise<void> }> = ({ onClose, onSuccess }) => {
  const stripe = useStripe();
  const elements = useElements();
  const { language } = useLanguage();
  const isJa = language === 'ja';

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
      <div className="stripe-checkout-actions">
        <button type="button" className="keyword-btn-cancel" onClick={onClose} disabled={submitting}>
          {isJa ? 'キャンセル' : 'Cancel'}
        </button>
        <button type="submit" className="auth-submit-btn" disabled={!stripe || submitting}>
          {submitting && <Loader2 size={15} className="animate-spin" />}
          {submitting ? (isJa ? '処理中…' : 'Processing…') : isJa ? '支払う' : 'Pay'}
        </button>
      </div>
    </form>
  );
};
