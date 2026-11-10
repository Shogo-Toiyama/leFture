"""RevenueCat の実際の契約状態と DB(user_subscription_mappings)を突き合わせて直す。

webhookだけでは救えないケースのための補完経路:
  - アカウント作成前に匿名IDで成立した購入(後でaliasされるだけで新イベントが来ない)
  - webhookの取りこぼし・恒久エラー(EXPIRATION未着でプランが残り続ける等)

方針(webhookと同じSQL関数を使い、新しい付与ロジックは持たない):
  - RevenueCatで有効なサブスクがDBに無い/期間が古い → grant_store_subscription_credits
    event_idは「RCのサブスクID + その期間の開始時刻」= 1請求期間につき最大1回。
    同じ期間を何度同期しても二重付与されない。
  - RevenueCatで有効なサブスクが無く、DBのプランが期限切れのまま6時間以上残っている
    → expire_store_subscription(DB上の期限がまだ先のもの=手動付与等には触れない)
  - 判断材料が不完全(APIエラー・ページ取り切れず・商品IDを変換できない)なら何もしない

★ 購入直後10分以内のサブスクは、webhookが先に届くのを待って何もしない
  (同じ期間をwebhookとこちらで別event_idとして二重処理しないため)。
"""

import asyncio
import logging
import time
from datetime import datetime, timezone, timedelta
from typing import Any, Optional

from app.services.helpers import revenuecat_api

logger = logging.getLogger(__name__)

IN_SYNC_TOLERANCE = timedelta(hours=1)
RECENT_PURCHASE_GRACE = timedelta(minutes=10)
STALE_EXPIRE_AFTER = timedelta(hours=6)
SUPPORTED_RC_STORES = {"app_store", "stripe"}

# /billing/summary はアプリからほぼ常時呼ばれるため、同じインスタンス内では
# DBの間引きチェック(claim_store_sync_slot)自体も一定時間スキップする。
_LOCAL_CHECKED_AT: dict[str, float] = {}
_LOCAL_SKIP_SECONDS = 600


def _ms_to_dt(ms: Any) -> Optional[datetime]:
    if not isinstance(ms, (int, float)):
        return None
    return datetime.fromtimestamp(ms / 1000, tz=timezone.utc)


def _parse_ts(value: Any) -> Optional[datetime]:
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def plans_by_store_id(plans: list) -> dict:
    """store_product_id / stripe_price_id / stripe_product_id -> plan(課金プランのみ)。"""
    out = {}
    for p in plans:
        if p.get("claim_mode") != "store_purchase":
            continue
        for key in ("store_product_id", "stripe_price_id", "stripe_product_id"):
            if p.get(key):
                out[p[key]] = p
    return out


