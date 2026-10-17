import { apiFetch } from './api';

/**
 * support_tickets.categoryは自由な文字列で、管理画面は値をそのまま出す。
 * inappropriate / incorrect はAIチャットの回答への報告で使う(モバイルのお問い合わせには無い)。
 */
export type SupportCategory = 'bug' | 'feature_request' | 'account' | 'other' | 'inappropriate' | 'incorrect';

interface SubmitSupportTicketResponse {
  success: boolean;
  ticket_code: string;
  message?: string;
}

/**
 * contact_page.dartのbody形状に合わせる。添付ファイルはMVPでは非対応
 * (attachment_urlsは常に空 — mobileのpresigned upload手順は移植していない)。
 */
export async function submitSupportTicket(
  category: SupportCategory,
  message: string,
  /** 問い合わせの発生元の情報(どの画面の何についてか)。device_info.report に入り、管理者宛のメールに載る。 */
  report?: Record<string, unknown>
): Promise<string> {
  const { ticket_code } = await apiFetch<SubmitSupportTicketResponse>('/support/submit', {
    method: 'POST',
    body: JSON.stringify({
      category,
      message,
      attachment_urls: [],
      device_info: {
        os: 'web',
        os_version: navigator.userAgent,
        app_version: 'web',
        locale: navigator.language,
        ...(report ? { report } : {}),
      },
    }),
  });
  return ticket_code;
}
