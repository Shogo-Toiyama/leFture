import asyncio
import os
from typing import Optional

import resend

from app.services.email_template import (
    build_email_change_email,
    build_password_reset_email,
    build_signup_email,
)

RESEND_API_KEY = os.getenv("RESEND_API_KEY")
RESEND_FROM_ADDRESS = os.getenv("RESEND_FROM_ADDRESS", "hello@lefture.com")

resend.api_key = RESEND_API_KEY


async def send_email(
    to: str,
    subject: str,
    html: str,
    reply_to: Optional[str] = None,
) -> dict:
    """
    Resend を使ってメールを送信する。
    失敗時は resend.exceptions.ResendError 系の例外を発生させ、呼び出し元で処理する。
    """
    if not RESEND_API_KEY:
        raise RuntimeError("RESEND_API_KEY is not set")

    params: resend.Emails.SendParams = {
        "from": RESEND_FROM_ADDRESS,
        "to": to,
        "subject": subject,
        "html": html,
    }
    if reply_to:
        params["reply_to"] = reply_to

    # resend.Emails.send はブロッキング呼び出しのため、イベントループを塞がないようスレッドに逃がす
    email = await asyncio.to_thread(resend.Emails.send, params)
    return {"success": True, "message_id": email["id"]}


async def send_verification_email(
    to: str,
    verification_link: str,
    display_name: str = "",
) -> dict:
    """ユーザー登録確認メール"""
    html = build_signup_email(display_name, verification_link)
    return await send_email(to, "leFture - Verify Email Address", html)


async def send_password_reset_email(
    to: str,
    reset_link: str,
    display_name: str = "",
) -> dict:
    """パスワードリセットメール"""
    html = build_password_reset_email(display_name, reset_link)
    return await send_email(to, "leFture - Reset Your Password", html)


async def send_email_change_email(
    to: str,
    confirmation_link: str,
    new_email: str = "",
) -> dict:
    """メールアドレス変更確認メール"""
    html = build_email_change_email(new_email, confirmation_link)
    return await send_email(to, "leFture - Confirm Email Address Change", html)


async def send_important_notification(
    to: str, subject: str, html: str
) -> dict:
    """汎用通知メール（任意の HTML を直接指定）"""
    return await send_email(to, subject, html)
