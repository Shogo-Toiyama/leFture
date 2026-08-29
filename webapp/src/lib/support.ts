import { apiFetch } from './api';

export type SupportCategory = 'bug' | 'feature_request' | 'account' | 'other';

interface SubmitSupportTicketResponse {
  success: boolean;
  ticket_code: string;
  message?: string;
}

/**
 * contact_page.dartのbody形状に合わせる。添付ファイルはMVPでは非対応
 * (attachment_urlsは常に空 — mobileのpresigned upload手順は移植していない)。
 */
export async function submitSupportTicket(category: SupportCategory, message: string): Promise<string> {
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
      },
    }),
  });
  return ticket_code;
}
