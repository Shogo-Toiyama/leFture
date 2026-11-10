"""RevenueCat REST API v2 の読み取り専用プローブ(書き込み無し・無料)。

確認したいこと:
  1. aliasのapp user id(Supabase uuid)で顧客を引けるか
  2. 顧客の契約中の商品ID・期限・自動更新・ストア・環境が取れるか
  3. 存在しないIDを引いたときに顧客が作られないか(404になるか)
実行: python3 probe_rc_api.py
"""
import json, sys, time, urllib.request, urllib.error, urllib.parse
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
env = {}
for line in open(ROOT / "lefture_backend" / ".env"):
    line = line.strip()
    if "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
KEY, PID = env["REVENUECAT_SECRET_API_KEY"], env["REVENUECAT_PROJECT_ID"]
BASE = f"https://api.revenuecat.com/v2/projects/{PID}"


def get(path):
    req = urllib.request.Request(BASE + path, headers={"Authorization": f"Bearer {KEY}", "Accept": "application/json"})
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            body, status, hdr = json.loads(r.read() or "null"), r.status, dict(r.headers)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            body = json.loads(raw)
        except Exception:
            body = raw
        status, hdr = e.code, dict(e.headers)
    ms = round((time.perf_counter() - t0) * 1000)
    rl = {k: v for k, v in hdr.items() if "ratelimit" in k.lower() or k.lower() == "retry-after"}
    return {"path": path, "status": status, "ms": ms, "rate_limit_headers": rl, "body": body}


USERS = {
    "friend_offer_code_alias": "fdae3630-75e5-4304-8b13-356254ec1f2f",
    "friend_offer_code_installed": "a29fe924-9adf-4baa-b84a-7c8906944d7b",
    "lefture_app_sandbox": "5be0566d-9b7a-499f-b7d2-f1c736fd5082",
    "shogo_after_transfer": "a0368beb-867a-48ce-a9a1-c1421a72fc65",
    "nonexistent": "00000000-0000-4000-8000-00000000dead",
}
out = {}
for label, uid in USERS.items():
    q = urllib.parse.quote(uid, safe="")
    out[label] = [get(f"/customers/{q}")]
    if out[label][0]["status"] == 200:
        for sub in ("/subscriptions", "/active_entitlements", "/aliases", "/purchases"):
            out[label].append(get(f"/customers/{q}{sub}"))
    for r in out[label]:
        print(label, r["path"].split("/customers/")[1][36:] or "(customer)", r["status"], f'{r["ms"]}ms')
# 存在しないIDを引いた後、もう一度引いて「作られていない」ことを確認
again = get(f"/customers/{USERS['nonexistent']}")
out["nonexistent_second_lookup"] = [again]
print("nonexistent (2nd)", again["status"])

stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
p = HERE / "results" / f"{stamp}_rc_v2_probe.json"
p.write_text(json.dumps(out, indent=2, ensure_ascii=False))
print("saved", p)
