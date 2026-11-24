"""
Hydrogen 差し替え時の講義1件あたりの原価と損益(読み取りのみ。API 課金なし)。

データ: 本番の usage_records(job_id 付き)と credit_transactions(reason=LECTURE_ANALYSIS)。
  - Gemini 2.5 Flash 時代: 2026-10-10 〜 2026-11-04 / Haiku 時代: 2026-11-08 以降(切り替えは 2026-11-05 のコミット 4dfc2d7)
Hydrogen の倍率: 第1ラウンドの同条件比較(各1回)の実測。RC 14.3 / DN 14.1 / FF 19.7(最小12・最大20で感度も出す)。
売上: 1クレジットの手取り。Max($19.99, 4,000 クレジット/月, 手数料15%)=$0.004248 は credits.py のコメントの前提。
      Lite / Core の価格は DB にもコードにも無いので、損益分岐の「必要な手取り/クレジット」だけを出す。

  .venv/bin/python contents_generation/test_codes/gemini4_hydrogen_swap/cost_analysis.py
"""
import collections
import json
import os
import statistics as st
from datetime import datetime
from pathlib import Path

from dotenv import load_dotenv
from supabase import create_client

HERE = Path(__file__).resolve().parent
load_dotenv(HERE.parents[2] / "lefture_backend" / ".env")
c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])

FACTORS = {"rc": 14.3, "dn": 14.1, "ff": 19.7}
TASKS = {"rc": "REVIEW_CARD_GENERATION", "dn": "DETAIL_CONTENTS_GENERATION", "ff": "FUN_FACTS_GENERATION"}
MAX_NET_PER_CREDIT = 19.99 * 0.85 / 4000
CHAT_MARKUP, CREDITS_PER_USD = 1.5, 300


def fetch(table, sel, since, until, extra=None):
    out, off = [], 0
    while True:
        q = c.table(table).select(sel).gte("created_at", since).lt("created_at", until)
        if extra:
            q = extra(q)
        r = q.range(off, off + 999).execute().data
        out += r
        off += 1000
        if len(r) < 1000:
            return out


def jobs_between(since, until):
    ur = fetch("usage_records", "job_id,cost_breakdown", since, until, lambda q: q.not_.is_("job_id", "null"))
    tx = fetch("credit_transactions", "related_job_id,metadata", since, until, lambda q: q.eq("reason", "LECTURE_ANALYSIS"))
    meta = {t["related_job_id"]: t["metadata"] for t in tx}
    per = collections.defaultdict(lambda: collections.defaultdict(float))
    for u in ur:
        if u["job_id"] in meta:
            for b in u["cost_breakdown"] or []:
                per[u["job_id"]][(b.get("task_type"), b.get("resource"))] += b["cost_usd"]
    rows = []
    for j, d in per.items():
        tok = lambda tt: sum(v for (t, r), v in d.items() if t == tt and r != "cloudrun/self")
        rows.append({"credits": meta[j].get("credits"), "total": sum(d.values()),
                     **{k: tok(tt) for k, tt in TASKS.items()}})
    return rows


def tier_mean(rows, credits, key):
    s = [r[key] for r in rows if r["credits"] == credits]
    return st.mean(s) if s else None


