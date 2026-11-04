"""RevenueCat TRANSFER 処理のテスト(本番DBへの書き込み無し・外部API呼び出し無し)。

- 埋め込みPostgres(pgserver)を ./pgdata に立て、本番と同じ関数定義を流す:
    materialize_expired_grants / grant_credits  … 20260919000000 の定義をそのまま抽出
    新マイグレーション 20261104010000_handle_revenuecat_transfer.sql … ファイルを丸ごと実行
- 本番Supabaseから「読み取りのみ」で、subscription_plans 全行と
  lefture.app / shogo.toiyama の active mapping・有効grant、実際に受信した
  TRANSFER payload(billing_webhook_log)を取得してシードに使う。
- Python側のハンドラ(_uuid_strings / _handle_revenuecat_transfer)は
  lefture_backend/app/main.py からASTで関数定義だけを抜き出して実行する。
実行: .venv/bin/python run_test.py
"""
import ast
import asyncio
import json
import logging
import re
import sys
import time
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path

import pgserver
import psycopg2
import psycopg2.extras

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MIG = ROOT / "supabase" / "migrations"

# ---------------------------------------------------------------- prod (read-only)
env = {}
for line in open(ROOT / "lefture_backend" / ".env"):
    line = line.strip()
    if "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
H = {"apikey": env["SUPABASE_SECRET_KEY"], "Authorization": "Bearer " + env["SUPABASE_SECRET_KEY"]}


def prod_get(path):
    r = urllib.request.Request(env["SUPABASE_URL"] + "/rest/v1/" + path, headers=H, method="GET")
    return json.loads(urllib.request.urlopen(r).read())


LEFTURE = "5be0566d-9b7a-499f-b7d2-f1c736fd5082"
SHOGO = "a0368beb-867a-48ce-a9a1-c1421a72fc65"
plans = prod_get("subscription_plans?select=*")
PLAN = {p["name"]: p for p in plans}
snapshot = {}
for uid in (LEFTURE, SHOGO):
    snapshot[uid] = {
        "mappings": prod_get(f"user_subscription_mappings?select=*&user_id=eq.{uid}"),
        # 残高のあるgrantに加え、Freeの付け直し判定(直近1請求期間の付与有無)に
        # 必要なので、直近60日のgrantは消化済み(remaining=0)のものも含める。
        "grants": prod_get(f"credit_grants?select=*&user_id=eq.{uid}"
                           f"&or=(remaining_amount.gt.0,created_at.gte.2026-09-05)"),
    }
real_transfer = prod_get("billing_webhook_log?select=raw_payload&event_type=eq.TRANSFER&order=id&limit=1")[0]["raw_payload"]

# ---------------------------------------------------------------- local postgres
srv = pgserver.get_server(str(HERE / "pgdata"), cleanup_mode="stop")
conn = psycopg2.connect(srv.get_uri())
conn.autocommit = True
cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)


def sql(q, args=None):
    cur.execute(q, args)
    try:
        return cur.fetchall()
    except psycopg2.ProgrammingError:
        return None


def extract_fn(path, name):
    text = path.read_text()
    m = re.search(rf"CREATE (?:OR REPLACE )?FUNCTION public\.{name}\(.*?\$function\$;", text, re.S)
    assert m, f"{name} not found in {path.name}"
    return m.group(0)


