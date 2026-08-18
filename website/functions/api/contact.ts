// Cloudflare Pages Functions: /api/contact
// Handles public contact form submissions for leFture website,
// inserting into Supabase support_tickets, uploading attachments to R2, and sending emails via Resend.

interface R2BucketBinding {
  put(
    key: string,
    value: ReadableStream | ArrayBuffer | ArrayBufferView | string | Blob | null,
    options?: {
      httpMetadata?: {
        contentType?: string;
      };
      customMetadata?: Record<string, string>;
    }
  ): Promise<any>;
}

interface Env {
  SUPABASE_URL?: string;
  SUPABASE_SECRET_KEY?: string;
  SUPABASE_SERVICE_ROLE_KEY?: string;
  RESEND_API_KEY?: string;
  ADMIN_EMAIL?: string;
  FROM_EMAIL?: string;
  LECTURE_ASSETS?: R2BucketBinding;
  R2_BUCKET?: R2BucketBinding;
  ATTACHMENTS_BUCKET?: R2BucketBinding;
}

// ---------------------------------------------------------------------------
// HTML Email Templates (100% Identical with leFture Backend email_template.py)
// ---------------------------------------------------------------------------

const COLOR_BACKGROUND = "#0D0D14";
const COLOR_CARD = "#13131C";
const COLOR_CARD_BORDER = "#2A2A3A";
const COLOR_PRIMARY = "#C89A2C";
const COLOR_TEXT_MAIN = "#E8E8F0";
const COLOR_TEXT_MUTED = "#8888AA";
const FONT_STACK = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif";

const EMAIL_CONTENT_EN = {
  SUPPORT_APP_NAME: "leFture Support",
  SUPPORT_DESK_APP_NAME: "leFture Support Desk",
  FOOTER_IGNORE_NOTE: "If you did not request this email, you can safely ignore it.",
  FOOTER_COPYRIGHT: `&copy; ${new Date().getFullYear()} leFture. All rights reserved.`,
  SUPPORT_ACK_SUBJECT: "leFture Support - Inquiry Received [{ticket_code}]",
  SUPPORT_ACK_HEADING: "Inquiry Received",
  SUPPORT_ACK_BODY: "Thank you for contacting leFture Support. We have received your report and our team is currently reviewing your message.",
  SUPPORT_ACK_TICKET_CODE_LABEL: "Ticket Code",
  SUPPORT_ACK_CATEGORY_LABEL: "Category",
  SUPPORT_ACK_MESSAGE_LABEL: "Message Details",
  SUPPORT_ACK_FOOTER_NOTE: "Our support team will get back to you as soon as possible via this email address. Please keep your ticket code for reference.",
  SUPPORT_ADMIN_SUBJECT: "[leFture Web Support] New Inquiry: {ticket_code}",
  SUPPORT_ADMIN_HEADING: "[Action Required] New Support Inquiry",
  SUPPORT_ADMIN_BODY: "A new support inquiry was submitted via the leFture website:",
  SUPPORT_ADMIN_FOOTER_NOTE: "Replying directly to this email will respond to the user's email address (<strong>{user_email}</strong>).",
};

const EMAIL_CONTENT_JA = {
  SUPPORT_APP_NAME: "leFture サポート",
  SUPPORT_DESK_APP_NAME: "leFture サポートデスク",
  FOOTER_IGNORE_NOTE: "本メールにお心当たりがない場合は、破棄していただけますようお願いいたします。",
  FOOTER_COPYRIGHT: `&copy; ${new Date().getFullYear()} leFture. All rights reserved.`,
  SUPPORT_ACK_SUBJECT: "【leFture サポート】お問い合わせを受領いたしました [{ticket_code}]",
  SUPPORT_ACK_HEADING: "お問い合わせを受領いたしました",
  SUPPORT_ACK_BODY: "leFture サポートにお問い合わせいただきありがとうございます。ご送信いただいた内容を正常に受け付けました。担当チームにて順次確認・対応を行っております。",
  SUPPORT_ACK_TICKET_CODE_LABEL: "チケットコード",
  SUPPORT_ACK_CATEGORY_LABEL: "カテゴリ",
  SUPPORT_ACK_MESSAGE_LABEL: "お問い合わせ内容",
  SUPPORT_ACK_FOOTER_NOTE: "サポートチームより、本メールアドレス宛に折り返しご連絡いたします。お問い合わせの際はチケットコードをお控えください。",
  SUPPORT_ADMIN_SUBJECT: "【leFture Webサポート】新規お問い合わせ: {ticket_code}",
  SUPPORT_ADMIN_HEADING: "[要対応] Web問い合わせ",
  SUPPORT_ADMIN_BODY: "leFture Webサイトより新しいサポート問い合わせが送信されました：",
  SUPPORT_ADMIN_FOOTER_NOTE: "このメールに直接返信すると、ユーザーのメールアドレス（<strong>{user_email}</strong>）へ返信されます。",
};

