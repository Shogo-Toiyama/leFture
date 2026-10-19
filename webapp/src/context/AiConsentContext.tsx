import React, { createContext, useCallback, useContext, useMemo, useRef, useState } from 'react';
import { AiConsentModal } from '../components/modals/AiConsentModal';
import { useProfile, mutateProfile, notifyProfileUpdate } from '../hooks/useProfile';
import { consentVersionOf, hasAiConsent, type AiConsentKind } from '../lib/aiConsent';
import { markAiConsent } from '../lib/profile';

interface AiConsentContextValue {
  /** 今の版で同意済みか(手元のプロフィールで判る範囲。まだ読み込めていなければfalse)。 */
  hasConsent: (kind: AiConsentKind) => boolean;
  /**
   * 同意済みならすぐtrue。まだなら同意のモーダルを出して聞き、同意されたらtrue、断られたらfalse。
   * 別の端末(アプリ)で同意していることもあるので、聞く前にサーバーの最新を読む。
   */
  requestConsent: (kind: AiConsentKind) => Promise<boolean>;
}

const AiConsentContext = createContext<AiConsentContextValue | undefined>(undefined);

interface Pending {
  kind: AiConsentKind;
  updated: boolean;
  resolve: (agreed: boolean) => void;
}

/**
 * AIサービスへのデータ送信への同意(録音・チャット)をアカウント単位で管理する。アプリ(Flutter)と
 * 同じキー・同じ版番号で profiles.metadata に残るので、どちらかで同意すればもう一方では出ない。
 */
export const AiConsentProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { profile } = useProfile();
  const [pending, setPending] = useState<Pending | null>(null);
  const pendingRef = useRef<Pending | null>(null);

  const hasConsent = useCallback((kind: AiConsentKind) => hasAiConsent(profile?.metadata, kind), [profile]);

  const requestConsent = useCallback(
    async (kind: AiConsentKind): Promise<boolean> => {
      if (hasAiConsent(profile?.metadata, kind)) return true;

      let latest = profile;
      try {
        latest = (await mutateProfile()) ?? profile;
      } catch {
        // 読めなくても、手元の値で聞く(聞き直すだけで、読めないまま通すことはしない)
      }
      if (hasAiConsent(latest?.metadata, kind)) return true;

      const updated = consentVersionOf(latest?.metadata, kind) > 0;
      // 同時に2つ聞かない: 先に開いているモーダルは断った扱いにする
      pendingRef.current?.resolve(false);
      return new Promise<boolean>((resolve) => {
        const next = { kind, updated, resolve };
        pendingRef.current = next;
        setPending(next);
      });
    },
    [profile]
  );

  const close = useCallback((agreed: boolean) => {
    const current = pendingRef.current;
    pendingRef.current = null;
    setPending(null);
    current?.resolve(agreed);
  }, []);

  const agree = useCallback(async () => {
    const current = pendingRef.current;
    if (!current) return;
    const updatedProfile = await markAiConsent(current.kind);
    notifyProfileUpdate(updatedProfile);
    close(true);
  }, [close]);

  const value = useMemo(() => ({ hasConsent, requestConsent }), [hasConsent, requestConsent]);

  return (
    <AiConsentContext.Provider value={value}>
      {children}
      {pending && (
        <AiConsentModal kind={pending.kind} updated={pending.updated} onAgree={agree} onCancel={() => close(false)} />
      )}
    </AiConsentContext.Provider>
  );
};

export function useAiConsent(): AiConsentContextValue {
  const ctx = useContext(AiConsentContext);
  if (!ctx) throw new Error('useAiConsent must be used within an AiConsentProvider');
  return ctx;
}