def reset_db():
    sql("drop schema if exists public cascade; create schema public;")
    sql("""
    create table subscription_plans (
      id uuid primary key, created_at timestamptz, name text, monthly_credit_amount bigint, price_usd numeric,
      updated_at timestamptz, disabled_at timestamptz, metadata jsonb, claim_mode text, billing_interval_months int,
      store_product_id text, subtitles jsonb, tier_level int, stripe_price_id text, stripe_product_id text);
    create table user_subscription_mappings (
      id uuid default gen_random_uuid() primary key, created_at timestamptz default now() not null,
      user_id uuid not null, plan_id uuid not null, status text, current_period_start timestamptz,
      current_period_end timestamptz, metadata jsonb, pending_plan_id uuid, auto_renew_disabled boolean default false);
    create unique index user_subscription_mappings_user_plan_uidx on user_subscription_mappings (user_id, plan_id);
    create table credit_grants (
      id uuid default gen_random_uuid() primary key, created_at timestamptz default now() not null,
      user_id uuid not null, amount bigint not null, remaining_amount bigint not null, source text,
      plan_id uuid, expires_at timestamptz, metadata jsonb);
    create table credit_transactions (
      id uuid default gen_random_uuid() primary key, created_at timestamptz default now() not null,
      user_id uuid not null, delta bigint not null, balance_after bigint, reason text,
      related_job_id uuid, related_grant_id uuid, metadata jsonb);
    create table revenuecat_webhook_events (
      event_id text primary key, event_type text not null, received_at timestamptz default now() not null, raw_payload jsonb);
    """)
    f = MIG / "20260919000000_fix_credit_expiry_materialization.sql"
    sql(extract_fn(f, "materialize_expired_grants"))
    sql(extract_fn(f, "grant_credits"))
    sql((MIG / "20261104010000_handle_revenuecat_transfer.sql").read_text())
    for p in plans:
        cols = list(p.keys())
        sql(f"insert into subscription_plans ({','.join(cols)}) values ({','.join(['%s'] * len(cols))})",
            [json.dumps(p[c]) if isinstance(p[c], (dict, list)) else p[c] for c in cols])


def seed_snapshot():
    for uid, s in snapshot.items():
        for m in s["mappings"]:
            m = {k: v for k, v in m.items() if k != "store"}
            cols = list(m.keys())
            sql(f"insert into user_subscription_mappings ({','.join(cols)}) values ({','.join(['%s'] * len(cols))})",
                [json.dumps(m[c]) if isinstance(m[c], dict) else m[c] for c in cols])
        for g in s["grants"]:
            cols = list(g.keys())
            sql(f"insert into credit_grants ({','.join(cols)}) values ({','.join(['%s'] * len(cols))})",
                [json.dumps(g[c]) if isinstance(g[c], dict) else g[c] for c in cols])


def balance(uid):
    return sql("select coalesce(sum(remaining_amount),0)::bigint b from credit_grants where user_id=%s and remaining_amount>0 "
               "and (expires_at is null or expires_at>now())", (uid,))[0]["b"]


def active(uid):
    rows = sql("select p.name, m.store, m.current_period_end from user_subscription_mappings m join subscription_plans p "
               "on p.id=m.plan_id where m.user_id=%s and m.status='active'", (uid,))
    return [(r["name"], r["store"]) for r in rows]


def add_map(uid, plan, end, store=None, start="now()"):
    sql(f"insert into user_subscription_mappings (user_id, plan_id, status, current_period_start, current_period_end, store) "
        f"values (%s,%s,'active',{start},%s,%s)", (uid, PLAN[plan]["id"], end, store))


def add_grant(uid, amount_credits, source, plan=None, expires=None, created="now()"):
    sql(f"insert into credit_grants (user_id, amount, remaining_amount, source, plan_id, expires_at, created_at) "
        f"values (%s,%s,%s,%s,%s,%s,{created})",
        (uid, amount_credits * 10**6, amount_credits * 10**6, source, PLAN[plan]["id"] if plan else None, expires))


# ---------------------------------------------------------------- python handler from main.py
class _Rpc:
    def __init__(self, name, params):
        self.name, self.params = name, params

    def execute(self):
        p = self.params
        if self.name == "transfer_store_subscription":
            r = sql("select transfer_store_subscription(%s, %s::uuid[], %s::uuid, %s) as r",
                    (p["p_event_id"], p["p_from_user_ids"], p["p_to_user_id"], p["p_store"]))
            return type("R", (), {"data": r[0]["r"]})()
        raise AssertionError(self.name)


class FakeAdmin:
    def rpc(self, name, params):
        return _Rpc(name, params)


src = (ROOT / "lefture_backend" / "app" / "main.py").read_text()
tree = ast.parse(src)
wanted = {"_uuid_strings", "_handle_revenuecat_transfer"}
mod = ast.Module(body=[n for n in tree.body if getattr(n, "name", None) in wanted], type_ignores=[])
assert len(mod.body) == 2, "handler functions not found in main.py"
ns = {"uuid": uuid, "asyncio": asyncio, "logger": logging.getLogger("t")}
exec(compile(mod, "main.py(extract)", "exec"), ns)
handle_transfer = ns["_handle_revenuecat_transfer"]


