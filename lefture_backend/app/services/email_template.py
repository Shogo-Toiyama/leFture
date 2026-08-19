"""
email_template.py
-----------------
leFture 共通メールテンプレートシステム。

【設計方針】
- テーマカラー・フォント・レイアウトはすべてこのファイルで一元管理。
- 共通コンポーネント関数 (email_header, email_button 等) を組み合わせて
  アクションタイプ別の HTML を生成する build_*_email() 関数を提供する。
- 将来的にデザインを変更する場合も、この 1 ファイルを編集するだけで
  全メールに反映される。
"""

# ---------------------------------------------------------------------------
# テーマ定数
# ---------------------------------------------------------------------------

# --- Colors (アプリと統一) ---
COLOR_BACKGROUND   = "#0D0D14"   # voidBackground
COLOR_CARD         = "#13131C"   # カード背景
COLOR_CARD_BORDER  = "#2A2A3A"   # ガラスボーダー
COLOR_PRIMARY      = "#C89A2C"   # starGold (CTA ボタン等)
COLOR_PRIMARY_DARK = "#A07820"   # ボタンホバー想定 / 補色
COLOR_TEXT_MAIN    = "#E8E8F0"   # textStarlight
COLOR_TEXT_MUTED   = "#8888AA"   # textComet
COLOR_BUTTON_TEXT  = "#0D0D14"   # ボタン上テキスト (ダーク背景に金色ボタン)

# --- Typography ---
FONT_STACK = (
    "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"
)
FONT_SIZE_BODY = "15px"
FONT_SIZE_SMALL = "13px"
FONT_SIZE_HEADING = "22px"

# --- Layout ---
EMAIL_MAX_WIDTH = "600px"


import datetime
from app.services.email_content import get_email_content, EmailContentEN

# ---------------------------------------------------------------------------
# 共通コンポーネント関数
# ---------------------------------------------------------------------------

def email_header(app_name: str = "leFture") -> str:
    """ロゴ + アプリ名ヘッダー"""
    return f"""
    <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:32px;">
      <tr>
        <td align="center">
          <span style="
            font-size:26px;
            font-weight:700;
            letter-spacing:0.5px;
            color:{COLOR_PRIMARY};
            font-family:{FONT_STACK};
          ">
            &#x2605; {app_name}
          </span>
        </td>
      </tr>
    </table>
    """


def email_heading(text: str) -> str:
    """メインの見出し"""
    return f"""
    <h1 style="
      margin:0 0 16px 0;
      font-size:{FONT_SIZE_HEADING};
      font-weight:700;
      color:{COLOR_TEXT_MAIN};
      font-family:{FONT_STACK};
      line-height:1.3;
    ">{text}</h1>
    """


def email_text(content: str, muted: bool = False) -> str:
    """本文テキスト段落"""
    color = COLOR_TEXT_MUTED if muted else COLOR_TEXT_MAIN
    return f"""
    <p style="
      margin:0 0 16px 0;
      font-size:{FONT_SIZE_BODY};
      color:{color};
      font-family:{FONT_STACK};
      line-height:1.6;
    ">{content}</p>
    """


def email_button(label: str, url: str) -> str:
    """starGold カラーの CTA ボタン"""
    return f"""
    <table width="100%" cellpadding="0" cellspacing="0" style="margin:28px 0;">
      <tr>
        <td align="center">
          <a href="{url}"
             class="email-btn-link"
             style="
               display:inline-block;
               padding:14px 36px;
               background-color:{COLOR_PRIMARY} !important;
               color:{COLOR_BUTTON_TEXT} !important;
               text-decoration:none;
               font-family:{FONT_STACK};
               font-size:{FONT_SIZE_BODY};
               font-weight:700;
               border-radius:10px;
               letter-spacing:0.3px;
             "
          >{label}</a>
        </td>
      </tr>
    </table>
    """


def email_divider() -> str:
    """水平区切り線"""
    return f"""
    <hr style="
      border:none;
      border-top:1px solid {COLOR_CARD_BORDER};
      margin:24px 0;
    "/>
    """


