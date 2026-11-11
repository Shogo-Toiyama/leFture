"""課金クレジットの寿命(失効の保険30日 / BILLING_ISSUEで増減しない / 長期契約の月次補充)のテスト。

本番DBへの書き込み: 0件(本番は subscription_plans の読み取りのみ)。RevenueCat API: 呼ばない。費用: $0。
埋め込みPostgres(pgserver)に、本番と同じSQL関数(マイグレーションから抽出)を入れて実行する。

  T1  旧 handle_billing_issue のバグ再現(使い切っても決済失敗で満額に戻る)
  T2  新 handle_billing_issue: 残高は増えも減りもしない(使い切りなら0のまま)・期限だけ延びる・冪等
  T3  Grace Period 中に回復(RENEWAL)→通常どおりリセット / 回復せず(EXPIRATION)→Freeへ
  T4  保険: 付与の期限 = 期間終了 + 30日。BILLING_ISSUEを取りこぼしても Grace Period 28日は消えない
  T5  月次補充: 長期契約だけ・繰り越しなし・冪等・k か月目・billing_webhook_logに記録
  T6  補充の対象外: 月額契約 / 期間終了後 / 適用前に過ぎた補充日(既存データは次の月から)
  T7  補充のあとに RENEWAL(オファー終了→通常更新)が来ても二重に積み上がらない
  T8  main.py の BILLING_ISSUE 分岐: grace_period_expiration_at_ms を優先
  T9  reconcile decide(): in_grace_period のサブスクは期限切れ扱いにしない
実行: contents_generation/test_codes/revenuecat_reconcile/.venv/bin/python run_test.py
"""
import ast, asyncio, json, logging, re, sys, time, uuid
from datetime import datetime, timezone, timedelta
from pathlib import Path

import pgserver, psycopg2, psycopg2.extras

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MIG = ROOT / "supabase" / "migrations"
sys.path.insert(0, str(ROOT / "contents_generation" / "test_codes" / "revenuecat_reconcile"))
sys.path.insert(0, str(ROOT / "lefture_backend"))
from sb import req  # noqa: E402  本番は読み取りのみ
from app.services.helpers import store_reconcile  # noqa: E402

logging.basicConfig(level=logging.WARNING)
MAX_PID = "com.lefture.app.sub.premium"

srv = pgserver.get_server(str(HERE / "pgdata"), cleanup_mode="stop")
conn = psycopg2.connect(srv.get_uri()); conn.autocommit = True
cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
for _r in ("anon", "authenticated", "service_role"):
    cur.execute("select 1 from pg_roles where rolname=%s", (_r,))
    if not cur.fetchone():
        cur.execute(f"create role {_r} nologin")


def sql(q, a=None):
    cur.execute(q, a)
    try:
        return cur.fetchall()
    except psycopg2.ProgrammingError:
        return None


def extract_fn(path, name):
    m = re.search(rf"CREATE (?:OR REPLACE )?FUNCTION public\.{name}\(.*?\$function\$;", path.read_text(), re.S)
    assert m, (name, path.name)
    return m.group(0)


plans = req("GET", "/rest/v1/subscription_plans?select=*")
PLAN = {p["name"]: p for p in plans}


def reset_db(new=False):
    sql("drop schema if exists public cascade; create schema public;")
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
    sql(extract_fn(MIG / "20260927020000_fix_expire_store_subscription_same_plan_guard.sql", "expire_store_subscription"))
    sql((MIG / "20261104010000_handle_revenuecat_transfer.sql").read_text())
    sql(extract_fn(MIG / "20260926000000_add_stripe_product_id_lookup.sql", "handle_billing_issue"))  # 旧(バグあり)
    sql((MIG / "20261110010000_add_store_subscription_reconcile.sql").read_text())
    for p in plans:
        cols = list(p.keys())
        sql(f"insert into subscription_plans ({','.join(cols)}) values ({','.join(['%s'] * len(cols))})",
            [json.dumps(p[c]) if isinstance(p[c], (dict, list)) else p[c] for c in cols])
    if new:
        sql((MIG / "20261111000000_store_credit_backstop_and_grace_period.sql").read_text())
        sql((MIG / "20261111010000_add_long_period_monthly_refill.sql").read_text())


