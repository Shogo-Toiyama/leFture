import asyncio

import firebase_admin
from firebase_admin import messaging

from app.core.supabase import get_supabase_client

# Cloud Run実行サービスアカウントのADC (Application Default Credentials) で
# 初期化する。同一GCPプロジェクトにFirebaseを追加済みのため、明示的な
# サービスアカウントJSONは不要。
if not firebase_admin._apps:
    firebase_admin.initialize_app()


def _get_device_tokens_sync(user_id: str) -> list[str]:
    supabase = get_supabase_client()
    res = supabase.table("user_devices").select("device_token").eq("user_id", user_id).execute()
    return [row["device_token"] for row in (res.data or [])]


def _delete_device_token_sync(device_token: str) -> None:
    supabase = get_supabase_client()
    supabase.table("user_devices").delete().eq("device_token", device_token).execute()


async def send_push_notification(user_id: str, title: str, body: str, data: dict | None = None) -> dict:
    """
    指定ユーザーの全登録端末にFCM通知を送信する。
    無効化済み(アンインストール等)のトークンはUNREGISTEREDエラーとして
    返ってくるため、その場でuser_devicesから削除しておく。
    """
    tokens = await asyncio.to_thread(_get_device_tokens_sync, user_id)
    if not tokens:
        return {"success": True, "sent": 0, "failed": 0}

    message = messaging.MulticastMessage(
        notification=messaging.Notification(title=title, body=body),
        data={k: str(v) for k, v in (data or {}).items()},
        tokens=tokens,
    )

    response = await asyncio.to_thread(messaging.send_each_for_multicast, message)

    if response.failure_count:
        stale_tokens = [
            tokens[i]
            for i, r in enumerate(response.responses)
            if not r.success and isinstance(r.exception, messaging.UnregisteredError)
        ]
        for stale_token in stale_tokens:
            await asyncio.to_thread(_delete_device_token_sync, stale_token)

    return {"success": True, "sent": response.success_count, "failed": response.failure_count}