function getEmailContent(lang?: string) {
  if (lang && lang.toLowerCase().startsWith("ja")) {
    return EMAIL_CONTENT_JA;
  }
  return EMAIL_CONTENT_EN;
}

function emailHeader(appName: string = "leFture Support"): string {
  return `
    <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:32px;">
      <tr>
        <td align="center">
          <span style="
            font-size:26px;
            font-weight:700;
            letter-spacing:0.5px;
            color:${COLOR_PRIMARY} !important;
            font-family:${FONT_STACK};
          ">
            &#x2605; ${appName}
          </span>
        </td>
      </tr>
    </table>
  `;
}

function emailHeading(text: string): string {
  return `
    <h1 style="
      margin:0 0 16px 0;
      font-size:22px;
      font-weight:700;
      color:${COLOR_TEXT_MAIN} !important;
      font-family:${FONT_STACK};
      line-height:1.3;
    ">${text}</h1>
  `;
}

function emailText(content: string, muted: boolean = false): string {
  const color = muted ? COLOR_TEXT_MUTED : COLOR_TEXT_MAIN;
  return `
    <p style="
      margin:0 0 16px 0;
      font-size:15px;
      color:${color} !important;
      font-family:${FONT_STACK};
      line-height:1.6;
    ">${content}</p>
  `;
}

function emailDivider(): string {
  return `
    <hr style="
      border:none;
      border-top:1px solid ${COLOR_CARD_BORDER} !important;
      margin:24px 0;
    "/>
  `;
}

function emailFooter(lang?: string): string {
  const c = getEmailContent(lang);
  return `
    <table width="100%" cellpadding="0" cellspacing="0" style="margin-top:32px;">
      <tr>
        <td style="
          border-top:1px solid ${COLOR_CARD_BORDER} !important;
          padding-top:20px;
          text-align:center;
        ">
          <p style="
            margin:0 0 6px 0;
            font-size:13px;
            color:${COLOR_TEXT_MUTED} !important;
            font-family:${FONT_STACK};
          ">
            ${c.FOOTER_IGNORE_NOTE}
          </p>
          <p style="
            margin:0;
            font-size:13px;
            color:${COLOR_TEXT_MUTED} !important;
            font-family:${FONT_STACK};
          ">
            ${c.FOOTER_COPYRIGHT}
          </p>
        </td>
      </tr>
    </table>
  `;
}