def decide(
    subs: Optional[list],
    store_ids: dict,
    plans: list,
    db_mapping: Optional[dict],
    now: datetime,
) -> dict:
    """純粋関数。RevenueCatのサブスク一覧とDBのactiveな課金プランから、取るべき行動を返す。

    subs:       fetch_customer_subscriptions() の結果(None = 不完全)
    store_ids:  RevenueCat内部product_id -> ストア商品ID(変換できなければ値がNone)
    db_mapping: {"id","plan_id","current_period_end"} DBのactiveな store_purchase mapping(無ければNone)
    """
    if subs is None:
        return {"action": "none", "reason": "incomplete_subscription_list"}

    by_store = plans_by_store_id(plans)
    candidates, unmapped = [], []
    for s in subs:
        end = _ms_to_dt(s.get("current_period_ends_at"))
        # gives_accessがtrueでも期間が過ぎているものはRevenueCat側の情報が古い
        # (Stripe sandboxで実例あり)ので有効とみなさない。
        if not s.get("gives_access") or end is None or end <= now:
            continue
        if s.get("store") not in SUPPORTED_RC_STORES:
            continue
        store_id = store_ids.get(s.get("product_id"))
        plan = by_store.get(store_id) if store_id else None
        if plan is None:
            unmapped.append(s.get("product_id"))
            continue
        candidates.append(((plan.get("tier_level") or 0), end, s, plan, store_id))

    db_plan_id = (db_mapping or {}).get("plan_id")
    db_end = _parse_ts((db_mapping or {}).get("current_period_end"))

    if unmapped:
        # 有効な契約の一部をプランに変換できない = 全体像が分からないので触らない。
        return {"action": "none", "reason": "unmapped_active_products", "unmapped": unmapped}

    if candidates:
        _, end, sub, plan, store_id = max(candidates, key=lambda c: (c[0], c[1]))
        start = _ms_to_dt(sub.get("current_period_starts_at")) or now
        base = {
            "plan_id": plan["id"],
            "plan_name": plan.get("name"),
            "product_id": store_id,
            "period_end": end.isoformat(),
            "rc_subscription_id": sub.get("id"),
            "environment": sub.get("environment"),
            "store": sub.get("store"),
        }
        if db_plan_id == plan["id"] and db_end is not None and db_end >= end - IN_SYNC_TOLERANCE:
            return {"action": "none", "reason": "in_sync", **base}
        if now - start < RECENT_PURCHASE_GRACE:
            return {"action": "none", "reason": "recent_purchase_wait_for_webhook", **base}
        start_ms = int(sub.get("current_period_starts_at") or 0)
        return {
            "action": "grant",
            "reason": "missed_renewal" if db_plan_id == plan["id"] else "missing_plan",
            "event_type": "RENEWAL" if db_plan_id == plan["id"] else "INITIAL_PURCHASE",
            "event_id": f"reconcile:{sub.get('id')}:{start_ms}",
            "auto_renew_disabled": sub.get("auto_renewal_status") == "will_not_renew",
            "cancel_event_id": f"reconcile-cancel:{sub.get('id')}:{start_ms}",
            **base,
        }

    if db_mapping and db_end is not None and db_end < now - STALE_EXPIRE_AFTER:
        return {
            "action": "expire",
            "reason": "stale_plan_without_active_subscription",
            "plan_id": db_plan_id,
            "event_id": f"reconcile-expire:{db_mapping.get('id')}:{db_end.isoformat()}",
            "db_period_end": db_end.isoformat(),
        }
    return {"action": "none", "reason": "no_active_subscription" if not db_mapping else "db_plan_not_expired_yet"}


# ----------------------------------------------------------------------------- DB/IO


async def _claim_slot(admin_client, user_id: str, min_interval_seconds: int) -> bool:
    res = await asyncio.to_thread(
        lambda: admin_client.rpc("claim_store_sync_slot", {
            "p_user_id": user_id, "p_min_interval_seconds": min_interval_seconds,
        }).execute()
    )
    return bool(res.data)


async def _load_plans(admin_client) -> list:
    res = await asyncio.to_thread(
        lambda: admin_client.table("subscription_plans")
            .select("id, name, claim_mode, tier_level, store_product_id, stripe_price_id, stripe_product_id")
            .execute()
    )
    return res.data or []


async def _load_db_mapping(admin_client, user_id: str) -> Optional[dict]:
    res = await asyncio.to_thread(
        lambda: admin_client.table("user_subscription_mappings")
            .select("id, plan_id, current_period_end, subscription_plans!user_subscription_mappings_plan_id_fkey!inner(claim_mode)")
            .eq("user_id", user_id)
            .eq("status", "active")
            .eq("subscription_plans.claim_mode", "store_purchase")
            .order("current_period_end", desc=True)
            .limit(1)
            .execute()
    )
    rows = res.data or []
    return rows[0] if rows else None


async def _record(admin_client, user_id: str, result: dict, error: Optional[str]) -> None:
    try:
        await asyncio.to_thread(
            lambda: admin_client.table("store_subscription_sync_state").update({
                "result": result, "error": error,
            }).eq("user_id", user_id).execute()
        )
    except Exception as e:
        logger.warning(f"store reconcile: failed to record state for {user_id}: {e}")


