"""
複数の実行(results/<tag>/)をまとめて比べる。同じ設定を何回か回したときの揺れと、役割ごとの原価を見る。

実行: python compare.py lunaA_r1 lunaA_r2 lunaA_r3 lunaB_r1 ...
      python compare.py --prefix lunaA_ lunaB_     # 前方一致でまとめる
"""

import argparse
import json
from pathlib import Path

RESULTS_DIR = Path(__file__).resolve().parent / "results"


def load(tag: str) -> list[dict]:
    return [json.loads(p.read_text(encoding="utf-8")) for p in sorted((RESULTS_DIR / tag).glob("p*.json"))]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("tags", nargs="*")
    ap.add_argument("--prefix", nargs="*", default=[])
    args = ap.parse_args()
    groups: dict[str, list[str]] = {}
    for t in args.tags:
        groups[t] = [t]
    for pre in args.prefix:
        groups[pre.rstrip("_")] = sorted(d.name for d in RESULTS_DIR.iterdir() if d.is_dir() and d.name.startswith(pre))

    print(f"{'group':<14}{'runs':>5}{'false_promo':>13}{'missed':>8}{'obs_viol':>9}{'mech':>6}{'passed':>12}"
          f"{'$/6人':>9}{'observer':>10}{'consol.':>9}{'cover':>8}{'embed':>8}")
    for name, tags in groups.items():
        runs = [load(t) for t in tags]
        runs = [r for r in runs if r]
        if not runs:
            continue
        def total(key):
            return [sum(sc["summary"][key] for sc in run) for run in runs]
        def cost(role=None):
            vals = [sum(sc["cost_usd"]["by_role"][role] if role else sc["cost_usd"]["pipeline_tokens"] for sc in run) for run in runs]
            return sum(vals) / len(vals)
        fp, missed, ov, mech = total("false_promotions"), total("missed"), total("observation_violations"), total("mechanical_failures")
        passed = [f"{a}/{b}" for a, b in zip(total("passed"), total("total"))]
        print(f"{name:<14}{len(runs):>5}{str(fp):>13}{str(missed):>8}{str(ov):>9}{str(mech):>6}{' '.join(passed):>12}"
              f"{cost():>9.4f}{cost('observer'):>10.4f}{cost('consolidator'):>9.4f}{cost('cover'):>8.4f}{cost('embedding'):>8.4f}")
        # 間違って上げた中身(どの実行の、どのシナリオか)
        for t, run in zip(tags, runs):
            for sc in run:
                for g in sc["grades"]:
                    for x in g["results"]:
                        if not x["ok"] and x["type"] == "must_not" and g["target"] != "observations":
                            print(f"    ✗ {t} {sc['scenario_id']} {g['event']} {g['target']}: {x['expectation'][:60]} — {x['note'][:100]}")


if __name__ == "__main__":
    main()
