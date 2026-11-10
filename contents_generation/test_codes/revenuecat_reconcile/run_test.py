"""RevenueCat突き合わせ(store_reconcile) + 関数権限の修正 のテスト。

本番DBへの書き込み: 0件。RevenueCat API: 読み取り(GET)のみ。費用: $0。

  S1  権限修正マイグレーション(20261110000000)… 埋め込みPostgres(pgserver)に
      Supabaseと同じ「デフォルトでanon/authenticatedにEXECUTE」状態を再現して流す
  S2  claim_store_sync_slot の間引き(20261110010000)
  S3  本物の RevenueCat API(本番コードの revenuecat_api.py)+ 本番DBの状態で decide()
  S4  本番と同じSQL関数を入れたPostgresで reconcile_user() を実際に動かす
      (supabase-pyの呼び出しを最小限のフェイクでSQLに変換)
  S5  webhookの匿名ID処理(main.pyの_handle_revenuecat_eventをASTで抽出して実行)
実行: .venv/bin/python run_test.py
"""
import ast
import asyncio
import json
import logging
import re
import sys
import time
import uuid
from datetime import datetime, timezone, timedelta
from pathlib import Path

import pgserver
import psycopg2
import psycopg2.extras

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MIG = ROOT / "supabase" / "migrations"
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "lefture_backend"))
from sb import env, req  # noqa: E402  (本番は読み取りのみ)


def prod_get(path):
    return req("GET", "/rest/v1/" + path)

import os  # noqa: E402
os.environ["REVENUECAT_SECRET_API_KEY"] = env["REVENUECAT_SECRET_API_KEY"]
os.environ["REVENUECAT_PROJECT_ID"] = env["REVENUECAT_PROJECT_ID"]
from app.services.helpers import revenuecat_api, store_reconcile  # noqa: E402

logging.basicConfig(level=logging.WARNING)

# 商品IDの対応(products:read 権限が付くまでの暫定。根拠は本番データ):
#  prod61c65a81de: 友達a29fe924のRCサブスクの商品。同じ購入のwebhookは
#                  com.lefture.app.sub.premium でMaxとしてDBに入っている
#  prod0371c8554c: 4859e134 の stripe サブスク。DBのMax(stripe顧客)に対応
EVIDENCE_STORE_IDS = {"prod61c65a81de": "com.lefture.app.sub.premium"}

# ------------------------------------------------------------------ Postgres
srv = pgserver.get_server(str(HERE / "pgdata"), cleanup_mode="stop")
conn = psycopg2.connect(srv.get_uri())
conn.autocommit = True
cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
for _role in ("anon", "authenticated", "service_role"):
    cur.execute("select 1 from pg_roles where rolname=%s", (_role,))
    if not cur.fetchone():
        cur.execute(f"create role {_role} nologin")


def sql(q, args=None):
    cur.execute(q, args)
    try:
        return cur.fetchall()
    except psycopg2.ProgrammingError:
        return None


def extract_fn(path, name):
    m = re.search(rf"CREATE (?:OR REPLACE )?FUNCTION public\.{name}\(.*?\$function\$;", path.read_text(), re.S)
    assert m, f"{name} not in {path.name}"
    return m.group(0)


plans = prod_get("subscription_plans?select=*")
PLAN = {p["name"]: p for p in plans}


