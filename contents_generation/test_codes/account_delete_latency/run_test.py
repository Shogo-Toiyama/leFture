"""アカウント削除(/auth/delete-account)が遅い原因の計測。

本番の削除関数(main._hard_delete_user_data / _hard_delete_lecture)をそのまま、
**存在しないID(ランダムなUUID)**で実行し、DB(PostgREST)とR2への1回ごとの往復時間を測る。
どのDELETEも0行に一致するので、本番では何も消えない。auth.users の削除(GoTrue)は呼ばない。

  --dry-run : ネットワークに出ず、呼び出しの回数と順番だけを数える
  (なし)    : 本番のSupabase/R2に対して実行(0行一致のDELETEとR2のlistのみ)。費用$0。

加えて、本番の lectures 件数(ユーザーごと、読み取りのみ)から、
「この往復時間なら、講義が何件あると30秒(アプリのタイムアウト)を超えるか」を見積もる。
注意: 計測はこのPCから。本番(Cloud Run us-west1)からの往復時間とは異なる。
"""
import asyncio
import json
import statistics
import sys
import time
import uuid
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "lefture_backend"))
DRY_RUN = "--dry-run" in sys.argv
REPEAT = 3

import os  # noqa: E402
os.chdir(ROOT / "lefture_backend")
import app.main as m  # noqa: E402  (本番コード)
from app.core.r2_storage import storage_service  # noqa: E402
import postgrest._sync.request_builder as rb  # noqa: E402

CALLS = []  # (kind, label, ms)

_orig_send = rb.send_with_retry


def timed_send(req):
    label = f"{getattr(req, 'http_method', '?')} {str(req.path).split('/rest/v1/')[-1]}"
    if DRY_RUN:
        CALLS.append(("db", label, 0.0))

        import httpx
        return httpx.Response(200, json=[], request=httpx.Request("GET", "http://dry-run.invalid/"))  # 0行の応答を装う
    t = time.perf_counter()
    try:
        return _orig_send(req)
    finally:
        CALLS.append(("db", label, (time.perf_counter() - t) * 1000))


rb.send_with_retry = timed_send

_orig_prefix = storage_service.delete_prefix


def timed_prefix(prefix):
    if DRY_RUN:
        CALLS.append(("r2", "delete_prefix", 0.0))
        return 0
    t = time.perf_counter()
    try:
        return _orig_prefix(prefix)
    finally:
        CALLS.append(("r2", "delete_prefix", (time.perf_counter() - t) * 1000))


storage_service.delete_prefix = timed_prefix


def run_once():
    admin = m.get_supabase_client()
    fake_uid, fake_lecture = str(uuid.uuid4()), str(uuid.uuid4())
    CALLS.clear()
    t = time.perf_counter()
    asyncio.run(m._hard_delete_lecture(admin, fake_uid, fake_lecture))
    lecture_ms = (time.perf_counter() - t) * 1000
    lecture_calls = list(CALLS)
    CALLS.clear()
    t = time.perf_counter()
    asyncio.run(m._hard_delete_user_data(admin, fake_uid))
    user_ms = (time.perf_counter() - t) * 1000
    return {"lecture_ms": lecture_ms, "lecture_calls": lecture_calls,
            "user_ms": user_ms, "user_calls": list(CALLS)}


runs = [run_once() for _ in range(1 if DRY_RUN else REPEAT)]
per_lecture_ms = statistics.median(r["lecture_ms"] for r in runs)
user_base_ms = statistics.median(r["user_ms"] for r in runs)
n_lecture_calls = len(runs[0]["lecture_calls"])
n_user_calls = len(runs[0]["user_calls"])

per_call = defaultdict(list)
for r in runs:
    for kind, label, ms in r["lecture_calls"] + r["user_calls"]:
        per_call[f"{kind} {label}"].append(ms)
per_call_summary = {k: round(statistics.median(v), 1) for k, v in sorted(per_call.items())}

# 本番の講義件数の分布(読み取りのみ。ユーザーIDは出力しない)
lecture_counts = []
if not DRY_RUN:
    admin = m.get_supabase_client()
    rows = admin.table("lectures").select("user_id").execute().data
    counts = defaultdict(int)
    for row in rows:
        counts[row["user_id"]] += 1
    lecture_counts = sorted(counts.values())


def projected_s(n):
    return round((user_base_ms + n * per_lecture_ms) / 1000, 1)


projection = None
if lecture_counts:
    projection = {
        "users_with_lectures": len(lecture_counts),
        "lectures_per_user_median": statistics.median(lecture_counts),
        "lectures_per_user_max": max(lecture_counts),
        "projected_seconds_median_user": projected_s(statistics.median(lecture_counts)),
        "projected_seconds_max_user": projected_s(max(lecture_counts)),
        "lectures_to_exceed_30s": int((30000 - user_base_ms) // per_lecture_ms) + 1,
        "users_over_30s": sum(1 for n in lecture_counts if projected_s(n) > 30),
    }

# ------------------------------------------------------------------ 変更後(まとめて削除)の計測
# _hard_delete_user_data は講義を _hard_delete_lectures_bulk で消す。存在しない講義IDを
# N件渡して(0行一致)、N件の講義を持つユーザーの削除時間を見積もる。
after = {}
if hasattr(m, "_hard_delete_lectures_bulk"):
    admin = m.get_supabase_client()
    for n in (1, 7, 84):
        times, calls = [], 0
        for _ in range(1 if DRY_RUN else REPEAT):
            CALLS.clear()
            t = time.perf_counter()
            asyncio.run(m._hard_delete_lectures_bulk(admin, [str(uuid.uuid4()) for _ in range(n)]))
            times.append((time.perf_counter() - t) * 1000)
            calls = len(CALLS)
        bulk_ms = statistics.median(times)
        after[f"lectures_{n}"] = {
            "sequential_calls": calls,
            "bulk_lectures_ms_median": round(bulk_ms, 1),
            # ユーザー単位の削除(講義0件の _hard_delete_user_data。R2の {uid}/ 削除を含む)を足した見積もり
            "projected_total_seconds": round((bulk_ms + user_base_ms) / 1000, 1),
            "before_projected_seconds": projected_s(n),
        }
summary_after = after

summary = {
    "dry_run": DRY_RUN,
    "measured_from": "developer PC (not Cloud Run)",
    "repeat": len(runs),
    "sequential_calls_per_lecture": n_lecture_calls,
    "sequential_calls_user_level_excluding_lectures_and_auth": n_user_calls,
    "per_lecture_ms_median": round(per_lecture_ms, 1),
    "user_level_ms_median": round(user_base_ms, 1),
    "per_call_ms_median": per_call_summary,
    "projection": projection,
    "after_bulk_delete": summary_after,
    "writes_to_production": "DELETEs matching 0 rows only (random UUIDs); no auth.users delete",
    "cost_usd": 0,
}
stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
out = HERE / "results" / f"{stamp}_account_delete_latency{'_dryrun' if DRY_RUN else ''}.json"
out.write_text(json.dumps(summary, indent=1, ensure_ascii=False))
print(json.dumps(summary, indent=1, ensure_ascii=False))
print("->", out.relative_to(ROOT))