def main():
    old = jobs_between("2026-10-10T00:00:00+00:00", "2026-11-05T00:00:00+00:00")
    new = jobs_between("2026-11-08T00:00:00+00:00", "2026-12-01T00:00:00+00:00")
    out = {"created_at": datetime.now().isoformat(timespec="seconds"), "factors": FACTORS,
           "max_net_per_credit": MAX_NET_PER_CREDIT, "tiers": {}}
    print(f"jobs: 2.5 Flash era {len(old)}, Haiku era {len(new)}; Max net/credit ${MAX_NET_PER_CREDIT:.6f}")
    for cr in (60, 80, 100):
        n = sum(1 for r in new if r["credits"] == cr)
        if not n:
            continue
        revenue = cr * MAX_NET_PER_CREDIT
        base = tier_mean(new, cr, "total")
        parts = {k: tier_mean(new, cr, k) for k in TASKS}
        old_total = tier_mean(old, cr, "total")
        old_parts = sum(tier_mean(old, cr, k) or 0 for k in TASKS) if old_total else None
        def scen(f):  # f: k -> multiplier
            return base - sum(parts.values()) + sum(parts[k] * f[k] for k in TASKS)
        full = scen(FACTORS)
        lo, hi = scen({k: 12 for k in TASKS}), scen({k: 20 for k in TASKS})
        combos = {name: scen({k: (FACTORS[k] if k in keys else 1) for k in TASKS})
                  for name, keys in {"FFのみ": ["ff"], "RCのみ": ["rc"], "DNのみ": ["dn"], "RC+FF": ["rc", "ff"],
                                     "DN+FF": ["dn", "ff"], "RC+DN": ["rc", "dn"], "RC+DN+FF": ["rc", "dn", "ff"]}.items()}
        t = {"n_haiku_era": n, "revenue_at_max_net": revenue, "cost_2_5_flash": old_total, "cost_haiku": base,
             "haiku_three_tasks": sum(parts.values()), "flash_three_tasks": old_parts, "parts_haiku": parts,
             "hydrogen_cost": full, "hydrogen_low12": lo, "hydrogen_high20": hi, "combos": combos,
             "breakeven_net_per_credit_hydrogen": full / cr, "breakeven_net_per_credit_haiku": base / cr}
        out["tiers"][cr] = t
        m = lambda cost: (revenue - cost) / revenue * 100
        print(f"\n[{cr} credits] revenue@Max ${revenue:.3f} | 2.5Flash ${old_total or 0:.3f} (RC+DN+FF ${old_parts or 0:.3f}) | "
              f"Haiku ${base:.3f} (RC+DN+FF ${sum(parts.values()):.3f}; RC {parts['rc']:.4f} DN {parts['dn']:.4f} FF {parts['ff']:.4f})")
        print(f"   Hydrogen ${full:.3f} (x12 ${lo:.3f} / x20 ${hi:.3f}) margin {m(full):.0f}% (range {m(hi):.0f}..{m(lo):.0f}%); "
              f"break-even net/credit ${full / cr:.5f} (Haiku ${base / cr:.5f})")
        for name, v in combos.items():
            print(f"   {name:9} ${v:.3f} margin {m(v):.0f}%")

    # チャット: 1メッセージ(2026-11-19 の本番ターン)。原価はそのターンの usage.records(振り分け役 + 回答役 + Cloud Run)
    haiku_turn = 0.0007817500000000001 + 3.354e-05 + 0.0023251 + 0.00018897
    hyd_answer = 0.018373
    hyd_turn = haiku_turn - 0.0023251 + hyd_answer
    out["chat"] = {"haiku_turn_usd": haiku_turn, "hydrogen_turn_usd": hyd_turn,
                   "haiku_credits": haiku_turn * CHAT_MARKUP * CREDITS_PER_USD,
                   "hydrogen_credits": hyd_turn * CHAT_MARKUP * CREDITS_PER_USD,
                   "hydrogen_cost_over_revenue_at_max": hyd_turn / (hyd_turn * CHAT_MARKUP * CREDITS_PER_USD * MAX_NET_PER_CREDIT),
                   "min_net_per_credit_for_chat_breakeven": 1 / (CHAT_MARKUP * CREDITS_PER_USD)}
    print("\nchat:", json.dumps(out["chat"], indent=1))
    d = HERE / "results" / f"{datetime.now():%Y%m%d_%H%M%S}_cost_analysis"
    d.mkdir(parents=True, exist_ok=True)
    (d / "summary.json").write_text(json.dumps(out, ensure_ascii=False, indent=1, default=float), encoding="utf-8")
    print("saved", d)


if __name__ == "__main__":
    main()
