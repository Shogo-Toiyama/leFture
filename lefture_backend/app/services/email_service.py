import asyncio
import logging
import os
from typing import Optional

import httpx
import resend

from app.services.email_content import get_email_content
from app.services.email_template import (
    build_email_change_email,
    build_password_reset_email,
    build_signup_email,
)

logger = logging.getLogger(__name__)

# Cloudflare Email Worker 設定
EMAIL_WORKER_URL = os.getenv("EMAIL_WORKER_URL")
EMAIL_WORKER_SECRET = os.getenv("EMAIL_WORKER_SECRET")

# 送信元情報（Cloudflare / Resend 共通）
DEFAULT_FROM_ADDRESS = os.getenv(
    "EMAIL_FROM_ADDRESS", os.getenv("RESEND_FROM_ADDRESS", "hello@lefture.com")
)
DEFAULT_FROM_NAME = os.getenv(
    "EMAIL_FROM_NAME", os.getenv("RESEND_FROM_NAME", "leFture")
)

# 従来の Resend 設定（フォールバック用）
RESEND_API_KEY = os.getenv("RESEND_API_KEY")
if RESEND_API_KEY:
    resend.api_key = RESEND_API_KEY


async def send_email(
    to: str,
    subject: str,
    html: str,
    reply_to: Optional[str] = None,
    from_address: Optional[str] = None,
    from_name: Optional[str] = None,
) -> dict:
    """
    メールを送信する。
    1. EMAIL_WORKER_URL と EMAIL_WORKER_SECRET が設定されていれば Cloudflare Email Worker 経由で送信
    2. 未設定の場合は従来の Resend SDK を使ってフォールバック送信する
    """
    sender_addr = from_address or DEFAULT_FROM_ADDRESS
    sender_name = from_name or DEFAULT_FROM_NAME

    # 1. Cloudflare Email Worker が設定されている場合
    if EMAIL_WORKER_URL and EMAIL_WORKER_SECRET:
        try:
            # エンドポイントのパス補正（/send が含まれていなければ付与）
            url = EMAIL_WORKER_URL.rstrip("/")
            if not url.endswith("/send"):
                url += "/send"

            payload = {
                "to": to,
                "subject": subject,
                "html": html,
                "from_name": sender_name,
                "from_address": sender_addr,
            }
            if reply_to:
                payload["reply_to"] = reply_to

            headers = {
                "Authorization": f"Bearer {EMAIL_WORKER_SECRET}",
                "Content-Type": "application/json",
            }

            async with httpx.AsyncClient(timeout=15.0) as client:
                res = await client.post(url, json=payload, headers=headers)
                res.raise_for_status()
                data = res.json()
                logger.info("Email sent via Cloudflare Email Worker: to=%s, subject=%s", to, subject)
                return {"success": True, "provider": "cloudflare", "data": data}
        except Exception as e:
            logger.error("Failed to send email via Cloudflare Email Worker: %s", e)
            # Resend API Key がある場合はフォールバックを試みる
            if not RESEND_API_KEY:
                raise

    # 2. Resend フォールバック
    if not RESEND_API_KEY:
        raise RuntimeError("Neither EMAIL_WORKER nor RESEND_API_KEY is configured")

    params: resend.Emails.SendParams = {
        "from": f"{sender_name} <{sender_addr}>",
        "to": to,
        "subject": subject,
        "html": html,
    }
    if reply_to:
        params["reply_to"] = reply_to

    email = await asyncio.to_thread(resend.Emails.send, params)
    logger.info("Email sent via Resend: to=%s, id=%s", to, email.get("id"))
    return {"success": True, "provider": "resend", "message_id": email["id"]}


async def send_verification_email(
    to: str,
    verification_link: str,
    display_name: str = "",
    lang: str = "en",
) -> dict:
    """ユーザー登録確認メール"""
    c = get_email_content(lang)
    html = build_signup_email(display_name, verification_link, lang=lang)
    return await send_email(to, c.SIGNUP_SUBJECT, html)


async def send_password_reset_email(
    to: str,
    reset_link: str,
    display_name: str = "",
    lang: str = "en",
) -> dict:
    """パスワードリセットメール"""
    c = get_email_content(lang)
    html = build_password_reset_email(display_name, reset_link, lang=lang)
    return await send_email(to, c.PASSWORD_RESET_SUBJECT, html)


async def send_email_change_email(
    to: str,
    confirmation_link: str,
    new_email: str = "",
    lang: str = "en",
) -> dict:
    """メールアドレス変更確認メール"""
    c = get_email_content(lang)
    html = build_email_change_email(new_email, confirmation_link, lang=lang)
    return await send_email(to, c.EMAIL_CHANGE_SUBJECT, html)


async def send_important_notification(
    to: str, subject: str, html: str
) -> dict:
    """汎用通知メール（任意の HTML を直接指定）"""
    return await send_email(to, subject, html)
