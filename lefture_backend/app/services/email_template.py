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
             style="
               display:inline-block;
               padding:14px 36px;
               background:{COLOR_PRIMARY};
               color:{COLOR_BUTTON_TEXT};
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


def email_fallback_link(url: str) -> str:
    """ボタンが機能しない場合のフォールバックリンクテキスト"""
    return f"""
    <p style="
      margin:0 0 8px 0;
      font-size:{FONT_SIZE_SMALL};
      color:{COLOR_TEXT_MUTED};
      font-family:{FONT_STACK};
      line-height:1.5;
    ">
      ボタンが機能しない場合は、以下のリンクをブラウザにコピーして開いてください：
    </p>
    <p style="
      margin:0 0 16px 0;
      font-size:{FONT_SIZE_SMALL};
      color:{COLOR_TEXT_MUTED};
      font-family:{FONT_STACK};
      word-break:break-all;
    ">
      <a href="{url}" style="color:{COLOR_PRIMARY};">{url}</a>
    </p>
    """


def email_footer() -> str:
    """フッター（免責・著作権）"""
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
            このメールに心当たりがない場合は、無視していただいて問題ありません。
          </p>
          <p style="
            margin:0;
            font-size:{FONT_SIZE_SMALL};
            color:{COLOR_TEXT_MUTED};
            font-family:{FONT_STACK};
          ">
            &copy; 2025 leFture. All rights reserved.
          </p>
        </td>
      </tr>
    </table>
    """


def email_wrapper(body_html: str) -> str:
    """
    全体のレイアウトラッパー。
    DOCTYPE + meta + 背景 + カードコンテナを提供する。
    body_html にはコンポーネントを組み合わせた HTML を渡す。
    """
    return f"""<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>leFture</title>
  <style>
    body {{
      margin: 0;
      padding: 0;
      background-color: {COLOR_BACKGROUND};
      font-family: {FONT_STACK};
    }}
    a {{
      color: {COLOR_PRIMARY};
    }}
  </style>
</head>
<body>
  <table width="100%" cellpadding="0" cellspacing="0"
         style="background-color:{COLOR_BACKGROUND}; min-height:100vh; padding:40px 16px;">
    <tr>
      <td align="center">
        <table width="100%" style="max-width:{EMAIL_MAX_WIDTH}; width:100%;"
               cellpadding="0" cellspacing="0">
          <tr>
            <td style="
              background:{COLOR_CARD};
              border:1px solid {COLOR_CARD_BORDER};
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

def build_signup_email(display_name: str, verification_link: str) -> str:
    """ユーザー登録確認メール"""
    greeting = f"{display_name} さん、" if display_name else ""
    body = (
        email_header()
        + email_heading("leFture へようこそ！")
        + email_text(
            f"{greeting}アカウントの登録ありがとうございます。"
            "以下のボタンをクリックして、メールアドレスを確認してください。"
        )
        + email_button("メールアドレスを確認する", verification_link)
        + email_divider()
        + email_text("このリンクは <strong>24時間</strong> 有効です。", muted=True)
        + email_fallback_link(verification_link)
        + email_footer()
    )
    return email_wrapper(body)


def build_password_reset_email(display_name: str, reset_link: str) -> str:
    """パスワードリセットメール"""
    greeting = f"{display_name} さん、" if display_name else ""
    body = (
        email_header()
        + email_heading("パスワードをリセット")
        + email_text(
            f"{greeting}パスワードのリセットがリクエストされました。"
            "以下のボタンをクリックして、新しいパスワードを設定してください。"
        )
        + email_button("パスワードをリセットする", reset_link)
        + email_divider()
        + email_text(
            "このリンクは <strong>1時間</strong> 有効です。"
            "このメールに心当たりがない場合は、安全のためリンクを無視してください。",
            muted=True,
        )
        + email_fallback_link(reset_link)
        + email_footer()
    )
    return email_wrapper(body)


def build_email_change_email(new_email: str, confirmation_link: str) -> str:
    """メールアドレス変更確認メール"""
    new_email_note = (
        f"変更後のアドレス: <strong style='color:{COLOR_TEXT_MAIN};'>{new_email}</strong><br/>"
        if new_email
        else ""
    )
    body = (
        email_header()
        + email_heading("メールアドレスの変更を確認")
        + email_text(
            "leFture アカウントのメールアドレス変更がリクエストされました。"
            "以下のボタンをクリックして変更を確定してください。"
        )
        + email_text(new_email_note, muted=True)
        + email_button("メールアドレスの変更を確認する", confirmation_link)
        + email_divider()
        + email_text(
            "このリンクは <strong>24時間</strong> 有効です。"
            "このリクエストに心当たりがない場合は、リンクを無視してください。",
            muted=True,
        )
        + email_fallback_link(confirmation_link)
        + email_footer()
    )
    return email_wrapper(body)
