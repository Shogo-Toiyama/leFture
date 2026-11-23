"""手動同期(/billing/sync-store-subscription)が、直前の summary 突き合わせに間引かれる問題の確認。

再現したいこと(2026-11-23 Sandbox):
  1. サインアップ直後に /billing/summary の突き合わせが DB の枠(claim_store_sync_slot)を使う。
     この時点では RevenueCat 上に契約が無い。
  2. 約20秒後、ログイン直後の syncPurchases で TRANSFER が起き、契約がこのユーザーに移る。
     アプリが手動同期を呼ぶが、同じ DB の枠(30秒)に間引かれて何もしない → DB はプラン無しのまま。

本番コードの store_reconcile.reconcile_user() をそのまま動かす。DB と RevenueCat API はフェイク
(プラン定義だけ本番 Supabase から読み取り)。本番への書き込み: 0件。外部API: 0回。費用: $0。
実行: .venv/bin/python contents_generation/test_codes/manual_sync_throttle/run_test.py [--dry-run]
"""
import asyncio
import json
import sys
import time
import uuid
from datetime import datetime, timezone, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "lefture_backend"))

import os  # noqa: E402
from dotenv import load_dotenv  # noqa: E402
load_dotenv(ROOT / "lefture_backend" / ".env")
# is_configured() を通すためのダミー(フェイクに差し替えるので実際には使われない)
os.environ.setdefault("REVENUECAT_SECRET_API_KEY", "fake-not-used")
os.environ.setdefault("REVENUECAT_PROJECT_ID", "fake-not-used")

from app.services.helpers import revenuecat_api, store_reconcile  # noqa: E402

DRY_RUN = "--dry-run" in sys.argv

# ------------------------------------------------------------------ 本番のプラン定義(読み取りのみ)
if DRY_RUN:
    PLANS = [{"id": "plan-max", "name": "Max", "claim_mode": "store_purchase", "tier_level": 3,
              "store_product_id": "com.lefture.app.sub.premium", "stripe_price_id": None, "stripe_product_id": None}]
else:
    from supabase import create_client
    _c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    PLANS = _c.table("subscription_plans").select(
        "id, name, claim_mode, tier_level, store_product_id, stripe_price_id, stripe_product_id").execute().data
MAX = next(p for p in PLANS if p["store_product_id"] == "com.lefture.app.sub.premium")

# ------------------------------------------------------------------ 時計(秒)
CLOCK = {"t": 1000.0}
store_reconcile.time.monotonic = lambda: CLOCK["t"]

# ------------------------------------------------------------------ フェイクDB
class Res:
    def __init__(self, data):
        self.data = data


class FakeDB:
    def __init__(self):
        self.sync_checked_at = {}     # user_id -> fake time
        self.mappings = {}            # user_id -> {"id","plan_id","current_period_end"}
        self.rpc_log = []

    # claim_store_sync_slot と同じ意味(checked_at が min_interval より古ければ更新して True)
    def claim(self, uid, interval):
        last = self.sync_checked_at.get(uid)
        if last is None or last < CLOCK["t"] - interval:
            self.sync_checked_at[uid] = CLOCK["t"]
            return True
        return False


class Query:
    def __init__(self, db, table):
        self.db, self.table, self.filters = db, table, {}

    def select(self, *_a, **_k): return self
    def insert(self, _row): return self
    def update(self, _row): return self
    def order(self, *_a, **_k): return self
    def limit(self, *_a): return self
    def single(self): return self

    def eq(self, k, v):
        self.filters[k] = v
        return self

    def execute(self):
        if self.table == "subscription_plans":
            return Res(PLANS)
        if self.table == "user_subscription_mappings":
            m = self.db.mappings.get(self.filters.get("user_id"))
            return Res([m] if m else [])
        return Res([])


class RPC:
    def __init__(self, db, name, params):
        self.db, self.name, self.params = db, name, params

    def execute(self):
        self.db.rpc_log.append(self.name)
        if self.name == "claim_store_sync_slot":
            return Res(self.db.claim(self.params["p_user_id"], self.params["p_min_interval_seconds"]))
        if self.name == "grant_store_subscription_credits":
            plan = next(p for p in PLANS if p["store_product_id"] == self.params["p_product_id"])
            self.db.mappings[self.params["p_user_id"]] = {
                "id": "m1", "plan_id": plan["id"], "current_period_end": self.params["p_period_end"]}
        return Res(None)


class FakeAdmin:
    def __init__(self, db): self.db = db
    def table(self, name): return Query(self.db, name)
    def rpc(self, name, params): return RPC(self.db, name, params)


