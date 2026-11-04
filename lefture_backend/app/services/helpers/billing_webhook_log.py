"""課金系Webhook(RevenueCat / Stripe)の受信ログ(public.billing_webhook_log)。

冪等性台帳(revenuecat_webhook_events)とは完全に分離した追記専用ログ。
ここでの書き込み失敗は絶対にWebhook処理自体を止めてはならない — 全関数が
例外を握りつぶしてwarningログだけ残す。
"""

import asyncio
import copy
import logging
import uuid
from datetime import datetime, timezone
from typing import Any, Optional

logger = logging.getLogger(__name__)

TABLE = "billing_webhook_log"

# RevenueCatの予約済みsubscriber attributeのうち個人情報にあたるもの。
# 現状アプリからは設定していないが、将来設定された場合に備えて保存前に落とす。
_RC_PII_ATTRIBUTE_KEYS = {"$email", "$displayName", "$phoneNumber", "$ip"}

# Stripeのdata.objectに載りうる個人情報系フィールド。
_STRIPE_PII_KEYS = {
    "receipt_email", "customer_email", "customer_name", "customer_phone",
    "customer_address", "customer_shipping", "billing_details", "shipping",
    "email", "name", "phone", "address",
}

# ハンドラ戻り値のstatus -> ログのstatus
_RESULT_STATUS_MAP = {
    "success": "processed",
    "ignored": "ignored",
    "error_logged": "error",
    "already_processed": "duplicate",
}


def _as_uuid(value: Any) -> Optional[str]:
    if not isinstance(value, str):
        return None
    try:
        return str(uuid.UUID(value))
    except ValueError:
        return None


def _ms_to_iso(ms: Any) -> Optional[str]:
    if not isinstance(ms, (int, float)):
        return None
    return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).isoformat()


def _str_list(value: Any) -> Optional[list]:
    if isinstance(value, list):
        return [str(v) for v in value]
    return None


def _sanitize_revenuecat(body: dict) -> dict:
    body = copy.deepcopy(body)
    attrs = (body.get("event") or {}).get("subscriber_attributes")
    if isinstance(attrs, dict):
        for k in list(attrs):
            if k in _RC_PII_ATTRIBUTE_KEYS:
                attrs[k] = {"value": "[redacted]"}
    return body


def _strip_keys(obj: Any, keys: set) -> Any:
    if isinstance(obj, dict):
        return {k: ("[redacted]" if k in keys else _strip_keys(v, keys)) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_strip_keys(v, keys) for v in obj]
    return obj


def build_revenuecat_row(body: dict) -> dict:
    """RevenueCat webhook本文からログ行を組み立てる(純粋関数、DBアクセス無し)。"""
    event = body.get("event") or {}
    app_user_id = event.get("app_user_id")
    transferred_to = _str_list(event.get("transferred_to"))
    # TRANSFERにはapp_user_idが無い(webhookは移転先ユーザー向けに送られる)。
    user_id = _as_uuid(app_user_id)
    if user_id is None and transferred_to:
        user_id = next((u for u in map(_as_uuid, transferred_to) if u), None)
    return {
        "source": "revenuecat",
        "event_id": event.get("id"),
        "event_type": event.get("type"),
        "app_user_id": app_user_id,
        "user_id": user_id,
        "original_app_user_id": event.get("original_app_user_id"),
        "aliases": _str_list(event.get("aliases")),
        "transferred_from": _str_list(event.get("transferred_from")),
        "transferred_to": transferred_to,
        "environment": event.get("environment"),
        "store": event.get("store"),
        # main.pyのrevenuecat_webhookと同じ優先順位(実際に照合に使うID)。
        "product_id": event.get("price_id") or event.get("product_id"),
        "expiration_at": _ms_to_iso(event.get("expiration_at_ms")),
        "event_timestamp": _ms_to_iso(event.get("event_timestamp_ms")),
        "raw_payload": _sanitize_revenuecat(body),
    }


def build_stripe_row(event: dict) -> dict:
    """Stripe webhookイベント(dict化済み)からログ行を組み立てる(純粋関数)。"""
    obj = ((event.get("data") or {}).get("object")) or {}
    metadata = obj.get("metadata") or {}
    uid = metadata.get("supabase_user_id") if isinstance(metadata, dict) else None
    created = event.get("created")
    livemode = event.get("livemode")
    return {
        "source": "stripe",
        "event_id": event.get("id"),
        "event_type": event.get("type"),
        "app_user_id": uid,
        "user_id": _as_uuid(uid),
        "environment": None if livemode is None else ("PRODUCTION" if livemode else "SANDBOX"),
        "store": "STRIPE",
        "product_id": metadata.get("stripe_price_id") if isinstance(metadata, dict) else None,
        "event_timestamp": _ms_to_iso(created * 1000) if isinstance(created, (int, float)) else None,
        "raw_payload": _strip_keys(event, _STRIPE_PII_KEYS),
    }


async def _ledger_has(client, event_id: Optional[str]) -> bool:
    """台帳の確認はduplicate判定の補助にすぎないため、失敗してもFalseで続行する。"""
    if not event_id:
        return False
    try:
        res = await asyncio.to_thread(
            lambda: client.table("revenuecat_webhook_events")
                .select("event_id").eq("event_id", event_id).limit(1).execute()
        )
        return bool(res.data)
    except Exception as e:
        logger.warning(f"billing_webhook_log: ledger lookup failed for {event_id}: {e}")
        return False


_ROW_BUILDERS = {
    "revenuecat": build_revenuecat_row,
    "stripe": build_stripe_row,
}


async def record_received(client, source: str, payload: Any) -> tuple[Optional[int], bool]:
    """受信直後に1行挿入する。戻り値は (ログ行id, 受信時点で台帳に既に存在したか)。

    台帳チェックは「処理は成功扱いだが実際はSQL関数側で重複としてスキップされた」
    配信をduplicateとして区別するためだけのもので、処理の分岐には使わない。
    payloadが想定外の形(dict以外等)でも、行の組み立てを含めて例外は外に出さない。
    """
    row: dict = {}
    try:
        if isinstance(payload, dict):
            row = _ROW_BUILDERS[source](payload)
        else:
            row = {"source": source, "raw_payload": {"_non_object_payload": payload}}
        already = await _ledger_has(client, row.get("event_id"))
        res = await asyncio.to_thread(
            lambda: client.table(TABLE).insert(row).execute()
        )
        log_id = res.data[0]["id"] if res.data else None
        return log_id, already
    except Exception as e:
        logger.warning(f"billing_webhook_log: failed to record received event {row.get('event_id')}: {e}")
        return None, False


async def record_outcome(
    client,
    log_id: Optional[int],
    *,
    result: Optional[dict] = None,
    error: Optional[str] = None,
    was_in_ledger: bool = False,
) -> None:
    """処理結果でログ行を更新する。log_idがNone(受信記録に失敗)なら何もしない。"""
    if log_id is None:
        return
    if error is not None:
        status = "error"
    else:
        status = _RESULT_STATUS_MAP.get((result or {}).get("status"), "processed")
        if status == "processed" and was_in_ledger:
            status = "duplicate"
    update = {
        "status": status,
        "result": result,
        "error": error,
        "processed_at": datetime.now(timezone.utc).isoformat(),
    }
    try:
        await asyncio.to_thread(
            lambda: client.table(TABLE).update(update).eq("id", log_id).execute()
        )
    except Exception as e:
        logger.warning(f"billing_webhook_log: failed to record outcome for log {log_id}: {e}")
