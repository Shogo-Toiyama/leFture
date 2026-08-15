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
// HTML Email Templates (Mirrors leFture Backend Design)
// ---------------------------------------------------------------------------

function buildEmailWrapper(bodyHtml: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>leFture Support</title>
  <style>
    body { margin: 0; padding: 0; background-color: #0B0D19; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; }
    a { color: #FFB300; }
  </style>
</head>
<body>
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#0B0D19; min-height:100vh; padding:40px 16px;">
    <tr>
      <td align="center">
        <table width="100%" style="max-width:560px; width:100%;" cellpadding="0" cellspacing="0">
          <tr>
            <td style="background:#16192E; border:1px solid #232742; border-radius:16px; padding:40px 36px 32px 36px;">
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

function buildUserAckEmail(name: string, ticketCode: string, category: string, message: string, hasAttachment: boolean): string {
  const greeting = name ? `Hi ${name},<br/><br/>` : `Hi,<br/><br/>`;
  const formattedMessage = message.replace(/\n/g, '<br/>');

  const content = `
    <!-- Header -->
    <div style="margin-bottom:28px;">
      <span style="display:inline-block; background:rgba(255,179,0,0.12); color:#FFB300; font-size:13px; font-weight:700; letter-spacing:0.06em; padding:5px 12px; border-radius:999px; text-transform:uppercase;">
        leFture Support
      </span>
      <h1 style="margin:16px 0 0 0; color:#F0F2FD; font-size:24px; font-weight:700; letter-spacing:-0.02em;">
        Inquiry Received
      </h1>
    </div>

    <!-- Body text -->
    <p style="margin:0 0 20px 0; color:#A4A8C4; font-size:15px; line-height:1.65;">
      ${greeting}Thank you for contacting leFture Support. We have received your inquiry and our team is currently reviewing your message.
    </p>

    <!-- Ticket Card -->
    <div style="background:#1C203A; border:1px solid #282D52; border-radius:12px; padding:20px; margin:24px 0; color:#F0F2FD; font-size:14px; line-height:1.6;">
      <p style="margin:0 0 8px 0;"><strong>Ticket Code:</strong> <span style="color:#FFB300; font-weight:700; letter-spacing:0.05em;">${ticketCode}</span></p>
      <p style="margin:0 0 8px 0;"><strong>Category:</strong> ${category}</p>
      ${hasAttachment ? '<p style="margin:0 0 8px 0; color:#4CAF50;"><strong>Attachment:</strong> 1 image attached</p>' : ''}
      <p style="margin:0 0 6px 0;"><strong>Your Message:</strong></p>
      <div style="margin:0; color:#8C92B4; word-break:break-word; background:#121424; padding:12px; border-radius:8px; border:1px solid #232742;">
        ${formattedMessage}
      </div>
    </div>

    <p style="margin:0 0 24px 0; color:#7E83A5; font-size:13.5px; line-height:1.6;">
      Our support team will get back to you as soon as possible via this email address. Please keep your ticket code for reference.
    </p>

    <!-- Footer -->
    <table width="100%" cellpadding="0" cellspacing="0" style="margin-top:28px;">
      <tr>
        <td style="border-top:1px solid #232742; padding-top:20px; text-align:center;">
          <p style="margin:0 0 6px 0; font-size:12px; color:#5D6285;">
            &copy; ${new Date().getFullYear()} leFture. All rights reserved.
          </p>
        </td>
      </tr>
    </table>
  `;

  return buildEmailWrapper(content);
}

function buildAdminNotificationEmail(
  ticketCode: string,
  name: string,
  email: string,
  category: string,
  message: string,
  userAgent: string,
  storagePath: string | null
): string {
  const formattedMessage = message.replace(/\n/g, '<br/>');

  const attachmentInfo = storagePath
    ? `<p style="margin:0 0 8px 0; color:#4CAF50;"><strong>Attachment:</strong> Attached to this email (R2: <code>${storagePath}</code>)</p>`
    : '';

  const content = `
    <!-- Header -->
    <div style="margin-bottom:24px;">
      <span style="display:inline-block; background:rgba(255,87,34,0.15); color:#FF7043; font-size:12px; font-weight:700; letter-spacing:0.06em; padding:4px 10px; border-radius:999px; text-transform:uppercase;">
        [Action Required] Web Support
      </span>
      <h1 style="margin:14px 0 0 0; color:#F0F2FD; font-size:22px; font-weight:700;">
        New Contact Inquiry
      </h1>
    </div>

    <p style="margin:0 0 16px 0; color:#A4A8C4; font-size:14.5px;">
      A new support inquiry was submitted via the leFture website:
    </p>

    <!-- Ticket details -->
    <div style="background:#1C203A; border:1px solid #282D52; border-radius:12px; padding:20px; margin:20px 0; color:#F0F2FD; font-size:14px; line-height:1.6;">
      <p style="margin:0 0 8px 0;"><strong>Ticket Code:</strong> <span style="color:#FFB300; font-weight:700;">${ticketCode}</span></p>
      <p style="margin:0 0 8px 0;"><strong>Name:</strong> ${name || 'N/A'}</p>
      <p style="margin:0 0 8px 0;"><strong>Email:</strong> <a href="mailto:${email}" style="color:#FFB300;">${email}</a></p>
      <p style="margin:0 0 8px 0;"><strong>Category:</strong> ${category}</p>
      ${attachmentInfo}
      <p style="margin:0 0 6px 0;"><strong>Message:</strong></p>
      <div style="margin:0 0 14px 0; color:#E0E4FC; word-break:break-word; background:#121424; padding:14px; border-radius:8px; border:1px solid #232742; line-height:1.6;">
        ${formattedMessage}
      </div>
      <p style="margin:0; font-size:12px; color:#686E91;"><strong>User-Agent:</strong> ${userAgent}</p>
    </div>

    <p style="margin:0; color:#7E83A5; font-size:13px;">
      💡 You can reply directly to this email to respond to the user.
    </p>
  `;

  return buildEmailWrapper(content);
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
    let attachmentFile: File | null = null;

    const contentType = request.headers.get('content-type') || '';

    if (contentType.includes('multipart/form-data')) {
      const formData = await request.formData();
      userName = (formData.get('name') as string)?.trim() || '';
      userEmail = (formData.get('email') as string)?.trim() || '';
      category = (formData.get('category') as string)?.trim() || 'general';
      message = (formData.get('message') as string)?.trim() || '';
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
      };
      userName = body.name?.trim() || '';
      userEmail = body.email?.trim() || '';
      category = body.category || 'general';
      message = body.message?.trim() || '';
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
          subject: `[leFture Web Support] New Inquiry: ${ticketCode}${storagePath ? ' 📷' : ''}`,
          html: buildAdminNotificationEmail(ticketCode, userName, userEmail, category, message, userAgent, storagePath),
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
          subject: `leFture Support - Inquiry Received [${ticketCode}]`,
          html: buildUserAckEmail(userName, ticketCode, category, message, !!storagePath),
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