# ------------------------------------------------------------------ フェイク RevenueCat
RC = {}  # user_id -> list of RC v2 subscription items
now = datetime.now(timezone.utc)
TRANSFERRED_SUB = {
    # 形は RevenueCat v2 の subscription(2026-11-23 Sandbox の実際の契約と同じ商品・状態)
    "id": "sub_test_transferred", "product_id": "prod_rc_max", "store": "app_store",
    "gives_access": True, "status": "trialing", "environment": "sandbox",
    "auto_renewal_status": "will_not_renew",
    "current_period_starts_at": int((now - timedelta(minutes=30)).timestamp() * 1000),
    "current_period_ends_at": int((now + timedelta(hours=1)).timestamp() * 1000),
}


async def fake_fetch(uid): return RC.get(uid, [])
async def fake_store_id(pid): return {"prod_rc_max": "com.lefture.app.sub.premium"}.get(pid)

revenuecat_api.fetch_customer_subscriptions = fake_fetch
revenuecat_api.get_store_identifier = fake_store_id

SUMMARY = dict(min_interval_seconds=6 * 3600, reason="summary", use_local_skip=False)
MANUAL_OLD = dict(min_interval_seconds=30, reason="manual")                      # 変更前の呼び出し
MANUAL_NEW = dict(min_interval_seconds=30, reason="manual", use_db_slot=False)   # 変更後の呼び出し(main.py)


def run(db, uid, kw):
    t0 = time.perf_counter()
    r = asyncio.run(store_reconcile.reconcile_user(FakeAdmin(db), uid, **kw))
    return {"at_s": CLOCK["t"] - 1000, "action": r.get("action"), "reason": r.get("reason"),
            "latency_ms": round((time.perf_counter() - t0) * 1000, 2)}


def scenario(manual_kw):
    """サインアップ時の summary → 20秒後に TRANSFER → 手動同期。"""
    db, uid = FakeDB(), str(uuid.uuid4())
    store_reconcile._LOCAL_MANUAL_CHECKED_AT.clear()
    CLOCK["t"] = 1000.0
    steps = [("summary_at_signup", run(db, uid, SUMMARY))]
    CLOCK["t"] += 20
    RC[uid] = [TRANSFERRED_SUB]
    steps.append(("manual_after_transfer", run(db, uid, manual_kw)))
    return steps, db.mappings.get(uid)


results = {}

# A. 変更前: 手動が summary の枠に間引かれ、DB にプランが付かない(バグの再現)
steps, mapping = scenario(MANUAL_OLD)
results["A_before_fix"] = {"steps": steps, "db_plan": mapping and mapping["plan_id"]}
assert steps[1][1]["reason"] == "throttled" and mapping is None, results["A_before_fix"]

# B. 変更後: 手動は DB の枠を使わないので、TRANSFER 直後に Max が付く
steps, mapping = scenario(MANUAL_NEW)
results["B_after_fix"] = {"steps": steps, "db_plan": mapping and mapping["plan_id"]}
assert steps[1][1]["action"] == "grant" and steps[1][1]["reason"] == "missing_plan", results["B_after_fix"]
assert mapping and mapping["plan_id"] == MAX["id"], results["B_after_fix"]

# C. 手動の連打は 30 秒間引かれる(RevenueCat API を連打させない)。31 秒後は通る
db, uid = FakeDB(), str(uuid.uuid4())
store_reconcile._LOCAL_MANUAL_CHECKED_AT.clear()
RC[uid] = []
CLOCK["t"] = 1000.0
c = [run(db, uid, MANUAL_NEW)]
CLOCK["t"] += 5
c.append(run(db, uid, MANUAL_NEW))
CLOCK["t"] += 26
c.append(run(db, uid, MANUAL_NEW))
results["C_manual_throttle"] = c
assert [x["reason"] for x in c] == ["no_active_subscription", "throttled", "no_active_subscription"], c

# D. summary は従来どおり DB の枠(6時間)で間引かれる。手動は summary の枠を消費しない
db, uid = FakeDB(), str(uuid.uuid4())
store_reconcile._LOCAL_MANUAL_CHECKED_AT.clear()
RC[uid] = []
CLOCK["t"] = 1000.0
d = [run(db, uid, MANUAL_NEW), run(db, uid, SUMMARY)]
CLOCK["t"] += 60
d.append(run(db, uid, SUMMARY))
results["D_summary_unchanged"] = d
assert [x["reason"] for x in d] == ["no_active_subscription", "no_active_subscription", "throttled"], d

stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
out = HERE / "results" / f"{stamp}_manual_sync_throttle{'_dryrun' if DRY_RUN else ''}.json"
out.write_text(json.dumps({"dry_run": DRY_RUN, "plans_source": "mock" if DRY_RUN else "production subscription_plans (read-only)",
                           "external_api_calls": 0, "cost_usd": 0, "results": results}, indent=1, ensure_ascii=False))
print(json.dumps(results, indent=1, ensure_ascii=False))
print("ALL PASSED ->", out.relative_to(ROOT))
