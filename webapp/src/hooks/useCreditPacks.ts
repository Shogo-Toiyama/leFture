import { useEffect, useState } from 'react';
import { listCreditPacks } from '../lib/billing';
import type { CreditPackOption } from '../types/billing';
import { useLanguage } from '../i18n/LanguageContext';

export function useCreditPacks() {
  const { t } = useLanguage();
  const [packs, setPacks] = useState<CreditPackOption[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    listCreditPacks()
      .then(setPacks)
      .catch((err) => setError(err instanceof Error ? err.message : t('failedToLoadCreditPacks')))
      .finally(() => setLoading(false));
  }, [t]);

  return { packs, loading, error };
}