def uid(): return str(uuid.uuid4())
def bal(u):
    return sql("select coalesce(sum(remaining_amount),0)::bigint b from credit_grants where user_id=%s and remaining_amount>0 "
               "and (expires_at is null or expires_at>now())", (u,))[0]["b"] // 10**6
def grants(u):
    return sql("select source, (remaining_amount/1000000)::bigint as rem, expires_at, created_at, metadata from credit_grants "
               "where user_id=%s order by created_at, source", (u,))
def purchase(u, ev, typ="INITIAL_PURCHASE", end="now() + interval '30 days'"):
    sql(f"select grant_store_subscription_credits(%s,%s,%s,%s,{end})", (u, ev, typ, MAX_PID))
def spend_to(u, credits):
    sql("update credit_grants set remaining_amount=%s where user_id=%s and plan_id=%s and remaining_amount>0",
        (credits * 10**6, u, PLAN["Max"]["id"]))
def age_grants(u, days):
    sql("update credit_grants set created_at = created_at - make_interval(days=>%s) where user_id=%s", (days, u))
def ledger(u): return sql("select reason, (delta/1000000)::bigint as d from credit_transactions where user_id=%s", (u,))
def days_until(ts): return round((ts - datetime.now(timezone.utc)).total_seconds() / 86400, 1)

CASES = []
def case(fn): CASES.append(fn); return fn


@case
def t1_old_billing_issue_bug_reproduced():
    reset_db(new=False)
    u = uid(); purchase(u, "e1", end="now() - interval '1 hour'")
    sql("update credit_grants set expires_at = now() + interval '5 hours' where user_id=%s", (u,))
    spend_to(u, 0)
    assert bal(u) == 0
    sql("select handle_billing_issue(%s,'bi1',%s, now() + interval '28 days')", (u, MAX_PID))
    after = bal(u)
    assert after == 4000, after  # 使い切っていたのに決済失敗で満額に戻る = バグ
    return {"balance_before": 0, "balance_after_old_handle_billing_issue": after}


@case
def t2_new_billing_issue_keeps_balance_and_extends_expiry():
    reset_db(new=True)
    out = {}
    # (a) 使い切り: 0のまま・新規付与なし・台帳なし
    a = uid(); purchase(a, "a1", end="now() - interval '1 hour'")
    sql("update credit_grants set expires_at = now() + interval '5 hours' where user_id=%s", (a,))  # 旧方式の6時間期限の状態
    spend_to(a, 0); n0 = len(grants(a)); l0 = len(ledger(a))
    sql("select handle_billing_issue(%s,'a-bi',%s, now() + interval '28 days')", (a, MAX_PID))
    assert bal(a) == 0 and len(grants(a)) == n0 and len(ledger(a)) == l0, (bal(a), grants(a), ledger(a))
    out["spent_all"] = {"balance": bal(a), "grants": len(grants(a)), "new_ledger_rows": len(ledger(a)) - l0}
    # (b) 残り700: 700のまま。旧方式の期限(5時間後)がGrace終了+2日(=30日後)へ延びる
    b = uid(); purchase(b, "b1", end="now() - interval '1 hour'")
    sql("update credit_grants set expires_at = now() + interval '5 hours' where user_id=%s", (b,))
    spend_to(b, 700)
    sql("select handle_billing_issue(%s,'b-bi',%s, now() + interval '28 days')", (b, MAX_PID))
    g = [x for x in grants(b) if x["rem"] > 0][0]
    assert bal(b) == 700 and 29.9 <= days_until(g["expires_at"]) <= 30.1, (bal(b), g)
    out["remaining_700"] = {"balance": bal(b), "expires_in_days": days_until(g["expires_at"])}
    # (c) 取引自体の期限(expiration_at_ms)を渡された場合は期限を縮めない(30日の保険が残る)
    c = uid(); purchase(c, "c1", end="now() - interval '3 days'")
    before = [x for x in grants(c) if x["rem"] > 0][0]["expires_at"]
    sql("select handle_billing_issue(%s,'c-bi',%s, now() - interval '3 days')", (c, MAX_PID))
    after = [x for x in grants(c) if x["rem"] > 0][0]["expires_at"]
    assert after == before, (before, after)
    out["never_shortens"] = True
    # (d) 冪等: 同じ event_id の再送は何も変えない
    sql("select handle_billing_issue(%s,'b-bi',%s, now() + interval '90 days')", (b, MAX_PID))
    g2 = [x for x in grants(b) if x["rem"] > 0][0]
    assert g2["expires_at"] == g["expires_at"] and bal(b) == 700
    out["idempotent"] = True
    return out


