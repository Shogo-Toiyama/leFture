"""billing_webhook_log helper の dry-run テスト(外部API・本番DBへの書き込み無し)。

- 本番のhelperモジュール(lefture_backend/app/services/helpers/billing_webhook_log.py)
  をそのままimportする。
- Supabaseクライアントはインメモリのモックに差し替え、挿入/更新された行を検証する。
- ペイロードは、本番の該当ユーザー(lefture.app@gmail.com)に実際に起きた事象
  (TRANSFER / RENEWAL / EXPIRATION)と、RevenueCat公式ドキュメントのフィールド定義
  (event-types-and-fields)に沿って組み立てたもの。
実行: .venv/bin/python run_test.py
"""
import asyncio
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "lefture_backend"))
from app.services.helpers import billing_webhook_log as bwl  # noqa: E402

import stripe  # noqa: E402


class _Res:
    def __init__(self, data):
        self.data = data


class _Query:
    def __init__(self, db, table):
        self.db, self.table, self.op, self.payload, self.filters = db, table, "select", None, []

    def select(self, *_):
        self.op = "select"; return self

    def insert(self, row):
        self.op, self.payload = "insert", row; return self

    def update(self, row):
        self.op, self.payload = "update", row; return self

    def eq(self, k, v):
        self.filters.append((k, v)); return self

    def limit(self, _):
        return self

    def execute(self):
        if self.db.fail_tables and self.table in self.db.fail_tables:
            raise RuntimeError(f"simulated failure on {self.table}")
        rows = self.db.tables.setdefault(self.table, [])
        if self.op == "insert":
            row = dict(self.payload, id=len(rows) + 1)
            json.dumps(row)  # PostgRESTへ送れる(JSONシリアライズ可能)ことを保証
            rows.append(row); return _Res([row])
        match = [r for r in rows if all(r.get(k) == v for k, v in self.filters)]
        if self.op == "update":
            json.dumps(self.payload)
            for r in match:
                r.update(self.payload)
        return _Res(match)


class MockClient:
    def __init__(self, ledger=(), fail_tables=()):
        self.tables = {"revenuecat_webhook_events": [{"event_id": e} for e in ledger]}
        self.fail_tables = set(fail_tables)

    def table(self, name):
        return _Query(self, name)


UID_LEFTURE = "5be0566d-9b7a-499f-b7d2-f1c736fd5082"
UID_SHOGO = "a0368beb-867a-48ce-a9a1-c1421a72fc65"


def rc_body(**event):
    return {"api_version": "1.0", "event": {"event_timestamp_ms": 1762239028000, "app_id": "app1", **event}}


CASES = []


def case(fn):
    CASES.append(fn); return fn


@case
async def renewal_processed():
    c = MockClient()
    body = rc_body(id="EVT-RENEW", type="RENEWAL", app_user_id=UID_SHOGO, original_app_user_id="$RCAnonymousID:07a6",
                   aliases=["$RCAnonymousID:07a6", UID_SHOGO], environment="SANDBOX", store="APP_STORE",
                   product_id="com.lefture.app.sub.premium", expiration_at_ms=1762326315000,
                   subscriber_attributes={"$email": {"value": "x@y.z", "updated_at_ms": 1}, "plan": {"value": "max"}})
    log_id, was = await bwl.record_received(c, "revenuecat", body)
    # SQL関数が台帳へ挿入したことを模擬
    c.tables["revenuecat_webhook_events"].append({"event_id": "EVT-RENEW"})
    await bwl.record_outcome(c, log_id, result={"status": "success", "event_type": "RENEWAL"}, was_in_ledger=was)
    r = c.tables["billing_webhook_log"][0]
    assert r["status"] == "processed", r["status"]
    assert r["user_id"] == UID_SHOGO and r["environment"] == "SANDBOX" and r["store"] == "APP_STORE"
    assert r["expiration_at"].startswith("2025-11-05") or r["expiration_at"].startswith("20")
    assert r["raw_payload"]["event"]["subscriber_attributes"]["$email"] == {"value": "[redacted]"}
    assert r["raw_payload"]["event"]["subscriber_attributes"]["plan"]["value"] == "max"
    assert body["event"]["subscriber_attributes"]["$email"]["value"] == "x@y.z", "元のbodyを書き換えてはいけない"
    assert r["processed_at"]
    return r


@case
async def retry_after_success_is_duplicate():
    c = MockClient(ledger=["EVT-RENEW"])
    log_id, was = await bwl.record_received(c, "revenuecat", rc_body(id="EVT-RENEW", type="RENEWAL", app_user_id=UID_SHOGO))
    await bwl.record_outcome(c, log_id, result={"status": "success"}, was_in_ledger=was)
    assert c.tables["billing_webhook_log"][0]["status"] == "duplicate"


