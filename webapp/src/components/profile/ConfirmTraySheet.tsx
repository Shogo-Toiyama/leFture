import React, { useState } from 'react';
import { AdaptiveSheet } from '../modals/AdaptiveSheet';
import { useLanguage } from '../../i18n/LanguageContext';
import type { TranslationKey } from '../../i18n/translations';
import {
  selfPortraitApi,
  type CoverField,
  type CoverProposal,
  type CoverValue,
  type ProfileItem,
} from '../../lib/selfPortrait';

const FIELD_LABEL: Record<CoverField, TranslationKey> = {
  bio: 'aboutYouSection',
  interests: 'interestsSection',
  future_goals: 'futureDreamsSection',
};

const AREA_LABEL: Record<string, TranslationKey> = {
  religion: 'spAreaReligion',
  health: 'spAreaHealth',
  sexuality: 'spAreaSexuality',
  politics: 'spAreaPolitics',
  ethnicity: 'spAreaEthnicity',
};

/**
 * 確認トレイ: センシティブな分野の項目(残す / 残さない)と、本人が書いた欄への書き直し案(反映する / 今のまま)。
 * 確認するまで、確認待ちの項目はチャットやFun Factのどこにも使われない。
 */
export const ConfirmTraySheet: React.FC<{
  open: boolean;
  onClose: () => void;
  pending: ProfileItem[];
  proposals: CoverProposal[];
  cover: Record<CoverField, CoverValue> | null;
  onChanged: () => Promise<void>;
}> = ({ open, onClose, pending, proposals, cover, onChanged }) => {
  const { t } = useLanguage();
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const run = async (id: string, fn: () => Promise<unknown>) => {
    setBusyId(id);
    setError(null);
    try {
      await fn();
      await onChanged();
      if (pending.length + proposals.length <= 1) onClose();
    } catch {
      setError(t('spActionFailed'));
    } finally {
      setBusyId(null);
    }
  };

  return (
    <AdaptiveSheet open={open} onClose={onClose} title={t('spConfirmSheetTitle')}>
      <div className="sp-sheet">
        {error && <p className="auth-error">{error}</p>}

        {pending.map((item) => (
          <div key={item.id} className="sp-tray-card is-sensitive">
            <span className="sp-tray-kicker">
              {t('spSensitiveAsk', { area: t(AREA_LABEL[item.sensitive] ?? 'spAreaSensitive') })}
            </span>
            <p className="sp-tray-text">{item.content}</p>
            <span className="sp-tray-note">{t('spPendingNotice')}</span>
            <div className="sp-inline-actions">
              <button type="button" className="btn btn-primary" disabled={busyId !== null} onClick={() => run(item.id, () => selfPortraitApi.keep(item.id))}>
                {t('spKeep')}
              </button>
              <button type="button" className="btn btn-ghost" disabled={busyId !== null} onClick={() => run(item.id, () => selfPortraitApi.discard(item.id))}>
                {t('spDontKeep')}
              </button>
            </div>
          </div>
        ))}

        {proposals.map((p) => (
          <div key={p.id} className="sp-tray-card">
            <span className="sp-tray-kicker is-muted">{t('spProposalTitle', { field: t(FIELD_LABEL[p.field]) })}</span>
            {cover?.[p.field]?.text && (
              <p className="sp-tray-before"><span>{t('spProposalNow')}</span>{cover[p.field].text}</p>
            )}
            <p className="sp-tray-text">{p.proposed_text}</p>
            <div className="sp-inline-actions">
              <button type="button" className="btn btn-primary" disabled={busyId !== null} onClick={() => run(p.id, () => selfPortraitApi.decideProposal(p.id, true))}>
                {t('spProposalAccept')}
              </button>
              <button type="button" className="btn btn-ghost" disabled={busyId !== null} onClick={() => run(p.id, () => selfPortraitApi.decideProposal(p.id, false))}>
                {t('spProposalReject')}
              </button>
            </div>
          </div>
        ))}

        {pending.length === 0 && proposals.length === 0 && <p className="sp-empty">{t('spConfirmEmpty')}</p>}
      </div>
    </AdaptiveSheet>
  );
};