@case
def t3_recovery_and_no_recovery():
    reset_db(new=True)
    # 回復: Grace中に残高300 → RENEWAL で通常どおりリセット(300は繰り越されず、4000に)
    u = uid(); purchase(u, "r1", end="now() - interval '2 days'"); spend_to(u, 300)
    sql("select handle_billing_issue(%s,'bi',%s, now() + interval '26 days')", (u, MAX_PID))
    assert bal(u) == 300
    purchase(u, "r2", typ="RENEWAL", end="now() + interval '30 days'")
    assert bal(u) == 4000, bal(u)
    # 回復せず: EXPIRATION → Maxのクレジットは消え、Freeに戻る
    v = uid(); purchase(v, "x1", end="now() - interval '2 days'"); spend_to(v, 300)
    sql("select handle_billing_issue(%s,'bi2',%s, now() + interval '26 days')", (v, MAX_PID))
    sql("select expire_store_subscription(%s,'exp',%s)", (v, MAX_PID))
    maxrem = sql("select coalesce(sum(remaining_amount),0)::bigint s from credit_grants where user_id=%s and plan_id=%s", (v, PLAN["Max"]["id"]))[0]["s"]
    plan_now = sql("select p.name from user_subscription_mappings m join subscription_plans p on p.id=m.plan_id where m.user_id=%s and m.status='active'", (v,))
    assert maxrem == 0 and [x["name"] for x in plan_now] == ["Free"], (maxrem, plan_now)
    return {"recovered_balance": bal(u), "after_expiration": {"max_credits_left": maxrem, "active_plan": plan_now[0]["name"], "balance": bal(v)}}


@case
def t4_backstop_is_30_days_and_survives_missed_billing_issue():
    reset_db(new=True)
    u = uid(); purchase(u, "p1", end="now() + interval '10 days'")
    g = [x for x in grants(u) if x["rem"] > 0][0]
    d = days_until(g["expires_at"])
    assert 39.9 <= d <= 40.1, d  # 期間終了(10日後) + 30日
    # BILLING_ISSUEを取りこぼしたまま、期間終了から27日経った時点でも残高が生きている(Grace 28日以内)
    w = uid(); purchase(w, "w1", end="now() - interval '27 days'")
    assert bal(w) == 4000, bal(w)
    # 期間終了から31日経ってEXPIRATIONも来ていなければ、保険の期限で消える
    z = uid(); purchase(z, "z1", end="now() - interval '31 days'")
    assert bal(z) == 0, bal(z)
    return {"expires_in_days_for_end_plus_10": d, "balance_27d_after_period_end": 4000, "balance_31d_after_period_end": 0}


def long_offer(u, ev=None, anchor_days_ago=45, end_days=365):
    purchase(u, ev or str(uuid.uuid4()), end=f"now() + interval '{end_days} days'")
    age_grants(u, anchor_days_ago)