def transfer_event(eid, frm, to, store="APP_STORE"):
    return {"id": eid, "type": "TRANSFER", "store": store, "environment": "SANDBOX",
            "transferred_from": frm, "transferred_to": to}


def run_transfer(ev):
    return asyncio.run(handle_transfer(ev, FakeAdmin()))


# ---------------------------------------------------------------- cases
CASES = []


def case(fn):
    CASES.append(fn)
    return fn


@case
def s1_real_payload_on_prod_snapshot():
    """本番の今の状態 + 実際に受信したTRANSFER payload(shogo -> lefture.app)。"""
    reset_db(); seed_snapshot()
    before = {LEFTURE: (active(LEFTURE), balance(LEFTURE)), SHOGO: (active(SHOGO), balance(SHOGO))}
    res = run_transfer(real_transfer["event"])
    after = {LEFTURE: (active(LEFTURE), balance(LEFTURE)), SHOGO: (active(SHOGO), balance(SHOGO))}
    assert res["status"] == "success", res
    assert [a[0] for a in after[LEFTURE][0]] == ["Max"], after
    assert [a[0] for a in after[SHOGO][0]] == ["Free"], after
    # shogoの残Maxクレジット(4000)がlefture.appへ、lefture.appの手動Max分は畳まれ、
    # 永久クレジット(credit pack 900)は残る
    pack = 900 * 10**6
    assert after[LEFTURE][1] == pack + 4000 * 10**6, after
    # shogoは直近1ヶ月にFree付与済み(10/21)かつFree期間が未来 → 付け直さない
    assert after[SHOGO][1] == 0, after
    sum_before = before[LEFTURE][1] + before[SHOGO][1]
    sum_after = after[LEFTURE][1] + after[SHOGO][1]
    assert sum_after <= sum_before, (sum_before, sum_after)
    return {"result": res, "before": before, "after": after}


@case
def s2_same_event_retry_is_duplicate():
    res = run_transfer(real_transfer["event"])  # s1の直後の状態で再送
    assert res["status"] == "already_processed", res
    return res


@case
def s3_ping_pong_does_not_create_credits():
    reset_db(); seed_snapshot()
    total0 = balance(LEFTURE) + balance(SHOGO)
    totals = []
    a, b = SHOGO, LEFTURE
    for i in range(6):
        run_transfer(transfer_event(f"pp-{i}", [a, "$RCAnonymousID:x"], [b, "$RCAnonymousID:y"]))
        totals.append(balance(LEFTURE) + balance(SHOGO))
        a, b = b, a
    assert all(t <= total0 for t in totals), (total0, totals)
    assert totals == sorted(totals, reverse=True), totals  # 単調非増加
    return {"total_before": total0, "totals_after_each_bounce": totals}


@case
def s4_stripe_plan_is_not_moved_by_app_store_transfer():
    reset_db()
    a, b = str(uuid.uuid4()), str(uuid.uuid4())
    add_map(a, "Max", "2026-12-01", store="STRIPE")
    add_grant(a, 4000, "subscription_renewal_store", "Max", "2026-12-01")
    res = run_transfer(transfer_event("t4", [a], [b]))
    assert res["status"] == "ignored" and res["reason"] == "no_source_subscription", res
    assert active(a) == [("Max", "STRIPE")] and active(b) == []
    return res


@case
def s5_anonymous_destination_only_removes_source():
    reset_db()
    a = str(uuid.uuid4())
    add_map(a, "Max", "2026-12-01", store="APP_STORE")
    add_grant(a, 4000, "subscription_renewal_store", "Max", "2026-12-01")
    res = run_transfer(transfer_event("t5", [a, "$RCAnonymousID:q"], ["$RCAnonymousID:z"]))
    assert res["status"] == "success", res
    assert active(a) == [("Free", None)]
    assert balance(a) == PLAN["Free"]["monthly_credit_amount"], balance(a)  # Free初回付与
    return res


@case
def s6_anonymous_source_is_ignored():
    reset_db()
    res = run_transfer(transfer_event("t6", ["$RCAnonymousID:q"], [str(uuid.uuid4())]))
    assert res["status"] == "ignored" and res["reason"] == "no_identified_source", res


