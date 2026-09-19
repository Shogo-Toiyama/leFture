// Cloudflare Pages Functions: /api/closed-test-signup
// Handles Android Closed Test signup requests for leFture,
// storing the request in Supabase support_tickets and sending emails via Resend.

interface Env {
  SUPABASE_URL?: string;
  SUPABASE_SECRET_KEY?: string;
  SUPABASE_SERVICE_ROLE_KEY?: string;
  EMAIL_WORKER_URL?: string;
  EMAIL_WORKER_SECRET?: string;
  RESEND_API_KEY?: string;
  ADMIN_EMAIL?: string;
  FROM_EMAIL?: string;
}

// Design tokens consistent with leFture
const COLOR_BACKGROUND = "#0D0D14";
const COLOR_CARD = "#13131C";
const COLOR_CARD_BORDER = "#2A2A3A";
const COLOR_PRIMARY = "#FFB300"; // Star Gold
const COLOR_TEXT_MAIN = "#E8E8F0";
const COLOR_TEXT_MUTED = "#8888AA";
const COLOR_SUCCESS = "#3DDC84"; // Android Green
const FONT_STACK = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif";

function buildEmailWrapper(bodyHtml: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <meta name="color-scheme" content="light dark"/>
  <title>leFture Android Closed Beta</title>
  <style>
    body {
      margin: 0 !important;
      padding: 0 !important;
      background-color: ${COLOR_BACKGROUND} !important;
      color: ${COLOR_TEXT_MAIN} !important;
      font-family: ${FONT_STACK};
      -webkit-text-size-adjust: 100%;
    }
    a { color: ${COLOR_PRIMARY}; text-decoration: none; }
  </style>
</head>
<body style="margin:0 !important; padding:0 !important; background-color:${COLOR_BACKGROUND} !important; color:${COLOR_TEXT_MAIN} !important;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color:${COLOR_BACKGROUND} !important; color:${COLOR_TEXT_MAIN} !important; min-height:100vh; padding:40px 16px;">
    <tr>
      <td align="center" style="background-color:${COLOR_BACKGROUND} !important;">
        <table width="100%" style="max-width:600px; width:100%;" cellpadding="0" cellspacing="0">
          <tr>
            <td style="background-color:${COLOR_CARD} !important; color:${COLOR_TEXT_MAIN} !important; border:1px solid ${COLOR_CARD_BORDER} !important; border-radius:16px; padding:40px 36px 32px 36px;">
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

function buildAdminNotificationEmail(
  ticketCode: string,
  userEmail: string,
  userName?: string,
  lang: string = 'en',
  submittedAt: string = ''
): string {
  const content = `
    <!-- Header -->
    <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:28px;">
      <tr>
        <td align="center">
          <span style="font-size:24px; font-weight:700; color:${COLOR_PRIMARY} !important; font-family:${FONT_STACK};">
            &#x2605; leFture Beta Desk
          </span>
        </td>
      </tr>
    </table>

    <div style="display:inline-block; background:rgba(61, 220, 132, 0.15); border:1px solid rgba(61, 220, 132, 0.3); border-radius:999px; padding:4px 12px; margin-bottom:16px;">
      <span style="color:${COLOR_SUCCESS} !important; font-size:12px; font-weight:700; text-transform:uppercase; letter-spacing:0.5px;">
        Android Closed Test 参加申請
      </span>
    </div>

    <h1 style="margin:0 0 16px 0; font-size:22px; font-weight:700; color:${COLOR_TEXT_MAIN} !important; font-family:${FONT_STACK}; line-height:1.3;">
      新しいクローズドテスト申し込みが届きました！
    </h1>

    <p style="margin:0 0 20px 0; font-size:15px; color:${COLOR_TEXT_MAIN} !important; line-height:1.6;">
      Webサイトの「Try leFture」より、以下のユーザーからAndroidクローズドテストへの参加申請がありました。
    </p>

    <!-- Details Box -->
    <div style="background:${COLOR_CARD_BORDER} !important; border-radius:12px; padding:20px; margin:20px 0;">
      <table width="100%" cellpadding="0" cellspacing="0" style="font-size:14px; line-height:1.7;">
        <tr>
          <td style="color:${COLOR_TEXT_MUTED} !important; width:130px; padding-bottom:8px; vertical-align:top;"><strong>Google Email:</strong></td>
          <td style="color:${COLOR_PRIMARY} !important; font-weight:600; font-size:15px; padding-bottom:8px; vertical-align:top;">
            <a href="mailto:${userEmail}" style="color:${COLOR_PRIMARY} !important; text-decoration:underline;">${userEmail}</a>
          </td>
        </tr>
        <tr>
          <td style="color:${COLOR_TEXT_MUTED} !important; padding-bottom:8px; vertical-align:top;"><strong>お名前:</strong></td>
          <td style="color:${COLOR_TEXT_MAIN} !important; padding-bottom:8px; vertical-align:top;">${userName || '（未入力）'}</td>
        </tr>
        <tr>
          <td style="color:${COLOR_TEXT_MUTED} !important; padding-bottom:8px; vertical-align:top;"><strong>言語 / 送信日時:</strong></td>
          <td style="color:${COLOR_TEXT_MAIN} !important; padding-bottom:8px; vertical-align:top;">${lang.toUpperCase()} / ${submittedAt}</td>
        </tr>
        <tr>
          <td style="color:${COLOR_TEXT_MUTED} !important; vertical-align:top;"><strong>管理ID:</strong></td>
          <td style="color:${COLOR_TEXT_MUTED} !important; font-family:monospace; vertical-align:top;">${ticketCode}</td>
        </tr>
      </table>
    </div>

    <!-- Instructions for Admin -->
    <div style="border-left:3px solid ${COLOR_PRIMARY}; padding-left:16px; margin:24px 0;">
      <p style="margin:0 0 8px 0; font-size:14px; font-weight:700; color:${COLOR_PRIMARY} !important;">
        今後のアクション手順
      </p>
      <ol style="margin:0; padding-left:18px; font-size:13px; color:${COLOR_TEXT_MAIN} !important; line-height:1.6;">
        <li>Google Play Consoleを開き、<strong>「クローズドテスト」</strong>のテスターリストに <code>${userEmail}</code> を追加します。</li>
        <li>追加完了後、Play Consoleの「テスターの参加方法」にあるURL（または案内メール）をユーザー宛に返信・共有してください。</li>
      </ol>
    </div>

    <table width="100%" cellpadding="0" cellspacing="0" style="margin:28px 0 16px 0;">
      <tr>
        <td align="center">
          <a href="https://play.google.com/console/" target="_blank" style="
            display:inline-block;
            background:${COLOR_PRIMARY} !important;
            color:#0D0D14 !important;
            font-weight:700;
            font-size:14px;
            padding:12px 28px;
            border-radius:8px;
            text-decoration:none;
          ">
            Google Play Console を開く &rarr;
          </a>
        </td>
      </tr>
    </table>

    <hr style="border:none; border-top:1px solid ${COLOR_CARD_BORDER} !important; margin:28px 0 20px 0;"/>

    <p style="margin:0; font-size:12px; color:${COLOR_TEXT_MUTED} !important; text-align:center;">
      ※ このメールに直接返信すると、申請者（<strong>${userEmail}</strong>）へメールが送信されます。
    </p>
  `;

  return buildEmailWrapper(content);
}

function buildUserConfirmationEmail(
  userName?: string,
  userEmail: string = '',
  lang: string = 'en'
): string {
  const isJa = lang.toLowerCase().startsWith('ja');

  const greeting = userName
    ? (isJa ? `${userName} 様<br/><br/>` : `Hi ${userName},<br/><br/>`)
    : '';

  const heading = isJa
    ? 'Android クローズドテストへの参加申請を受け付けました'
    : 'Android Closed Beta Request Received';

  const body1 = isJa
    ? 'この度は AI学習アプリ「leFture」のAndroidクローズドテストにご関心をお寄せいただき、誠にありがとうございます！'
    : 'Thank you for your interest in joining the Android Closed Beta for leFture!';

  const body2 = isJa
    ? '現在、開発チームにてGoogle Play Consoleのテスターリストへの登録を順次進めております。'
    : 'Our team is currently adding your email to our Google Play Console tester roster.';

  const boxTitle = isJa ? '今後の流れ' : 'What happens next?';

  const steps = isJa
    ? `
      <ol style="margin:0; padding-left:18px; font-size:14px; color:${COLOR_TEXT_MAIN} !important; line-height:1.7;">
        <li><strong>テスター登録（1〜2営業日以内）:</strong> ご入力いただいたGoogleアカウント（<code>${userEmail}</code>）をGoogle Playのテスターリストに登録します。</li>
        <li><strong>インストールリンクのご送付:</strong> 登録完了後、Google Playストアからアプリをダウンロードできる専用リンクをメールでお送りします。</li>
        <li><strong>アプリのご利用開始:</strong> リンクからテストに参加し、アプリをインストールしてすぐにお試しいただけます。</li>
      </ol>
    `
    : `
      <ol style="margin:0; padding-left:18px; font-size:14px; color:${COLOR_TEXT_MAIN} !important; line-height:1.7;">
        <li><strong>Roster Registration:</strong> We will add your Google Account (<code>${userEmail}</code>) to our Google Play tester roster within 1-2 business days.</li>
        <li><strong>Download Link:</strong> Once registered, we will email you the official Google Play opt-in link to download the app.</li>
        <li><strong>Start Learning:</strong> Open the link, accept the invite, install leFture, and enjoy!</li>
      </ol>
    `;

  const footerNote = isJa
    ? 'ご不明な点やご質問がございましたら、本メールへのご返信、または <a href="mailto:support@lefture.com">support@lefture.com</a> までお気軽にお問い合わせください。'
    : 'If you have any questions or feedback, feel free to reply directly to this email or reach us at <a href="mailto:support@lefture.com">support@lefture.com</a>.';

  const content = `
    <!-- Header -->
    <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:28px;">
      <tr>
        <td align="center">
          <span style="font-size:24px; font-weight:700; color:${COLOR_PRIMARY} !important; font-family:${FONT_STACK};">
            &#x2605; leFture
          </span>
        </td>
      </tr>
    </table>

    <h1 style="margin:0 0 16px 0; font-size:21px; font-weight:700; color:${COLOR_TEXT_MAIN} !important; font-family:${FONT_STACK}; line-height:1.35;">
      ${heading}
    </h1>

    <p style="margin:0 0 16px 0; font-size:15px; color:${COLOR_TEXT_MAIN} !important; line-height:1.6;">
      ${greeting}${body1}
    </p>

    <p style="margin:0 0 20px 0; font-size:15px; color:${COLOR_TEXT_MAIN} !important; line-height:1.6;">
      ${body2}
    </p>

    <!-- Next Steps Box -->
    <div style="background:${COLOR_CARD_BORDER} !important; border-radius:12px; padding:20px; margin:24px 0;">
      <p style="margin:0 0 12px 0; font-size:15px; font-weight:700; color:${COLOR_PRIMARY} !important;">
        ${boxTitle}
      </p>
      ${steps}
    </div>

    <p style="margin:20px 0 0 0; font-size:13px; color:${COLOR_TEXT_MUTED} !important; line-height:1.6;">
      ${footerNote}
    </p>

    <hr style="border:none; border-top:1px solid ${COLOR_CARD_BORDER} !important; margin:32px 0 20px 0;"/>

    <p style="margin:0; font-size:12px; color:${COLOR_TEXT_MUTED} !important; text-align:center;">
      &copy; ${new Date().getFullYear()} leFture. All rights reserved.
    </p>
  `;

  return buildEmailWrapper(content);
}

export async function onRequestPost(context: { request: Request; env: Env }): Promise<Response> {
  const { request, env } = context;

  try {
    let email = '';
    let name = '';
    let lang = 'ja';

    const contentType = request.headers.get('content-type') || '';
    if (contentType.includes('multipart/form-data')) {
      const formData = await request.formData();
      email = (formData.get('email') as string)?.trim() || '';
      name = (formData.get('name') as string)?.trim() || '';
      lang = (formData.get('lang') as string)?.trim() || 'ja';
    } else {
      const body = await request.json() as {
        email?: string;
        name?: string;
        lang?: string;
      };
      email = body.email?.trim() || '';
      name = body.name?.trim() || '';
      lang = body.lang?.trim() || 'ja';
    }

    // Basic email validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!email || !emailRegex.test(email)) {
      return new Response(
        JSON.stringify({ error: 'Valid email address is required.' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const userAgent = request.headers.get('User-Agent') || 'unknown';
    const submittedAt = new Date().toLocaleString('ja-JP', { timeZone: 'Asia/Tokyo' });

    // Generate unique signup code
    const characters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let randomPart = '';
    for (let i = 0; i < 6; i++) {
      randomPart += characters.charAt(Math.floor(Math.random() * characters.length));
    }
    const ticketCode = `LFT-BETA-${randomPart}`;

    // 1. Optionally save into Supabase `support_tickets`
    const supabaseUrl = env.SUPABASE_URL || 'https://lvbpuywjxmmeecftinkb.supabase.co';
    const supabaseKey = env.SUPABASE_SECRET_KEY || env.SUPABASE_SERVICE_ROLE_KEY;

    if (supabaseKey) {
      try {
        const record = {
          ticket_code: ticketCode,
          user_id: null,
          user_email: email,
          category: 'closed_test_signup',
          message: `Android Closed Test Request\nName: ${name || '-'}`,
          attachment_urls: [],
          device_info: {
            platform: 'android_closed_test',
            user_agent: userAgent,
            name: name || null,
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
          body: JSON.stringify(record),
        });

        if (!res.ok) {
          console.error('Failed to log closed test signup to Supabase:', await res.text());
        }
      } catch (dbErr) {
        console.error('Supabase logging error:', dbErr);
      }
    }

    // 2. Send Emails via Cloudflare Email Worker (or Resend Fallback)
    const adminEmail = env.ADMIN_EMAIL || 'lefture.app@gmail.com';
    const fromAddress = env.FROM_EMAIL || 'support@lefture.com';

    const userSubject = lang.toLowerCase().startsWith('ja')
      ? '【leFture】Android クローズドテストへの参加申請を受け付けました'
      : '[leFture] Android Closed Beta Request Received';

    const sendSingleEmail = async (payload: {
      to: string;
      subject: string;
      html: string;
      reply_to?: string;
    }) => {
      // 2-A. Cloudflare Email Worker が設定されている場合
      if (env.EMAIL_WORKER_URL && env.EMAIL_WORKER_SECRET) {
        let workerUrl = env.EMAIL_WORKER_URL.trim().replace(/\/+$/, '');
        if (!workerUrl.endsWith('/send')) {
          workerUrl += '/send';
        }
        const res = await fetch(workerUrl, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${env.EMAIL_WORKER_SECRET}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            to: payload.to,
            subject: payload.subject,
            html: payload.html,
            from_name: 'leFture',
            from_address: fromAddress,
            reply_to: payload.reply_to,
          }),
        });
        if (!res.ok) {
          throw new Error(`Email worker error (${res.status}): ${await res.text()}`);
        }
        return;
      }

      // 2-B. 従来の Resend フォールバック
      if (env.RESEND_API_KEY) {
        const res = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${env.RESEND_API_KEY}`,
          },
          body: JSON.stringify({
            from: `leFture <${fromAddress}>`,
            to: [payload.to],
            reply_to: payload.reply_to,
            subject: payload.subject,
            html: payload.html,
          }),
        });
        if (!res.ok) {
          throw new Error(`Resend error (${res.status}): ${await res.text()}`);
        }
        return;
      }

      console.warn('Neither EMAIL_WORKER nor RESEND_API_KEY is configured. Skipping email.');
    };

    // Email 1: Admin Notification to lefture.app@gmail.com
    const adminEmailPromise = sendSingleEmail({
      to: adminEmail,
      subject: `【leFture】Android Closed Test 参加申請 (${email})`,
      html: buildAdminNotificationEmail(ticketCode, email, name, lang, submittedAt),
      reply_to: email,
    }).catch((e) => console.error('Failed to send admin notification email:', e));

    // Email 2: User Confirmation
    const userEmailPromise = sendSingleEmail({
      to: email,
      subject: userSubject,
      html: buildUserConfirmationEmail(name, email, lang),
    }).catch((e) => console.error('Failed to send user confirmation email:', e));

    await Promise.allSettled([adminEmailPromise, userEmailPromise]);

    return new Response(
      JSON.stringify({
        success: true,
        code: ticketCode,
        message: 'Signup successful',
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
