"""Run the fixed holdout suite against the already-tested priority candidate."""

import argparse
import asyncio
from datetime import datetime
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "router_web_followups"))
from evaluate import Case, TZ, one, summarize


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--fixtures", type=Path, default=HERE / "cases.json",
                        help="Use a separate labeled suite and save results beside it.")
    parser.add_argument("--baseline-case", action="append", default=[],
                        help="Run the original prompt on a named case. Repeat to compare other selected cases.")
    args = parser.parse_args()
    fixtures = json.loads(args.fixtures.read_text())
    assert fixtures and len({row["name"] for row in fixtures}) == len(fixtures)
    assert all(type(row["expected"]) is bool for row in fixtures)
    requested = set(args.baseline_case)
    if unknown := requested - {row["name"] for row in fixtures}:
        parser.error(f"unknown case names: {', '.join(sorted(unknown))}")
    selected = [row for row in fixtures if not requested or row["name"] in requested]
    variant = "current_31" if args.baseline_case else "priority_31"
    stamp = datetime.now(TZ).strftime("%Y-%m-%dT%H%M%S%z")
    tag = "dry-run" if args.dry_run else "live"
    path = args.fixtures.parent / "results" / f"{stamp}-{variant}-{tag}.json"
    rows = []
    for fixture in selected:
        case = Case(**{key: val for key, val in fixture.items() if key != "gold_reason"})
        row = await one(case, variant, args.dry_run)
        rows.append(row)
        print(f"{case.name}: expected={case.expected} actual={row['actual']} fallback={row['fallback']}", flush=True)
        path.write_text(json.dumps({"mode": tag, "summary": summarize(rows), "trials": rows}, indent=2) + "\n")
    if args.dry_run:
        assert all(row["expected"] == row["actual"] and not row["fallback"] and not row["provider_usd"] for row in rows)
    print(json.dumps(summarize(rows), indent=2))
    print(path.name, flush=True)


if __name__ == "__main__":
    asyncio.run(main())
