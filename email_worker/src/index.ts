/**
 * lefture-email-worker
 *
 * Cloudflare Email Sending (send_email binding) を利用して、
 * 外部（GCP lefture_backend 等）から認証付きHTTPリクエスト経由で
 * トランザクションメールを送信する専用プロキシ Worker。
 *
 * リクエスト例:
 *   POST https://<worker-domain>/send
 *   Authorization: Bearer <EMAIL_WORKER_SECRET>
 *   Content-Type: application/json
 *
 *   {
 *     "to": "user@example.com",
 *     "subject": "件名",
 *     "html": "<h1>HTML本文</h1>",
 *     "text": "テキスト本文(任意)",
 *     "from_name": "leFture",
 *     "from_address": "hello@lefture.com",
 *     "reply_to": "support@lefture.com"
 *   }
 */

// SendEmail は @cloudflare/workers-types が提供するグローバル型をそのまま使う。
// (自前でバインディングの型を定義すると、実際のAPI形状とのズレを tsc が検知できなくなるため)
export interface Env {
  EMAIL: SendEmail;
  EMAIL_WORKER_SECRET?: string;
  DEFAULT_FROM_EMAIL?: string;
  DEFAULT_FROM_NAME?: string;
}

interface SendEmailPayload {
  to: string;
  subject: string;
  html: string;
  text?: string;
  from_address?: string;
  from_name?: string;
  reply_to?: string;
  attachments?: {
    content: string; // Base64 encoded string
    filename: string;
    type?: string;
  }[];
}

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type, X-Internal-Secret',
};

function jsonResponse(status: number, data: Record<string, any>): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...CORS_HEADERS,
    },
  });
}

/** タイミング攻撃耐性を持つ文字列比較 */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: CORS_HEADERS });
    }

    const url = new URL(request.url);

    // 1. Health check
    if (url.pathname === '/health' || url.pathname === '/') {
      return jsonResponse(200, {
        status: 'healthy',
        service: 'lefture-email-worker',
        timestamp: new Date().toISOString(),
      });
    }

    // 2. Email send endpoint
    if (url.pathname === '/send') {
      if (request.method !== 'POST') {
        return jsonResponse(405, { error: 'Method Not Allowed' });
      }

      // Check configured secret
      const configuredSecret = env.EMAIL_WORKER_SECRET;
      if (!configuredSecret) {
        console.error('EMAIL_WORKER_SECRET is not set in Worker environment');
        return jsonResponse(500, {
          error: 'Server configuration error: EMAIL_WORKER_SECRET is missing',
        });
      }

      // Extract client token
      const authHeader = request.headers.get('Authorization') || '';
      const customSecretHeader = request.headers.get('X-Internal-Secret') || '';

      let clientToken = '';
      if (authHeader.startsWith('Bearer ')) {
        clientToken = authHeader.substring(7).trim();
      } else if (customSecretHeader) {
        clientToken = customSecretHeader.trim();
      }

      if (!clientToken || !timingSafeEqual(clientToken, configuredSecret)) {
        return jsonResponse(401, { error: 'Unauthorized: Invalid or missing authentication token' });
      }

      // Parse payload
      let payload: SendEmailPayload;
      try {
        payload = (await request.json()) as SendEmailPayload;
      } catch {
        return jsonResponse(400, { error: 'Invalid JSON payload' });
      }

      const { to, subject, html, text, from_address, from_name, reply_to, attachments } = payload;

      // Validation
      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
      if (!to || typeof to !== 'string' || !emailRegex.test(to.trim())) {
        return jsonResponse(400, { error: 'Invalid or missing recipient email address (to)' });
      }

      if (!subject || typeof subject !== 'string' || !subject.trim()) {
        return jsonResponse(400, { error: 'Missing email subject' });
      }

      if (!html || typeof html !== 'string' || !html.trim()) {
        return jsonResponse(400, { error: 'Missing email html content' });
      }

      // Check send_email binding
      if (!env.EMAIL || typeof env.EMAIL.send !== 'function') {
        console.error('EMAIL binding is not properly bound or send_email is unavailable');
        return jsonResponse(500, {
          error: 'EMAIL binding unavailable. Ensure send_email is enabled and on Workers Paid plan.',
        });
      }

      const finalFromEmail = (from_address?.trim() || env.DEFAULT_FROM_EMAIL || 'hello@lefture.com');
      const finalFromName = (from_name?.trim() || env.DEFAULT_FROM_NAME || 'leFture');

      try {
        await env.EMAIL.send({
          to: to.trim(),
          from: {
            email: finalFromEmail,
            name: finalFromName,
          },
          subject: subject.trim(),
          html: html,
          text: text || undefined,
          replyTo: reply_to ? reply_to.trim() : undefined,
          attachments: attachments && Array.isArray(attachments)
            ? attachments.map((att): EmailAttachment => ({
                disposition: 'attachment',
                filename: att.filename,
                content: att.content,
                type: att.type || 'application/octet-stream',
              }))
            : undefined,
        });

        return jsonResponse(200, {
          success: true,
          message: 'Email delivered successfully',
          recipient: to.trim(),
          timestamp: new Date().toISOString(),
        });
      } catch (err: any) {
        console.error('Failed to send email via Cloudflare Email Sending:', err);
        return jsonResponse(500, {
          error: err.message || 'Failed to dispatch email via Cloudflare Email Sending',
        });
      }
    }

    return jsonResponse(404, { error: 'Not Found' });
  },
};