def email_fallback_link(url: str, lang: str = "en") -> str:
    """ボタンが機能しない場合のフォールバックリンクテキスト"""
    c = get_email_content(lang)
    note = getattr(c, "SIGNUP_FALLBACK_NOTE", EmailContentEN.SIGNUP_FALLBACK_NOTE)
    return f"""
    <p style="
      margin:0 0 8px 0;
      font-size:{FONT_SIZE_SMALL};
      color:{COLOR_TEXT_MUTED};
      font-family:{FONT_STACK};
      line-height:1.5;
    ">
      {note}
    </p>
    <p style="
      margin:0 0 16px 0;
      font-size:{FONT_SIZE_SMALL};
      color:{COLOR_TEXT_MUTED};
      font-family:{FONT_STACK};
      word-break:break-all;
    ">
      <a href="{url}" style="color:{COLOR_PRIMARY} !important;">{url}</a>
    </p>
    """


def email_footer(lang: str = "en") -> str:
    """フッター（免責・著作権）"""
    c = get_email_content(lang)
    current_year = datetime.datetime.now().year
    ignore_note = getattr(c, "FOOTER_IGNORE_NOTE", EmailContentEN.FOOTER_IGNORE_NOTE)
    copyright_text = getattr(c, "FOOTER_COPYRIGHT", EmailContentEN.FOOTER_COPYRIGHT).format(year=current_year)
    return f"""
    <table width="100%" cellpadding="0" cellspacing="0" style="margin-top:32px;">
      <tr>
        <td style="
          border-top:1px solid {COLOR_CARD_BORDER};
          padding-top:20px;
          text-align:center;
        ">
          <p style="
            margin:0 0 6px 0;
            font-size:{FONT_SIZE_SMALL};
            color:{COLOR_TEXT_MUTED};
            font-family:{FONT_STACK};
          ">
            {ignore_note}
          </p>
          <p style="
            margin:0;
            font-size:{FONT_SIZE_SMALL};
            color:{COLOR_TEXT_MUTED};
            font-family:{FONT_STACK};
          ">
            {copyright_text}
          </p>
        </td>
      </tr>
    </table>
    """


def email_wrapper(body_html: str) -> str:
    """
    全体のレイアウトラッパー。
    DOCTYPE + meta + 背景 + カードコンテナを提供する。
    メールクライアント（Gmail/Apple Mail等）の自動色反転を防止し、
    ダークモード・ライトモード環境にかかわらず黒背景・白文字を強制固定する。
    """
    return f"""<!DOCTYPE html>
<html lang="en" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <meta name="color-scheme" content="light dark"/>
  <meta name="supported-color-schemes" content="light dark"/>
  <title>leFture</title>
  <style>
    :root {{
      color-scheme: light dark;
      supported-color-schemes: light dark;
    }}
    html, body {{
      margin: 0 !important;
      padding: 0 !important;
      background-color: {COLOR_BACKGROUND} !important;
      color: {COLOR_TEXT_MAIN} !important;
      font-family: {FONT_STACK};
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
    }}
    /* メールクライアントの自動色反転オーバーライド */
    @media (prefers-color-scheme: dark) {{
      body, table, td, div, p, span, h1, h2, h3 {{
        background-color: {COLOR_BACKGROUND} !important;
        color: {COLOR_TEXT_MAIN} !important;
      }}
      .email-card-td {{
        background-color: {COLOR_CARD} !important;
        border-color: {COLOR_CARD_BORDER} !important;
      }}
    }}
    @media (prefers-color-scheme: light) {{
      body, table, td, div, p, span, h1, h2, h3 {{
        background-color: {COLOR_BACKGROUND} !important;
        color: {COLOR_TEXT_MAIN} !important;
      }}
      .email-card-td {{
        background-color: {COLOR_CARD} !important;
        border-color: {COLOR_CARD_BORDER} !important;
      }}
    }}
    a {{
      color: {COLOR_PRIMARY};
    }}
    .email-btn-link {{
      color: {COLOR_BUTTON_TEXT} !important;
      background-color: {COLOR_PRIMARY} !important;
    }}
  </style>
</head>
<body style="margin:0 !important; padding:0 !important; background-color:{COLOR_BACKGROUND} !important; color:{COLOR_TEXT_MAIN} !important;">
  <table width="100%" cellpadding="0" cellspacing="0"
         style="background-color:{COLOR_BACKGROUND} !important; color:{COLOR_TEXT_MAIN} !important; min-height:100vh; padding:40px 16px;">
    <tr>
      <td align="center" style="background-color:{COLOR_BACKGROUND} !important;">
        <table width="100%" style="max-width:{EMAIL_MAX_WIDTH}; width:100%;"
               cellpadding="0" cellspacing="0">
          <tr>
            <td class="email-card-td" style="
              background-color:{COLOR_CARD} !important;
              color:{COLOR_TEXT_MAIN} !important;
              border:1px solid {COLOR_CARD_BORDER} !important;
              border-radius:16px;
              padding:40px 40px 32px 40px;
            ">
              {body_html}
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>"""