@case
def t5_monthly_refill():
    reset_db(new=True)
    u = uid(); long_offer(u, anchor_days_ago=45); spend_to(u, 100)
    old = "2000-01-01T00:00:00Z"
    r1 = sql("select refill_long_period_store_credits(50, %s) r", (old,))[0]["r"]
    assert len(r1["refilled"]) == 1 and r1["refilled"][0]["refill_month"] == 1, r1
    assert bal(u) == 4000, bal(u)  # 100 + 4000 ではなく 4000(繰り越しなし)
    gs = grants(u)
    refill = [x for x in gs if (x["metadata"] or {}).get("refill")]
    assert len(refill) == 1 and refill[0]["source"] == "subscription_renewal_store"
    assert [x["d"] for x in ledger(u) if x["reason"] == "credit_reset_renewed"] == [-100], ledger(u)
    log = sql("select source,event_type,status,result from billing_webhook_log where user_id=%s", (u,))
    assert len(log) == 1 and log[0]["source"] == "reconcile" and log[0]["event_type"] == "REFILL", log
    # 冪等: すぐもう一度実行しても増えない
    r2 = sql("select refill_long_period_store_credits(50, %s) r", (old,))[0]["r"]
    assert r2["refilled"] == [] and bal(u) == 4000, (r2, bal(u))
    # 2か月目: さらに1か月進めると、もう一度だけ補充(補充分は通常付与の日付に数えないので起点は動かない)
    age_grants(u, 31)
    spend_to(u, 50)
    r3 = sql("select refill_long_period_store_credits(50, %s) r", (old,))[0]["r"]
    assert len(r3["refilled"]) == 1 and r3["refilled"][0]["refill_month"] == 2 and bal(u) == 4000, (r3, bal(u))
    return {"month1": r1["refilled"][0], "balance_after_month1": 4000, "month2": r3["refilled"][0], "ledger": len(ledger(u))}


@case
def t6_not_eligible():
    reset_db(new=True)
    old = "2000-01-01T00:00:00Z"
    monthly = uid(); purchase(monthly, "m1", end="now() + interval '10 days'"); age_grants(monthly, 20); spend_to(monthly, 10)  # 通常の月額(付与から20日目)
    ended = uid(); long_offer(ended); sql("update user_subscription_mappings set current_period_end = now() - interval '1 day' where user_id=%s", (ended,)); spend_to(ended, 10)
    young = uid(); long_offer(young, anchor_days_ago=10); spend_to(young, 10)  # まだ1か月経っていない
    r = sql("select refill_long_period_store_credits(50, %s) r", (old,))[0]["r"]
    assert r["refilled"] == [], r
    assert (bal(monthly), bal(ended), bal(young)) == (10, 10, 10), (bal(monthly), bal(ended), bal(young))
    # 既存データは次の月から: 補充日(anchor + 1か月)が下限より前なら補充しない。後なら補充する。
    e = uid(); long_offer(e, anchor_days_ago=45); spend_to(e, 10)
    due = sql("select (min(created_at) + interval '1 month') d from credit_grants where user_id=%s", (e,))[0]["d"]
    skip = sql("select refill_long_period_store_credits(50, %s) r", (due + timedelta(days=1),))[0]["r"]
    assert skip["refilled"] == [] and bal(e) == 10, skip
    go = sql("select refill_long_period_store_credits(50, %s) r", (due - timedelta(days=1),))[0]["r"]
    assert len(go["refilled"]) == 1 and bal(e) == 4000, go
    # 既定の下限(2026-11-11)で、今日が下限より前なら何も起きない(適用前の補充日を遡らない)
    d = uid(); long_offer(d, anchor_days_ago=45); spend_to(d, 10)
    default = sql("select refill_long_period_store_credits() r")[0]["r"]
    assert default["refilled"] == [] or datetime.now(timezone.utc) >= datetime(2026, 11, 11, tzinfo=timezone.utc), default
    return {"monthly_untouched": True, "ended_untouched": True, "young_untouched": True, "boundary": "ok", "default_refilled": default["refilled"]}