async def _log_action(admin_client, user_id: str, decision: dict, status: str, error: Optional[str]) -> None:
    """DBを変更した場合だけ billing_webhook_log に1行残す(source='reconcile')。"""
    try:
        await asyncio.to_thread(
            lambda: admin_client.table("billing_webhook_log").insert({
                "source": "reconcile",
                "event_id": decision.get("event_id"),
                "event_type": f"RECONCILE_{decision['action'].upper()}",
                "app_user_id": user_id,
                "user_id": user_id,
                "environment": (decision.get("environment") or "").upper() or None,
                "store": (decision.get("store") or "").upper() or None,
                "product_id": decision.get("product_id"),
                "expiration_at": decision.get("period_end"),
                "raw_payload": decision,
                "status": status,
                "error": error,
                "processed_at": datetime.now(timezone.utc).isoformat(),
            }).execute()
        )
    except Exception as e:
        logger.warning(f"store reconcile: failed to log action for {user_id}: {e}")


async def _apply(admin_client, user_id: str, decision: dict) -> None:
    if decision["action"] == "grant":
        await asyncio.to_thread(
            lambda: admin_client.rpc("grant_store_subscription_credits", {
                "p_user_id": user_id,
                "p_event_id": decision["event_id"],
                "p_event_type": decision["event_type"],
                "p_product_id": decision["product_id"],
                "p_period_end": decision["period_end"],
            }).execute()
        )
        if decision.get("auto_renew_disabled") and decision.get("store") == "app_store":
            await asyncio.to_thread(
                lambda: admin_client.rpc("mark_apple_subscription_auto_renew_disabled", {
                    "p_user_id": user_id,
                    "p_event_id": decision["cancel_event_id"],
                    "p_product_id": decision["product_id"],
                }).execute()
            )
    elif decision["action"] == "expire":
        plan_res = await asyncio.to_thread(
            lambda: admin_client.table("subscription_plans")
                .select("store_product_id, stripe_price_id")
                .eq("id", decision["plan_id"]).single().execute()
        )
        plan = plan_res.data or {}
        product_id = plan.get("store_product_id") or plan.get("stripe_price_id")
        await asyncio.to_thread(
            lambda: admin_client.rpc("expire_store_subscription", {
                "p_user_id": user_id,
                "p_event_id": decision["event_id"],
                "p_product_id": product_id,
            }).execute()
        )


async def reconcile_user(
    admin_client,
    user_id: str,
    *,
    min_interval_seconds: int,
    reason: str,
    use_local_skip: bool = False,
) -> dict:
    """1ユーザー分の突き合わせ。例外は外に出さず結果dictで返す。"""
    if not revenuecat_api.is_configured():
        return {"action": "none", "reason": "revenuecat_api_not_configured"}

    if use_local_skip:
        last = _LOCAL_CHECKED_AT.get(user_id)
        if last and time.monotonic() - last < _LOCAL_SKIP_SECONDS:
            return {"action": "none", "reason": "local_throttle"}
        _LOCAL_CHECKED_AT[user_id] = time.monotonic()

    try:
        if not await _claim_slot(admin_client, user_id, min_interval_seconds):
            return {"action": "none", "reason": "throttled"}
    except Exception as e:
        logger.warning(f"store reconcile: claim failed for {user_id}: {e}")
        return {"action": "none", "reason": "claim_failed"}

    decision: dict = {"action": "none", "reason": "unknown"}
    try:
        subs = await revenuecat_api.fetch_customer_subscriptions(user_id)
        store_ids = {}
        for s in subs or []:
            pid = s.get("product_id")
            if pid and pid not in store_ids and s.get("gives_access"):
                store_ids[pid] = await revenuecat_api.get_store_identifier(pid)
        plans = await _load_plans(admin_client)
        db_mapping = await _load_db_mapping(admin_client, user_id)
        decision = decide(subs, store_ids, plans, db_mapping, datetime.now(timezone.utc))
        decision["trigger"] = reason
        if decision["action"] != "none":
            try:
                await _apply(admin_client, user_id, decision)
            except Exception as e:
                await _log_action(admin_client, user_id, decision, "error", f"{type(e).__name__}: {e}")
                raise
            await _log_action(admin_client, user_id, decision, "processed", None)
            logger.info(f"store reconcile {user_id}: {decision['action']} ({decision['reason']}) plan={decision.get('plan_id')}")
        await _record(admin_client, user_id, decision, None)
        return decision
    except Exception as e:
        err = f"{type(e).__name__}: {e}"
        logger.warning(f"store reconcile failed for {user_id}: {err}")
        await _record(admin_client, user_id, decision, err)
        return {"action": "none", "reason": "error", "error": err}