# ---------------------------------------------------------------------------
# アクションタイプ別 HTML ビルド関数
# ---------------------------------------------------------------------------

def build_signup_email(display_name: str, verification_link: str, lang: str = "en") -> str:
    """ユーザー登録確認メール"""
    c = get_email_content(lang)
    greeting = f"Hi {display_name},<br/><br/>" if display_name else ""
    body = (
        email_header()
        + email_heading(c.SIGNUP_HEADING)
        + email_text(f"{greeting}{c.SIGNUP_BODY}")
        + email_button(c.SIGNUP_BUTTON, verification_link)
        + email_divider()
        + email_text(c.SIGNUP_EXPIRE_NOTE, muted=True)
        + email_fallback_link(verification_link, lang=lang)
        + email_footer(lang=lang)
    )
    return email_wrapper(body)


def build_password_reset_email(display_name: str, reset_link: str, lang: str = "en") -> str:
    """パスワードリセットメール"""
    c = get_email_content(lang)
    greeting = f"Hi {display_name},<br/><br/>" if display_name else ""
    body = (
        email_header()
        + email_heading(c.PASSWORD_RESET_HEADING)
        + email_text(f"{greeting}{c.PASSWORD_RESET_BODY}")
        + email_button(c.PASSWORD_RESET_BUTTON, reset_link)
        + email_divider()
        + email_text(c.PASSWORD_RESET_EXPIRE_NOTE, muted=True)
        + email_fallback_link(reset_link, lang=lang)
        + email_footer(lang=lang)
    )
    return email_wrapper(body)


def build_email_change_email(new_email: str, confirmation_link: str, lang: str = "en") -> str:
    """メールアドレス変更確認メール"""
    c = get_email_content(lang)
    new_email_note = (
        f"{c.EMAIL_CHANGE_NEW_EMAIL_LABEL}: <strong style='color:{COLOR_TEXT_MAIN};'>{new_email}</strong><br/>"
        if new_email
        else ""
    )
    body = (
        email_header()
        + email_heading(c.EMAIL_CHANGE_HEADING)
        + email_text(c.EMAIL_CHANGE_BODY)
        + (email_text(new_email_note, muted=True) if new_email_note else "")
        + email_button(c.EMAIL_CHANGE_BUTTON, confirmation_link)
        + email_divider()
        + email_text(c.EMAIL_CHANGE_EXPIRE_NOTE, muted=True)
        + email_fallback_link(confirmation_link, lang=lang)
        + email_footer(lang=lang)
    )
    return email_wrapper(body)