@case
def t7_renewal_after_refill_does_not_stack():
    reset_db(new=True)
    u = uid(); long_offer(u, anchor_days_ago=45); spend_to(u, 100)
    sql("select refill_long_period_store_credits(50, '2000-01-01T00:00:00Z')")
    assert bal(u) == 4000
    purchase(u, "renew1", typ="RENEWAL", end="now() + interval '30 days'")  # オファー終了→通常の月額更新
    assert bal(u) == 4000, bal(u)
    # 通常更新の後は短い期間なので、補充の対象から外れる
    r = sql("select refill_long_period_store_credits(50, '2000-01-01T00:00:00Z') r")[0]["r"]
    assert r["refilled"] == [], r
    return {"balance_after_renewal": 4000, "refill_after_short_renewal": r["refilled"]}


@case
def t8_main_billing_issue_branch():
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
        def __init__(self, status_code=None, detail=None): super().__init__(detail)
    ns = {"uuid": uuid, "asyncio": asyncio, "logger": logging.getLogger("t"), "datetime": datetime, "timezone": timezone, "HTTPException": HTTPException}
    exec(compile(mod, "main.py(extract)", "exec"), ns)
    h = ns["_handle_revenuecat_event"]
    U = str(uuid.uuid4())
    base = {"type": "BILLING_ISSUE", "product_id": MAX_PID, "store": "APP_STORE", "environment": "PRODUCTION", "app_user_id": U,
            "expiration_at_ms": 1_800_000_000_000}
    asyncio.run(h({"event": {**base, "id": "b1", "grace_period_expiration_at_ms": 1_802_419_200_000}}, Admin()))
    asyncio.run(h({"event": {**base, "id": "b2"}}, Admin()))
    asyncio.run(h({"event": {**base, "id": "b3", "grace_period_expiration_at_ms": None}}, Admin()))
    ends = [datetime.fromisoformat(c[1]["p_period_end"]).timestamp() * 1000 for c in calls]
    assert ends == [1_802_419_200_000, 1_800_000_000_000, 1_800_000_000_000], ends
    assert all(c[0] == "handle_billing_issue" for c in calls)
    return {"uses_grace_end_when_present": True, "falls_back_to_expiration_at_ms": True}


@case
def t9_reconcile_does_not_expire_during_grace():
    now = datetime.now(timezone.utc)
    ms = lambda dt: int(dt.timestamp() * 1000)
    plan = PLAN["Max"]
    db = {"id": "m1", "plan_id": plan["id"], "current_period_end": (now - timedelta(days=3)).isoformat()}
    ids = {"prodX": MAX_PID}
    base = {"id": "sub1", "gives_access": True, "store": "app_store", "product_id": "prodX",
            "current_period_starts_at": ms(now - timedelta(days=33)), "current_period_ends_at": ms(now - timedelta(days=3))}
    grace = store_reconcile.decide([{**base, "status": "in_grace_period"}], ids, plans, db, now)
    assert (grace["action"], grace["reason"]) == ("none", "in_grace_period"), grace
    # 対照: 同じ状況でも status が active(=RC側が古いだけ)なら従来どおり期限切れ処理(4859e134 の実例)
    stale = store_reconcile.decide([{**base, "status": "active"}], ids, plans, db, now)
    assert stale["action"] == "expire", stale
    return {"in_grace_period": grace["reason"], "stale_active_control": stale["action"]}


def main():
    out, ok = [], True
    for fn in CASES:
        t0 = time.perf_counter()
        try:
            detail = fn()
            out.append({"case": fn.__name__, "ok": True, "ms": round((time.perf_counter() - t0) * 1000), "detail": detail})
            print(f"PASS {fn.__name__}")
        except Exception as e:
            import traceback; traceback.print_exc()
            ok = False; out.append({"case": fn.__name__, "ok": False, "error": repr(e)})
            print(f"FAIL {fn.__name__}: {e!r}")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = HERE / "results" / f"{stamp}_lifecycle_test.json"
    path.write_text(json.dumps({"run_at": stamp, "prod_writes": 0, "revenuecat_calls": 0, "cost_usd": 0, "all_passed": ok, "cases": out},
                               indent=2, ensure_ascii=False, default=str))
    print("saved", path); conn.close(); sys.exit(0 if ok else 1)


main()