@case
async def transfer_is_logged_with_destination_user():
    c = MockClient()
    body = rc_body(id="EVT-TRANSFER", type="TRANSFER", environment="SANDBOX", store="APP_STORE",
                   transferred_from=["$RCAnonymousID:d412", UID_LEFTURE],
                   transferred_to=["$RCAnonymousID:07a6", UID_SHOGO])
    log_id, was = await bwl.record_received(c, "revenuecat", body)
    await bwl.record_outcome(c, log_id, result={"status": "ignored", "event_type": "TRANSFER"}, was_in_ledger=was)
    r = c.tables["billing_webhook_log"][0]
    assert r["status"] == "ignored" and r["app_user_id"] is None
    assert r["user_id"] == UID_SHOGO, "TRANSFERは移転先のuuidをuser_idにする"
    assert UID_LEFTURE in r["transferred_from"] and UID_SHOGO in r["transferred_to"]
    return r


@case
async def anonymous_id_does_not_break():
    c = MockClient()
    log_id, _ = await bwl.record_received(c, "revenuecat", rc_body(id="EVT-ANON", type="INITIAL_PURCHASE", app_user_id="$RCAnonymousID:abc"))
    await bwl.record_outcome(c, log_id, error="DataError: invalid input syntax for type uuid")
    r = c.tables["billing_webhook_log"][0]
    assert r["user_id"] is None and r["app_user_id"] == "$RCAnonymousID:abc" and r["status"] == "error" and "uuid" in r["error"]


@case
async def stripe_price_id_preferred():
    c = MockClient()
    await bwl.record_received(c, "revenuecat", rc_body(id="E", type="RENEWAL", app_user_id=UID_LEFTURE, store="STRIPE",
                                                        product_id="prod_VH82Av0m0a219M", price_id="price_1UGZmQQylf53GNnc2CM0H4TL"))
    assert c.tables["billing_webhook_log"][0]["product_id"] == "price_1UGZmQQylf53GNnc2CM0H4TL"


@case
async def unknown_product_error_logged():
    c = MockClient()
    log_id, was = await bwl.record_received(c, "revenuecat", rc_body(id="E2", type="RENEWAL", app_user_id=UID_LEFTURE))
    await bwl.record_outcome(c, log_id, result={"status": "error_logged", "reason": "unknown_product"}, was_in_ledger=was)
    assert c.tables["billing_webhook_log"][0]["status"] == "error"


@case
async def malformed_payloads_do_not_raise():
    c = MockClient()
    for p in [[], "str", None, {}, {"event": None}, {"event": {"transferred_to": "notalist", "expiration_at_ms": "x"}}]:
        log_id, _ = await bwl.record_received(c, "revenuecat", p)
        await bwl.record_outcome(c, log_id, result={"status": "ignored"})
    assert len(c.tables["billing_webhook_log"]) == 6


@case
async def db_failure_is_swallowed():
    c = MockClient(fail_tables=["billing_webhook_log", "revenuecat_webhook_events"])
    log_id, was = await bwl.record_received(c, "revenuecat", rc_body(id="E3", type="RENEWAL"))
    assert log_id is None and was is False
    # 台帳の確認だけが失敗しても、ログ行は挿入される
    c2 = MockClient(fail_tables=["revenuecat_webhook_events"])
    log_id2, was2 = await bwl.record_received(c2, "revenuecat", rc_body(id="E4", type="RENEWAL"))
    assert log_id2 == 1 and was2 is False
    await bwl.record_outcome(c, log_id, result={"status": "success"})  # 何もしない
    await bwl.record_outcome(c, 1, result={"status": "success"})       # update失敗も握りつぶす


@case
async def stripe_event_real_sdk_object():
    c = MockClient()
    ev = stripe.Event.construct_from({
        "id": "evt_1", "type": "payment_intent.succeeded", "livemode": True, "created": 1762239028,
        "data": {"object": {"id": "pi_1", "receipt_email": "a@b.c",
                            "metadata": {"supabase_user_id": UID_LEFTURE, "stripe_price_id": "price_x"},
                            "charges": {"data": [{"billing_details": {"email": "a@b.c", "name": "N"}}]}}},
    }, "sk_test_dummy")
    log_id, was = await bwl.record_received(c, "stripe", ev.to_dict())  # main.pyと同じ変換
    await bwl.record_outcome(c, log_id, result={"status": "success"}, was_in_ledger=was)
    r = c.tables["billing_webhook_log"][0]
    assert r["source"] == "stripe" and r["environment"] == "PRODUCTION" and r["user_id"] == UID_LEFTURE
    assert r["product_id"] == "price_x" and r["event_timestamp"].startswith("2025-11-04")
    s = json.dumps(r["raw_payload"])
    assert "a@b.c" not in s and '"N"' not in s, s
    return r


async def main():
    out, ok = [], True
    for fn in CASES:
        t0 = time.perf_counter()
        try:
            sample = await fn()
            out.append({"case": fn.__name__, "ok": True, "ms": round((time.perf_counter() - t0) * 1000, 2), "sample_row": sample})
            print(f"PASS {fn.__name__}")
        except Exception as e:
            ok = False
            out.append({"case": fn.__name__, "ok": False, "error": repr(e)})
            print(f"FAIL {fn.__name__}: {e!r}")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = Path(__file__).parent / "results" / f"{stamp}_dry_run.json"
    path.write_text(json.dumps({"run_at": stamp, "external_api_calls": 0, "cost_usd": 0, "all_passed": ok, "cases": out},
                               indent=2, ensure_ascii=False, default=str))
    print(f"saved {path}")
    sys.exit(0 if ok else 1)


asyncio.run(main())