def reset_db():
    sql("drop schema if exists public cascade; create schema public; grant usage on schema public to anon, authenticated, service_role;")
    # Supabaseのデフォルト権限を再現(public に作られる関数は anon/authenticated から実行可能)
    sql("alter default privileges for role postgres in schema public grant execute on functions to anon, authenticated, service_role;")
    sql("""
    create table subscription_plans (
      id uuid primary key, created_at timestamptz, name text, monthly_credit_amount bigint, price_usd numeric,
      updated_at timestamptz, disabled_at timestamptz, metadata jsonb, claim_mode text, billing_interval_months int,
      store_product_id text, subtitles jsonb, tier_level int, stripe_price_id text, stripe_product_id text);
    create table user_subscription_mappings (
      id uuid default gen_random_uuid() primary key, created_at timestamptz default now() not null,
      user_id uuid not null, plan_id uuid not null references subscription_plans(id), status text,
      current_period_start timestamptz, current_period_end timestamptz, metadata jsonb,
      pending_plan_id uuid, auto_renew_disabled boolean default false);
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
    sql((MIG / "20261104000000_add_billing_webhook_log.sql").read_text().replace("ENABLE ROW LEVEL SECURITY", "DISABLE ROW LEVEL SECURITY"))
    f19 = MIG / "20260919000000_fix_credit_expiry_materialization.sql"
    sql(extract_fn(f19, "materialize_expired_grants"))
    sql(extract_fn(f19, "grant_credits"))
    sql(extract_fn(MIG / "20260927000000_add_apple_auto_renew_disabled.sql", "mark_apple_subscription_auto_renew_disabled"))
    sql(extract_fn(MIG / "20260927020000_fix_expire_store_subscription_same_plan_guard.sql", "expire_store_subscription"))
    sql((MIG / "20261104010000_handle_revenuecat_transfer.sql").read_text())
    # 許可リストの3関数とトリガー関数(中身はダミー、シグネチャは本番と同じ名前)
    sql("""
    create function public.get_my_tier_level() returns integer language sql security definer as $$ select 0 $$;
    create function public.touch_activity(p_platform text, p_tz integer) returns void language sql as $$ select $$;
    create function public.search_knowledge_chunks(q text) returns setof text language sql as $$ select q $$;
    create function public.set_updated_at() returns trigger language plpgsql as $$ begin return new; end $$;
    """)
    for p in plans:
        cols = list(p.keys())
        sql(f"insert into subscription_plans ({','.join(cols)}) values ({','.join(['%s'] * len(cols))})",
            [json.dumps(p[c]) if isinstance(p[c], (dict, list)) else p[c] for c in cols])


def apply_migrations():
    sql((MIG / "20261110000000_revoke_public_execute_on_functions.sql").read_text())
    sql((MIG / "20261110010000_add_store_subscription_reconcile.sql").read_text())


def can_exec(role, sig):
    return sql("select has_function_privilege(%s, %s, 'execute') ok", (role, sig))[0]["ok"]


def active(uid):
    return [(r["name"], r["store"], r["end"], r["ard"]) for r in sql(
        "select p.name, m.store, to_char(m.current_period_end at time zone 'utc','YYYY-MM-DD\"T\"HH24:MI:SS') as end, "
        "m.auto_renew_disabled ard from user_subscription_mappings m join subscription_plans p on p.id=m.plan_id "
        "where m.user_id=%s and m.status='active'", (uid,))]


def balance(uid):
    return sql("select coalesce(sum(remaining_amount),0)::bigint b from credit_grants where user_id=%s and remaining_amount>0 "
               "and (expires_at is null or expires_at>now())", (uid,))[0]["b"] // 10**6


def add_map(uid, plan, end, store=None):
    sql("insert into user_subscription_mappings (user_id, plan_id, status, current_period_start, current_period_end, store) "
        "values (%s,%s,'active',now()-interval '20 days',%s,%s)", (uid, PLAN[plan]["id"], end, store))


def add_grant(uid, credits, source, plan=None, expires=None, created="now()"):
    sql(f"insert into credit_grants (user_id, amount, remaining_amount, source, plan_id, expires_at, created_at) "
        f"values (%s,%s,%s,%s,%s,%s,{created})",
        (uid, credits * 10**6, credits * 10**6, source, PLAN[plan]["id"] if plan else None, expires))


# ------------------------------------------------------------------ supabase-py の最小フェイク(SQLへ変換)
class _Res:
    def __init__(self, data):
        self.data = data


class _Q:
    def __init__(self, table):
        self.t, self.op, self.payload, self.f, self.sel, self.single_, self.lim, self.ord = table, "select", None, [], "*", False, None, None

    def select(self, s="*", **_):
        self.sel = s; return self

    def insert(self, row):
        self.op, self.payload = "insert", row; return self

    def update(self, row):
        self.op, self.payload = "update", row; return self

    def eq(self, k, v):
        self.f.append((k, v)); return self

    def order(self, col, desc=False):
        self.ord = (col, desc); return self

    def limit(self, n):
        self.lim = n; return self

    def single(self):
        self.single_ = True; return self

    def execute(self):
        if self.op == "insert":
            cols = list(self.payload)
            sql(f"insert into {self.t} ({','.join(cols)}) values ({','.join(['%s'] * len(cols))})",
                [json.dumps(v) if isinstance(v, (dict, list)) else v for v in self.payload.values()])
            return _Res([self.payload])
        if self.op == "update":
            sets = ",".join(f"{k}=%s" for k in self.payload)
            where = " and ".join(f"{k}=%s" for k, _ in self.f)
            sql(f"update {self.t} set {sets} where {where}",
                [json.dumps(v) if isinstance(v, (dict, list)) else v for v in self.payload.values()] + [v for _, v in self.f])
            return _Res([])
        if "subscription_plans!" in self.sel:  # _load_db_mapping の埋め込みフィルタ
            uid = dict(self.f)["user_id"]
            rows = sql("select m.id::text, m.plan_id::text, m.current_period_end::text from user_subscription_mappings m "
                       "join subscription_plans p on p.id=m.plan_id where m.user_id=%s and m.status='active' "
                       "and p.claim_mode='store_purchase' order by m.current_period_end desc limit 1", (uid,))
            return _Res([dict(r) for r in rows])
        where = (" where " + " and ".join(f"{k}::text=%s" for k, _ in self.f)) if self.f else ""
        rows = [dict(r) for r in sql(f"select {self.sel} from {self.t}{where}", [str(v) for _, v in self.f])]
        for r in rows:
            for k, v in list(r.items()):
                if isinstance(v, uuid.UUID):
                    r[k] = str(v)
        return _Res(rows[0] if self.single_ else rows)


class _Rpc:
    def __init__(self, name, params):
        self.name, self.params = name, params

    def execute(self):
        keys = list(self.params)
        r = sql(f"select public.{self.name}({','.join(f'{k} => %s' for k in keys)}) as r", [self.params[k] for k in keys])
        return _Res(r[0]["r"] if r else None)


class FakeAdmin:
    def table(self, name):
        return _Q(name)

    def rpc(self, name, params):
        return _Rpc(name, params)


# ------------------------------------------------------------------ cases
CASES, RESULTS = [], {}


def case(fn):
    CASES.append(fn); return fn


@case
def s1_security_revoke():
    reset_db()
    g = "grant_store_subscription_credits(uuid,text,text,text,timestamp with time zone)"
    before = {"anon": can_exec("anon", g), "authenticated": can_exec("authenticated", g)}
    assert before == {"anon": True, "authenticated": True}, ("Supabaseの既定状態を再現できていない", before)
    apply_migrations()
    checks = {
        "grant_store_subscription_credits": g, "grant_credits": "grant_credits(uuid,bigint,text,uuid,timestamp with time zone)",
        "transfer_store_subscription": "transfer_store_subscription(text,uuid[],uuid,text)",
        "claim_store_sync_slot": "claim_store_sync_slot(uuid,integer)",
    }
    out = {}
    for name, sig in checks.items():
        out[name] = {r: can_exec(r, sig) for r in ("anon", "authenticated", "service_role")}
        assert out[name] == {"anon": False, "authenticated": False, "service_role": True}, (name, out[name])
    for name, sig in {"get_my_tier_level": "get_my_tier_level()", "touch_activity": "touch_activity(text,integer)",
                      "search_knowledge_chunks": "search_knowledge_chunks(text)"}.items():
        out[name] = {r: can_exec(r, sig) for r in ("anon", "authenticated", "service_role")}
        assert out[name] == {"anon": False, "authenticated": True, "service_role": True}, (name, out[name])
    # 実際に anon として呼ぶと拒否される
    try:
        sql("set role anon; select public.grant_credits('00000000-0000-4000-8000-000000000000', 1, 'x');")
        raise AssertionError("anon could execute grant_credits")
    except psycopg2.errors.InsufficientPrivilege as e:
        out["anon_call"] = str(e).strip().splitlines()[0]
    finally:
        sql("reset role;")
    # 修正後に新しく作った関数も既定で anon/authenticated から呼べない
    sql("create function public.future_fn() returns int language sql as $$ select 1 $$;")
    out["future_fn"] = {r: can_exec(r, "future_fn()") for r in ("anon", "authenticated", "service_role")}
    assert out["future_fn"] == {"anon": False, "authenticated": False, "service_role": True}, ("future_fn", out["future_fn"])
    return out


@case
def s2_claim_slot_throttle():
    u = str(uuid.uuid4())
    seq = [sql("select claim_store_sync_slot(%s, 1) r", (u,))[0]["r"], sql("select claim_store_sync_slot(%s, 1) r", (u,))[0]["r"]]
    time.sleep(1.2)
    seq.append(sql("select claim_store_sync_slot(%s, 1) r", (u,))[0]["r"])
    assert seq == [True, False, True], seq
    return seq


USERS = {
    "fdae3630-75e5-4304-8b13-356254ec1f2f": "friend_offer_code_before_install",
    "a29fe924-9adf-4baa-b84a-7c8906944d7b": "friend_offer_code_after_install",
    "5be0566d-9b7a-499f-b7d2-f1c736fd5082": "lefture_app_sandbox",
    "13726160-6858-4a03-8cb5-69aeb0599773": "sandbox_tester",
    "1c141384-f370-4c47-90ba-0f5e65063b38": "production_max",
    "4859e134-9221-4e02-b33a-46b6cab47016": "stale_stripe_sandbox_max",
    "d0195a12-2b97-48aa-a29d-3790c58fec76": "reviewer_manual_10y",
    "a0368beb-867a-48ce-a9a1-c1421a72fc65": "shogo_free_after_transfer",
}
RC_SUBS = {}


@case
def s3_decide_on_real_revenuecat_and_db():
    """本番コードのrevenuecat_api.pyで本物のRCを読み、本番DBの状態と突き合わせて判定だけする。"""
    revenuecat_api.PAGE_LIMIT = 10  # ページ送り(next_page)の経路も通す
    now = datetime.now(timezone.utc)
    out = {}
    for uid, label in USERS.items():
        t0 = time.perf_counter()
        subs = asyncio.run(revenuecat_api.fetch_customer_subscriptions(uid))
        ms = round((time.perf_counter() - t0) * 1000)
        RC_SUBS[uid] = subs
        db = prod_get(f"user_subscription_mappings?select=id,plan_id,current_period_end,subscription_plans!user_subscription_mappings_plan_id_fkey!inner(claim_mode)"
                      f"&user_id=eq.{uid}&status=eq.active&subscription_plans.claim_mode=eq.store_purchase&order=current_period_end.desc&limit=1")
        store_ids = {s["product_id"]: EVIDENCE_STORE_IDS.get(s["product_id"]) for s in subs or [] if s.get("gives_access")}
        d = store_reconcile.decide(subs, store_ids, plans, db[0] if db else None, now)
        out[label] = {"rc_fetch_ms": ms, "rc_subs": len(subs or []), "decision": d["action"], "reason": d["reason"],
                      "unmapped": d.get("unmapped")}
        print(f"    {label:34s} subs={len(subs or []):2d} {ms:4d}ms -> {d['action']:6s} {d['reason']} {d.get('unmapped') or ''}")
    exp = {
        "friend_offer_code_before_install": ("none", "in_sync"),        # 11/04 の手動付与で揃っている
        "friend_offer_code_after_install": ("none", "in_sync"),
        "lefture_app_sandbox": ("none", "in_sync"),
        "sandbox_tester": ("none", "in_sync"),
        "production_max": ("none", "in_sync"),
        "reviewer_manual_10y": ("none", "db_plan_not_expired_yet"),     # 手動付与(期限2036)には触れない
        "shogo_free_after_transfer": ("none", "no_active_subscription"),
    }
    for label, (a, r) in exp.items():
        assert (out[label]["decision"], out[label]["reason"]) == (a, r), (label, out[label])
    # 4859e134: RC上は gives_access=true だが期限(10/19)切れ。Stripe商品のID対応は
    # 未取得(products:read権限待ち)なので、ここでは「変換できない有効契約は無い」= 期限切れ扱いで expire になる
    assert out["stale_stripe_sandbox_max"]["decision"] == "expire", out["stale_stripe_sandbox_max"]
    return out


async def _reconcile(uid, store_ids, interval=0):
    async def fake_fetch(_uid):
        return RC_SUBS_OVERRIDE.get(_uid, RC_SUBS.get(_uid))

    async def fake_store_id(pid):
        return store_ids.get(pid)

    revenuecat_api.fetch_customer_subscriptions = fake_fetch
    revenuecat_api.get_store_identifier = fake_store_id
    return await store_reconcile.reconcile_user(FakeAdmin(), uid, min_interval_seconds=interval, reason="test")


RC_SUBS_OVERRIDE = {}


@case
def s4a_friend_before_manual_fix_gets_max_once():
    """友達(fdae3630)の 11/04 手動付与前の状態 + 本物のRCデータ -> reconcile で Max が付く。"""
    reset_db(); apply_migrations()
    F = "fdae3630-75e5-4304-8b13-356254ec1f2f"
    add_map(F, "Free", "2026-11-30T05:16:03Z")
    add_grant(F, 320, "subscription_initial", "Free", "2026-11-30T11:16:03Z")
    r1 = asyncio.run(_reconcile(F, EVIDENCE_STORE_IDS))
    a1, b1 = active(F), balance(F)
    assert r1["action"] == "grant" and r1["reason"] == "missing_plan", r1
    assert a1 == [("Max", "APP_STORE", "2027-10-31T05:14:14", True)], a1   # 自動更新オフも反映
    assert b1 == 4000, b1
    # 2回目: 同じRCデータで in_sync、付与は増えない
    r2 = asyncio.run(_reconcile(F, EVIDENCE_STORE_IDS))
    assert r2["reason"] == "in_sync" and balance(F) == 4000, (r2, balance(F))
    # 同じevent_idを強制的に再適用しても二重付与されない
    sql("select grant_store_subscription_credits(%s,%s,'INITIAL_PURCHASE','com.lefture.app.sub.premium','2027-10-31T05:14:14Z')", (F, r1["event_id"]))
    assert balance(F) == 4000
    log = sql("select source, event_type, status, user_id::text from billing_webhook_log")
    assert [(l["source"], l["event_type"], l["status"]) for l in log] == [("reconcile", "RECONCILE_GRANT", "processed")], log
    return {"first": r1, "after": a1, "balance": b1, "second": r2["reason"]}


@case
def s4b_stale_plan_expires_to_free():
    reset_db(); apply_migrations()
    U = "4859e134-9221-4e02-b33a-46b6cab47016"
    add_map(U, "Max", "2026-10-19T21:24:41Z")
    add_grant(U, 1000, "credit_pack_purchase")  # 永久クレジットは残る
    r = asyncio.run(_reconcile(U, {}))
    assert r["action"] == "expire", r
    assert active(U) == [("Free", None, active(U)[0][2], False)], active(U)
    assert balance(U) == 1000 + PLAN["Free"]["monthly_credit_amount"] // 10**6, balance(U)
    return {"result": r, "after": active(U), "balance": balance(U)}


@case
def s4c_missed_renewal_refills_not_doubles():
    reset_db(); apply_migrations()
    U = str(uuid.uuid4())
    now = datetime.now(timezone.utc)
    add_map(U, "Max", (now - timedelta(days=1)).isoformat(), "APP_STORE")
    add_grant(U, 1500, "subscription_renewal_store", "Max", (now + timedelta(hours=5)).isoformat())
    start = now - timedelta(days=1)
    RC_SUBS_OVERRIDE[U] = [{"id": "subTEST1", "product_id": "prod61c65a81de", "store": "app_store", "environment": "production",
                            "gives_access": True, "auto_renewal_status": "will_renew",
                            "current_period_starts_at": int(start.timestamp() * 1000),
                            "current_period_ends_at": int((start + timedelta(days=30)).timestamp() * 1000)}]
    r = asyncio.run(_reconcile(U, EVIDENCE_STORE_IDS))
    assert r["action"] == "grant" and r["event_type"] == "RENEWAL", r
    assert balance(U) == 4000, balance(U)  # 1500の残りは畳まれ、新しい期間の4000だけ
    assert active(U)[0][3] is False
    return {"result": r["reason"], "balance": balance(U)}


@case
def s4d_recent_purchase_waits_for_webhook():
    reset_db(); apply_migrations()
    U = str(uuid.uuid4())
    now = datetime.now(timezone.utc)
    add_map(U, "Free", (now + timedelta(days=10)).isoformat())
    RC_SUBS_OVERRIDE[U] = [{"id": "subTEST2", "product_id": "prod61c65a81de", "store": "app_store", "environment": "production",
                            "gives_access": True, "auto_renewal_status": "will_renew",
                            "current_period_starts_at": int((now - timedelta(minutes=3)).timestamp() * 1000),
                            "current_period_ends_at": int((now + timedelta(days=30)).timestamp() * 1000)}]
    r = asyncio.run(_reconcile(U, EVIDENCE_STORE_IDS))
    assert (r["action"], r["reason"]) == ("none", "recent_purchase_wait_for_webhook"), r
    assert [a[0] for a in active(U)] == ["Free"]
    return r["reason"]


@case
def s4e_incomplete_or_unmapped_never_touches_db():
    reset_db(); apply_migrations()
    U = str(uuid.uuid4())
    now = datetime.now(timezone.utc)
    add_map(U, "Max", (now - timedelta(days=3)).isoformat(), "APP_STORE")  # 期限切れで残っている
    RC_SUBS_OVERRIDE[U] = None  # ページを取り切れなかった
    r1 = asyncio.run(_reconcile(U, {}))
    RC_SUBS_OVERRIDE[U] = [{"id": "subX", "product_id": "prodUNKNOWN", "store": "app_store", "gives_access": True,
                            "current_period_starts_at": int((now - timedelta(days=2)).timestamp() * 1000),
                            "current_period_ends_at": int((now + timedelta(days=28)).timestamp() * 1000)}]
    r2 = asyncio.run(_reconcile(U, {}))
    assert (r1["reason"], r2["reason"]) == ("incomplete_subscription_list", "unmapped_active_products"), (r1, r2)
    assert [a[0] for a in active(U)] == ["Max"]
    return [r1["reason"], r2["reason"]]


@case
def s4f_throttle_blocks_second_call():
    U = str(uuid.uuid4())
    RC_SUBS_OVERRIDE[U] = []
    r1 = asyncio.run(_reconcile(U, {}, interval=3600))
    r2 = asyncio.run(_reconcile(U, {}, interval=3600))
    assert r1["reason"] == "no_active_subscription" and r2["reason"] == "throttled", (r1, r2)
    return [r1["reason"], r2["reason"]]


@case
def s5_webhook_anonymous_app_user_id():
    src = (ROOT / "lefture_backend" / "app" / "main.py").read_text()
    tree = ast.parse(src)
    want = {"_uuid_strings", "_handle_revenuecat_event", "_handle_revenuecat_transfer"}
    mod = ast.Module(body=[n for n in tree.body if getattr(n, "name", None) in want], type_ignores=[])
    calls = []

    class Admin:
        def rpc(self, name, params):
            calls.append((name, params))
            return type("R", (), {"execute": lambda self: type("D", (), {"data": None})()})()

    class HTTPException(Exception):
        def __init__(self, status_code=None, detail=None):
            super().__init__(detail)

    ns = {"uuid": uuid, "asyncio": asyncio, "logger": logging.getLogger("t"), "datetime": datetime, "timezone": timezone,
          "HTTPException": HTTPException}
    exec(compile(mod, "main.py(extract)", "exec"), ns)
    h = ns["_handle_revenuecat_event"]
    base = {"type": "INITIAL_PURCHASE", "product_id": "com.lefture.app.sub.premium", "expiration_at_ms": 1824959654000,
            "store": "APP_STORE", "environment": "SANDBOX"}
    r_anon = asyncio.run(h({"event": {**base, "id": "e1", "app_user_id": "$RCAnonymousID:7e65",
                                      "aliases": ["$RCAnonymousID:7e65"], "original_app_user_id": "$RCAnonymousID:7e65"}}, Admin()))
    assert r_anon == {"status": "ignored", "event_type": "INITIAL_PURCHASE", "reason": "anonymous_app_user_id"} and not calls, (r_anon, calls)
    F = "fdae3630-75e5-4304-8b13-356254ec1f2f"
    r_alias = asyncio.run(h({"event": {**base, "id": "e2", "app_user_id": "$RCAnonymousID:7e65",
                                       "aliases": ["$RCAnonymousID:7e65", F]}}, Admin()))
    assert r_alias["status"] == "success" and calls[-1][1]["p_user_id"] == F, (r_alias, calls)
    r_uuid = asyncio.run(h({"event": {**base, "id": "e3", "app_user_id": F}}, Admin()))
    assert calls[-1][1]["p_user_id"] == F and r_uuid["status"] == "success"
    return {"anonymous": r_anon["reason"], "alias_resolved_to": calls[1][1]["p_user_id"]}


def main():
    out, ok = [], True
    for fn in CASES:
        t0 = time.perf_counter()
        try:
            detail = fn()
            out.append({"case": fn.__name__, "ok": True, "ms": round((time.perf_counter() - t0) * 1000), "detail": detail})
            print(f"PASS {fn.__name__}")
        except Exception as e:
            ok = False
            out.append({"case": fn.__name__, "ok": False, "error": repr(e)})
            print(f"FAIL {fn.__name__}: {e!r}")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = HERE / "results" / f"{stamp}_reconcile_test.json"
    path.write_text(json.dumps({"run_at": stamp, "prod_writes": 0, "revenuecat_calls": "GET only", "cost_usd": 0,
                                "all_passed": ok, "cases": out}, indent=2, ensure_ascii=False, default=str))
    print("saved", path)
    conn.close()
    sys.exit(0 if ok else 1)


main()
