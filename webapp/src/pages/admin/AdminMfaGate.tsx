import React, { useEffect, useRef, useState } from 'react';
import { ShieldCheck } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { ErrorLine, Loading } from './adminUi';

type Stage =
  | { kind: 'loading' }
  | { kind: 'challenge'; factorId: string }
  | { kind: 'enroll'; factorId: string; qrCode: string; secret: string };

/**
 * /admin/* はMFA(TOTP)を通したセッション(aal2)でしか通らない。
 * 既存の検証済みfactorがあればコード入力、無ければ登録(QR)から。
 * 成功するとSupabaseがセッションをaal2に差し替えるので、onVerifiedで再判定する。
 */
export const AdminMfaGate: React.FC<{ stale: boolean; onVerified: () => void }> = ({ stale, onVerified }) => {
  const [stage, setStage] = useState<Stage>({ kind: 'loading' });
  const [code, setCode] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // enrollは副作用があり、並行に2回走ると同名factorの衝突(422)になる。
  // StrictModeの二重実行でも1回だけ走らせる(refはremountを跨いで残る)。
  const started = useRef(false);
  useEffect(() => {
    if (started.current) return;
    started.current = true;
    (async () => {
      const { data, error: listErr } = await supabase.auth.mfa.listFactors();
      if (listErr) throw listErr;
      const verified = data.totp.find((f) => f.status === 'verified');
      if (verified) {
        setStage({ kind: 'challenge', factorId: verified.id });
        return;
      }
      // 途中で放棄された未検証factorが残っていると再登録が弾かれるので掃除する
      for (const f of data.all.filter((f) => f.factor_type === 'totp' && f.status !== 'verified')) {
        await supabase.auth.mfa.unenroll({ factorId: f.id });
      }
      const { data: enrolled, error: enrollErr } = await supabase.auth.mfa.enroll({
        factorType: 'totp',
        friendlyName: 'Lefture Admin',
      });
      if (enrollErr) throw enrollErr;
      setStage({
        kind: 'enroll',
        factorId: enrolled.id,
        qrCode: enrolled.totp.qr_code,
        secret: enrolled.totp.secret,
      });
    })().catch((e) => setError(e instanceof Error ? e.message : String(e)));
  }, []);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (stage.kind === 'loading') return;
    setBusy(true);
    setError(null);
    const { error: verifyErr } = await supabase.auth.mfa.challengeAndVerify({
      factorId: stage.factorId,
      code: code.trim(),
    });
    setBusy(false);
    if (verifyErr) {
      setError(verifyErr.message);
      return;
    }
    onVerified();
  };

  return (
    <div className="adm-gate">
      <form className="adm-gate-card" onSubmit={submit}>
        <div className="adm-gate-icon">
          <ShieldCheck size={22} />
        </div>
        <h1 className="adm-page-title">
          {stage.kind === 'enroll' ? '認証アプリを登録' : stale ? 'もう一度認証してください' : '2段階認証'}
        </h1>
        <p className="adm-page-hint">
          {stage.kind === 'enroll'
            ? 'Admin はMFA(TOTP)必須です。認証アプリでQRコードを読み取り、表示された6桁のコードを入力してください。'
            : stale
              ? '前回の認証から時間が経ったため、Admin の操作には再認証が必要です。'
              : '認証アプリに表示されている6桁のコードを入力してください。'}
        </p>

        {stage.kind === 'loading' && !error && <Loading />}

        {stage.kind === 'enroll' && (
          <div className="adm-gate-qr">
            <img src={stage.qrCode} alt="TOTP登録用QRコード" width={180} height={180} />
            <div className="adm-gate-secret">
              <span className="adm-muted">手入力用のキー</span>
              <code>{stage.secret}</code>
            </div>
          </div>
        )}

        {stage.kind !== 'loading' && (
          <>
            <label className="adm-field">
              <span>6桁のコード</span>
              <input
                className="adm-input adm-input-code"
                inputMode="numeric"
                autoComplete="one-time-code"
                pattern="[0-9]{6}"
                maxLength={6}
                value={code}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))}
                autoFocus
                required
              />
            </label>
            <button type="submit" className="adm-btn adm-btn-primary" disabled={busy || code.length !== 6}>
              {busy ? '確認中…' : '認証する'}
            </button>
          </>
        )}
        <ErrorLine message={error} />
      </form>
    </div>
  );
};