@case
def s7_source_without_store_plan_is_ignored():
    reset_db()
    a, b = str(uuid.uuid4()), str(uuid.uuid4())
    add_map(a, "Free", "2026-12-01")
    res = run_transfer(transfer_event("t7", [a], [b]))
    assert res["status"] == "ignored", res
    assert active(a) == [("Free", None)] and active(b) == []


@case
def s8_grant_sets_store_column():
    reset_db()
    a, b = str(uuid.uuid4()), str(uuid.uuid4())
    sql("select grant_store_subscription_credits(%s,'e8a','INITIAL_PURCHASE',%s,'2026-12-01')", (a, PLAN["Max"]["store_product_id"]))
    sql("select grant_store_subscription_credits(%s,'e8b','INITIAL_PURCHASE',%s,'2026-12-01')", (b, PLAN["Core"]["stripe_price_id"]))
    sql("select grant_store_subscription_credits(%s,'e8a','INITIAL_PURCHASE',%s,'2026-12-01')", (a, PLAN["Max"]["store_product_id"]))
    assert active(a) == [("Max", "APP_STORE")] and active(b) == [("Core", "STRIPE")]
    assert balance(a) == PLAN["Max"]["monthly_credit_amount"]  # 同じevent_idの再送で二重付与しない


@case
def s9_destination_other_plan_and_credit_pack():
    reset_db()
    a, b = str(uuid.uuid4()), str(uuid.uuid4())
    add_map(a, "Max", "2026-12-01", store="APP_STORE")
    add_grant(a, 3500, "subscription_renewal_store", "Max", "2026-12-01")
    add_grant(a, 500, "credit_pack_purchase")             # 永久: 移さない・消さない
    add_map(b, "Core", "2026-11-20", store="STRIPE")
    add_grant(b, 2000, "subscription_renewal_store", "Core", "2026-11-20")
    add_grant(b, 100, "credit_pack_purchase")
    res = run_transfer(transfer_event("t9", [a], [b]))
    assert res["status"] == "success", res
    assert active(b) == [("Max", "APP_STORE")], active(b)
    assert balance(b) == (3500 + 100) * 10**6, balance(b)
    assert balance(a) == 500 * 10**6 + PLAN["Free"]["monthly_credit_amount"], balance(a)
    period = sql("select current_period_end from user_subscription_mappings m join subscription_plans p on p.id=m.plan_id "
                 "where m.user_id=%s and p.name='Max'", (b,))[0]["current_period_end"]
    assert period.date().isoformat() == "2026-12-01", period
    return res


@case
def s10_legacy_null_store_is_moved():
    reset_db()
    a, b = str(uuid.uuid4()), str(uuid.uuid4())
    add_map(a, "Max", "2027-10-26", store=None)
    add_grant(a, 3498, "subscription_initial_store", "Max", "2027-10-26")
    res = run_transfer(transfer_event("t10", [a], [b]))
    assert res["status"] == "success" and active(b) == [("Max", "APP_STORE")], (res, active(b))
    assert balance(b) == 3498 * 10**6


@case
def s11_transactions_use_existing_reasons_only():
    reasons = {r["reason"] for r in sql("select distinct reason from credit_transactions")}
    allowed = {"credit_reset_plan_changed", "credit_reset_renewed", "credit_expired", "subscription_initial",
               "subscription_initial_store", "subscription_renewal_store", "subscription_grace_period"}
    assert reasons <= allowed, reasons - allowed
    return sorted(reasons)


def main():
    out, ok = [], True
    for fn in CASES:
        t0 = time.perf_counter()
        try:
            detail = fn()
            out.append({"case": fn.__name__, "ok": True, "ms": round((time.perf_counter() - t0) * 1000, 1), "detail": detail})
            print(f"PASS {fn.__name__}")
        except Exception as e:
            ok = False
            out.append({"case": fn.__name__, "ok": False, "error": repr(e)})
            print(f"FAIL {fn.__name__}: {e!r}")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = HERE / "results" / f"{stamp}_transfer_test.json"
    path.write_text(json.dumps({"run_at": stamp, "external_api_calls": 0, "cost_usd": 0, "prod_writes": 0,
                                "all_passed": ok, "cases": out}, indent=2, ensure_ascii=False, default=str))
    print(f"saved {path}")
    conn.close()
    sys.exit(0 if ok else 1)


main()
