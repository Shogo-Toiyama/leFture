import { supabase } from './supabase';

const FALLBACK_LOCALE = 'en';
const LEGAL_REGION = 'us';

export interface LegalDocument {
  slug: string;
  locale: string;
  region: string;
  version: number;
  title: string;
  contentMarkdown: string;
  effectiveDate: string;
  updatedAt: string;
}

function mapRow(row: Record<string, unknown>): LegalDocument {
  return {
    slug: row.slug as string,
    locale: row.locale as string,
    region: row.region as string,
    version: row.version as number,
    title: row.title as string,
    contentMarkdown: row.content_markdown as string,
    effectiveDate: row.effective_date as string,
    updatedAt: row.updated_at as string,
  };
}

/** website/src/lib/supabase.ts の getLegalDocument と同じ仕様(locale → enフォールバック)。 */
export async function getLegalDocument(
  slug: string,
  locale: string,
  region: string = LEGAL_REGION
): Promise<LegalDocument> {
  const { data: row, error } = await supabase
    .from('legal_documents')
    .select('*')
    .eq('slug', slug)
    .eq('locale', locale)
    .eq('region', region)
    .maybeSingle();
  if (error) throw new Error(`Failed to query legal document: ${error.message}`);
  if (row) return mapRow(row);

  if (locale !== FALLBACK_LOCALE) {
    const { data: fallbackRow, error: fallbackError } = await supabase
      .from('legal_documents')
      .select('*')
      .eq('slug', slug)
      .eq('locale', FALLBACK_LOCALE)
      .eq('region', region)
      .maybeSingle();
    if (fallbackError) throw new Error(`Failed to query fallback legal document: ${fallbackError.message}`);
    if (fallbackRow) return mapRow(fallbackRow);
  }

  throw new Error(`Legal document not found for slug='${slug}', region='${region}'`);
}