def build_support_user_ack_email(
    display_name: str,
    ticket_code: str,
    category: str,
    message: str,
    lang: str = "en",
) -> str:
    """お問い合わせ自動受信確認メール（ユーザー向け）"""
    c = get_email_content(lang)
    greeting = f"Hi {display_name},<br/><br/>" if display_name else ""
    formatted_message = message.replace("\n", "<br/>")

    ticket_info = f"""
    <div style="
      background:{COLOR_CARD_BORDER};
      border-radius:12px;
      padding:20px;
      margin:20px 0;
      color:{COLOR_TEXT_MAIN};
      font-family:{FONT_STACK};
      font-size:{FONT_SIZE_BODY};
      line-height:1.6;
    ">
      <p style="margin:0 0 8px 0;"><strong>{c.SUPPORT_ACK_TICKET_CODE_LABEL}:</strong> <span style="color:{COLOR_PRIMARY}; font-weight:700;">{ticket_code}</span></p>
      <p style="margin:0 0 8px 0;"><strong>{c.SUPPORT_ACK_CATEGORY_LABEL}:</strong> {category}</p>
      <p style="margin:0 0 4px 0;"><strong>{c.SUPPORT_ACK_MESSAGE_LABEL}:</strong></p>
      <p style="margin:0; color:{COLOR_TEXT_MUTED}; word-break:break-word;">{formatted_message}</p>
    </div>
    """

    body = (
        email_header(c.SUPPORT_APP_NAME)
        + email_heading(c.SUPPORT_ACK_HEADING)
        + email_text(f"{greeting}{c.SUPPORT_ACK_BODY}")
        + ticket_info
        + email_divider()
        + email_text(c.SUPPORT_ACK_FOOTER_NOTE, muted=True)
        + email_footer(lang=lang)
    )
    return email_wrapper(body)


def build_support_admin_notification_email(
    ticket_code: str,
    user_email: str,
    user_id: str,
    category: str,
    message: str,
    attachments_section_html: str = "",
    device_info_json: str = "",
    lang: str = "en",
) -> str:
    """お問い合わせ受信通知メール（管理者・チーム向け）"""
    c = get_email_content(lang)
    formatted_message = message.replace("\n", "<br/>")

    device_info_block = ""
    if device_info_json:
        device_info_block = f"""
        <p style="margin:16px 0 4px 0;"><strong>Device Info:</strong></p>
        <pre style="
          background:#0D0D14;
          border:1px solid {COLOR_CARD_BORDER};
          border-radius:8px;
          padding:12px;
          color:{COLOR_TEXT_MUTED};
          font-size:12px;
          overflow-x:auto;
        ">{device_info_json}</pre>
        """

    admin_info = f"""
    <div style="
      background:{COLOR_CARD_BORDER};
      border-radius:12px;
      padding:20px;
      margin:20px 0;
      color:{COLOR_TEXT_MAIN};
      font-family:{FONT_STACK};
      font-size:{FONT_SIZE_BODY};
      line-height:1.6;
    ">
      <p style="margin:0 0 8px 0;"><strong>Ticket Code:</strong> <span style="color:{COLOR_PRIMARY}; font-weight:700;">{ticket_code}</span></p>
      <p style="margin:0 0 8px 0;"><strong>User Email:</strong> {user_email}</p>
      <p style="margin:0 0 8px 0;"><strong>User ID:</strong> {user_id}</p>
      <p style="margin:0 0 8px 0;"><strong>Category:</strong> {category}</p>
      <p style="margin:0 0 4px 0;"><strong>Message:</strong></p>
      <p style="margin:0 0 12px 0; color:{COLOR_TEXT_MUTED}; word-break:break-word;">{formatted_message}</p>
      {attachments_section_html}
      {device_info_block}
    </div>
    """

    footer_note = c.SUPPORT_ADMIN_FOOTER_NOTE.format(user_email=user_email)

    body = (
        email_header(c.SUPPORT_DESK_APP_NAME)
        + email_heading(c.SUPPORT_ADMIN_HEADING)
        + email_text(c.SUPPORT_ADMIN_BODY)
        + admin_info
        + email_divider()
        + email_text(footer_note, muted=True)
        + email_footer(lang=lang)
    )
    return email_wrapper(body)