function buildEmailWrapper(bodyHtml: string): string {
  return `<!DOCTYPE html>
<html lang="en" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <meta name="color-scheme" content="light dark"/>
  <meta name="supported-color-schemes" content="light dark"/>
  <title>leFture Support</title>
  <style>
    :root {
      color-scheme: light dark;
      supported-color-schemes: light dark;
    }
    html, body {
      margin: 0 !important;
      padding: 0 !important;
      background-color: ${COLOR_BACKGROUND} !important;
      color: ${COLOR_TEXT_MAIN} !important;
      font-family: ${FONT_STACK};
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
    }
    @media (prefers-color-scheme: dark) {
      body, table, td, div, p, span, h1, h2, h3 {
        background-color: ${COLOR_BACKGROUND} !important;
        color: ${COLOR_TEXT_MAIN} !important;
      }
      .email-card-td {
        background-color: ${COLOR_CARD} !important;
        border-color: ${COLOR_CARD_BORDER} !important;
      }
    }
    @media (prefers-color-scheme: light) {
      body, table, td, div, p, span, h1, h2, h3 {
        background-color: ${COLOR_BACKGROUND} !important;
        color: ${COLOR_TEXT_MAIN} !important;
      }
      .email-card-td {
        background-color: ${COLOR_CARD} !important;
        border-color: ${COLOR_CARD_BORDER} !important;
      }
    }
    a { color: ${COLOR_PRIMARY} !important; }
  </style>
</head>
<body style="margin:0 !important; padding:0 !important; background-color:${COLOR_BACKGROUND} !important; color:${COLOR_TEXT_MAIN} !important;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color:${COLOR_BACKGROUND} !important; color:${COLOR_TEXT_MAIN} !important; min-height:100vh; padding:40px 16px;">
    <tr>
      <td align="center" style="background-color:${COLOR_BACKGROUND} !important;">
        <table width="100%" style="max-width:600px; width:100%;" cellpadding="0" cellspacing="0">
          <tr>
            <td class="email-card-td" style="background-color:${COLOR_CARD} !important; color:${COLOR_TEXT_MAIN} !important; border:1px solid ${COLOR_CARD_BORDER} !important; border-radius:16px; padding:40px 40px 32px 40px;">
              ${bodyHtml}
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

function buildUserAckEmail(name: string, ticketCode: string, category: string, message: string, hasAttachment: boolean, lang?: string): string {
  const c = getEmailContent(lang);
  const greeting = name ? `Hi ${name},<br/><br/>` : ``;
  const formattedMessage = message.replace(/\n/g, '<br/>');

  const attachmentNote = hasAttachment ? `<p style="margin:0 0 8px 0; color:#4CAF50;"><strong>Attachment:</strong> 1 file attached</p>` : '';

  const ticketInfo = `
    <div style="
      background:${COLOR_CARD_BORDER} !important;
      border-radius:12px;
      padding:20px;
      margin:20px 0;
      color:${COLOR_TEXT_MAIN} !important;
      font-family:${FONT_STACK};
      font-size:15px;
      line-height:1.6;
    ">
      <p style="margin:0 0 8px 0;"><strong>${c.SUPPORT_ACK_TICKET_CODE_LABEL}:</strong> <span style="color:${COLOR_PRIMARY} !important; font-weight:700;">${ticketCode}</span></p>
      <p style="margin:0 0 8px 0;"><strong>${c.SUPPORT_ACK_CATEGORY_LABEL}:</strong> ${category}</p>
      ${attachmentNote}
      <p style="margin:0 0 4px 0;"><strong>${c.SUPPORT_ACK_MESSAGE_LABEL}:</strong></p>
      <p style="margin:0; color:${COLOR_TEXT_MUTED} !important; word-break:break-word;">${formattedMessage}</p>
    </div>
  `;

  const body = 
    emailHeader(c.SUPPORT_APP_NAME) +
    emailHeading(c.SUPPORT_ACK_HEADING) +
    emailText(`${greeting}${c.SUPPORT_ACK_BODY}`) +
    ticketInfo +
    emailDivider() +
    emailText(c.SUPPORT_ACK_FOOTER_NOTE, true) +
    emailFooter(lang);

  return buildEmailWrapper(body);
}

function buildAdminNotificationEmail(
  ticketCode: string,
  name: string,
  email: string,
  category: string,
  message: string,
  userAgent: string,
  storagePath: string | null,
  lang?: string
): string {
  const c = getEmailContent(lang);
  const formattedMessage = message.replace(/\n/g, '<br/>');

  const attachmentInfo = storagePath
    ? `<p style="margin:0 0 8px 0; color:#4CAF50;"><strong>Attachment:</strong> R2 Storage Path: <code>${storagePath}</code></p>`
    : '';

  const adminInfo = `
    <div style="
      background:${COLOR_CARD_BORDER} !important;
      border-radius:12px;
      padding:20px;
      margin:20px 0;
      color:${COLOR_TEXT_MAIN} !important;
      font-family:${FONT_STACK};
      font-size:15px;
      line-height:1.6;
    ">
      <p style="margin:0 0 8px 0;"><strong>Ticket Code:</strong> <span style="color:${COLOR_PRIMARY} !important; font-weight:700;">${ticketCode}</span></p>
      <p style="margin:0 0 8px 0;"><strong>User Name:</strong> ${name || 'N/A'}</p>
      <p style="margin:0 0 8px 0;"><strong>User Email:</strong> ${email}</p>
      <p style="margin:0 0 8px 0;"><strong>Category:</strong> ${category}</p>
      ${attachmentInfo}
      <p style="margin:0 0 4px 0;"><strong>Message:</strong></p>
      <p style="margin:0 0 12px 0; color:${COLOR_TEXT_MUTED} !important; word-break:break-word;">${formattedMessage}</p>
      <p style="margin:0; font-size:12px; color:${COLOR_TEXT_MUTED} !important;"><strong>User-Agent:</strong> ${userAgent}</p>
    </div>
  `;

  const footerNote = c.SUPPORT_ADMIN_FOOTER_NOTE.replace('{user_email}', email);

  const body = 
    emailHeader(c.SUPPORT_DESK_APP_NAME) +
    emailHeading(c.SUPPORT_ADMIN_HEADING) +
    emailText(c.SUPPORT_ADMIN_BODY) +
    adminInfo +
    emailDivider() +
    emailText(footerNote, true) +
    emailFooter(lang);

  return buildEmailWrapper(body);
}

function bufferToBase64(buffer: ArrayBuffer): string {
  let binary = '';
  const bytes = new Uint8Array(buffer);
  const len = bytes.byteLength;
  for (let i = 0; i < len; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

// ---------------------------------------------------------------------------
// Main Request Handler
// ---------------------------------------------------------------------------

export async function onRequestPost(context: { request: Request; env: Env }) {
  try {
    const { request, env } = context;

    let userName = '';
    let userEmail = '';
    let category = 'general';
    let message = '';
    let lang = 'en';
    let attachmentFile: File | null = null;

    const contentType = request.headers.get('content-type') || '';

    if (contentType.includes('multipart/form-data')) {
      const formData = await request.formData();
      userName = (formData.get('name') as string)?.trim() || '';
      userEmail = (formData.get('email') as string)?.trim() || '';
      category = (formData.get('category') as string)?.trim() || 'general';
      message = (formData.get('message') as string)?.trim() || '';
      lang = (formData.get('lang') as string)?.trim() || 'en';
      const fileEntry = formData.get('attachment');
      if (fileEntry && typeof fileEntry === 'object' && 'name' in fileEntry && (fileEntry as File).size > 0) {
        attachmentFile = fileEntry as File;
      }
    } else {
      const body = await request.json() as {
        name?: string;
        email?: string;
        category?: string;
        message?: string;
        lang?: string;
      };
      userName = body.name?.trim() || '';
      userEmail = body.email?.trim() || '';
      category = body.category || 'general';
      message = body.message?.trim() || '';
      lang = body.lang?.trim() || 'en';
    }

    if (!userEmail || !message) {
      return new Response(
        JSON.stringify({ error: 'Email and message are required.' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const userAgent = request.headers.get('User-Agent') || 'unknown';

    // 1. Generate unique ticket code (LFT-WEB-XXXXXXXX)
    const characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let randomPart = '';
    for (let i = 0; i < 8; i++) {
      randomPart += characters.charAt(Math.floor(Math.random() * characters.length));
    }
    const ticketCode = `LFT-WEB-${randomPart}`;

    // 2. Upload screenshot to R2 if provided
    let storagePath: string | null = null;
    let attachmentBuffer: ArrayBuffer | null = null;

    if (attachmentFile) {
      const rawName = attachmentFile.name.replace(/[^a-zA-Z0-9._-]/g, '_');
      const uniqueId = Math.random().toString(36).substring(2, 12);
      storagePath = `support_attachments/web/${uniqueId}_${rawName}`;

      attachmentBuffer = await attachmentFile.arrayBuffer();

      const r2Bucket = env.LECTURE_ASSETS || env.R2_BUCKET || env.ATTACHMENTS_BUCKET;
      if (r2Bucket) {
        try {
          await r2Bucket.put(storagePath, attachmentBuffer, {
            httpMetadata: {
              contentType: attachmentFile.type || 'image/png',
            },
          });
        } catch (r2Err) {
          console.error('Failed to upload attachment to R2:', r2Err);
        }
      } else {
        console.warn('R2_BUCKET binding is not configured. Saved path reference only.');
      }
    }

    const supabaseUrl = env.SUPABASE_URL || 'https://lvbpuywjxmmeecftinkb.supabase.co';
    const supabaseKey = env.SUPABASE_SECRET_KEY || env.SUPABASE_SERVICE_ROLE_KEY;

    // 3. Insert into Supabase `support_tickets`
    if (supabaseKey) {
      try {
        const ticketData = {
          ticket_code: ticketCode,
          user_id: null,
          user_email: userEmail,
          category,
          message,
          attachment_urls: storagePath ? [storagePath] : [],
          device_info: {
            platform: 'web',
            user_agent: userAgent,
            name: userName || null,
            lang: lang,
          },
          status: 'open',
        };

        const res = await fetch(`${supabaseUrl}/rest/v1/support_tickets`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'apikey': supabaseKey,
            'Authorization': `Bearer ${supabaseKey}`,
            'Prefer': 'return=representation',
          },
          body: JSON.stringify(ticketData),
        });

        if (!res.ok) {
          console.error('Failed to insert support ticket in Supabase:', await res.text());
        }
      } catch (dbErr) {
        console.error('Supabase insertion error:', dbErr);
      }
    }

    // 4. Send Emails via Resend API
    const resendApiKey = env.RESEND_API_KEY;
    const adminEmail = env.ADMIN_EMAIL || 'lefture.app@gmail.com';
    const fromAddress = env.FROM_EMAIL || 'support@lefture.com';
    const emailContent = getEmailContent(lang);

    if (resendApiKey) {
      const emailHeaders = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${resendApiKey}`,
      };

      // Prepare attachment payload for Resend if image exists
      const emailAttachments = [];
      if (attachmentFile && attachmentBuffer) {
        emailAttachments.push({
          filename: attachmentFile.name,
          content: bufferToBase64(attachmentBuffer),
        });
      }

      // Email 1: Admin Notification
      const adminEmailPromise = fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: emailHeaders,
        body: JSON.stringify({
          from: `leFture Support <${fromAddress}>`,
          to: [adminEmail],
          reply_to: userEmail,
          subject: `${emailContent.SUPPORT_ADMIN_SUBJECT.replace('{ticket_code}', ticketCode)}${storagePath ? ' 📷' : ''}`,
          html: buildAdminNotificationEmail(ticketCode, userName, userEmail, category, message, userAgent, storagePath, lang),
          attachments: emailAttachments.length > 0 ? emailAttachments : undefined,
        }),
      }).catch((e) => console.error('Failed to send admin notification email:', e));

      // Email 2: User Auto-Acknowledgment
      const userAckEmailPromise = fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: emailHeaders,
        body: JSON.stringify({
          from: `leFture Support <${fromAddress}>`,
          to: [userEmail],
          subject: emailContent.SUPPORT_ACK_SUBJECT.replace('{ticket_code}', ticketCode),
          html: buildUserAckEmail(userName, ticketCode, category, message, !!storagePath, lang),
        }),
      }).catch((e) => console.error('Failed to send user ack email:', e));

      // Fire both email tasks concurrently
      await Promise.allSettled([adminEmailPromise, userAckEmailPromise]);
    } else {
      console.warn('RESEND_API_KEY is not configured on Cloudflare Pages. Skipping email delivery.');
    }

    return new Response(
      JSON.stringify({
        success: true,
        ticket_code: ticketCode,
        storage_path: storagePath,
        message: 'Inquiry submitted successfully',
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  } catch (error: any) {
    return new Response(
      JSON.stringify({ error: error.message || 'Internal Server Error' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
}
