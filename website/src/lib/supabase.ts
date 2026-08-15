import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://lvbpuywjxmmeecftinkb.supabase.co';
const supabasePublishableKey =
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ||
  import.meta.env.VITE_SUPABASE_ANON_KEY ||
  'sb_publishable_LUfg9T2f-zvargd7GgR7Cw_KAl86N8c';

export const supabase = createClient(supabaseUrl, supabasePublishableKey);

export const kAppLegalRegion = 'us';
const kFallbackLocale = 'en';

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

/**
 * Flutterアプリの [LegalContentRepositorySupabase] と同一の仕様で法務ドキュメントを取得。
 * 1. 指定 locale & region で取得
 * 2. なければ fallbackLocale ('en') & region で取得
 * 3. 取得できない場合は例外を投げる (ダミーテキストへのフォールバックは行わない)
 */
export async function getLegalDocument(slug: string, locale: string, region: string = kAppLegalRegion): Promise<LegalDocument> {
  // 1. 指定言語・リージョンでクエリ
  const { data: row, error } = await supabase
    .from('legal_documents')
    .select('*')
    .eq('slug', slug)
    .eq('locale', locale)
    .eq('region', region)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to query legal document: ${error.message}`);
  }

  if (row) {
    return {
      slug: row.slug,
      locale: row.locale,
      region: row.region,
      version: row.version,
      title: row.title,
      contentMarkdown: row.content_markdown,
      effectiveDate: row.effective_date,
      updatedAt: row.updated_at,
    };
  }

  // 2. フォールバック言語 ('en') でクエリ
  if (locale !== kFallbackLocale) {
    const { data: fallbackRow, error: fallbackError } = await supabase
      .from('legal_documents')
      .select('*')
      .eq('slug', slug)
      .eq('locale', kFallbackLocale)
      .eq('region', region)
      .maybeSingle();

    if (fallbackError) {
      throw new Error(`Failed to query fallback legal document: ${fallbackError.message}`);
    }

    if (fallbackRow) {
      return {
        slug: fallbackRow.slug,
        locale: fallbackRow.locale,
        region: fallbackRow.region,
        version: fallbackRow.version,
        title: fallbackRow.title,
        contentMarkdown: fallbackRow.content_markdown,
        effectiveDate: fallbackRow.effective_date,
        updatedAt: fallbackRow.updated_at,
      };
    }
  }

  throw new Error(`Legal document not found for slug='${slug}', region='${region}'`);
}

export interface SupportTicketSubmission {
  name?: string;
  email: string;
  category: string;
  message: string;
}

export interface SupportTicketResponse {
  success: boolean;
  ticket_code: string;
  message?: string;
}
