"""Verify the PostgREST queries used by the Flutter lazy lecture sync, read-only.

Mirrors the queries in user_interface/lib/application/sync/*:
  - recent lecture ids  : lectures where user_id, deleted_at is null, order lecture_datetime desc nulls last, limit 20
  - scoped full pull    : <child table> where user_id and lecture_id in (recent ids)
  - announcements full  : user_id and (completed_at is null OR lecture_id in (recent ids))
  - flagged rows        : user_id and (metadata->>saved = true OR metadata->>reaction in (like, dislike))

For the users with the most lectures, it compares the payload of the old user-wide
full pull against the new scoped one. No writes. Run with --dry-run to only print
the plan without touching the network.

Usage:
  .venv/bin/python contents_generation/test_codes/lazy_lecture_sync/verify_scoped_queries.py [--dry-run] [--users 3]
"""

import argparse
import collections
import datetime as dt
import json
import os
import sys
import time

RECENT_LECTURE_COUNT = 20
CHILD_TABLES = ["lecture_topics", "deep_notes", "review_cards", "keywords", "fun_facts"]
FLAG_TABLES = ["review_cards", "deep_notes", "keywords", "fun_facts"]
FLAG_FILTER = "metadata->>saved.eq.true,metadata->>reaction.in.(like,dislike)"


def size_kb(rows):
    return round(len(json.dumps(rows)) / 1024, 1)


def fetch_all(query_builder):
    out, start = [], 0
    while True:
        rows = query_builder().range(start, start + 999).execute().data
        out += rows
        if len(rows) < 1000:
            return out
        start += 1000


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--users", type=int, default=3)
    args = ap.parse_args()

    plan = {
        "recent_lecture_count": RECENT_LECTURE_COUNT,
        "child_tables": CHILD_TABLES,
        "flag_tables": FLAG_TABLES,
        "flag_filter": FLAG_FILTER,
        "users": args.users,
    }
    print("PLAN:", json.dumps(plan))
    if args.dry_run:
        print("dry-run: no network calls")
        return

    from dotenv import load_dotenv
    load_dotenv("lefture_backend/.env")
    from supabase import create_client

    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])

    lectures = fetch_all(lambda: c.table("lectures").select("id,user_id,deleted_at"))
    per_user = collections.Counter(l["user_id"] for l in lectures if l["deleted_at"] is None)
    users = [u for u, _ in per_user.most_common(args.users)]

    report = {"plan": plan, "users": []}
    for rank, uid in enumerate(users, 1):
        u = {"rank": rank, "live_lectures": per_user[uid], "tables": {}}
        t0 = time.perf_counter()
        recent = (
            c.table("lectures").select("id").eq("user_id", uid).is_("deleted_at", "null")
            .order("lecture_datetime", desc=True, nullsfirst=False).limit(RECENT_LECTURE_COUNT)
            .execute().data
        )
        ids = [r["id"] for r in recent]
        u["recent_ids_ms"] = round((time.perf_counter() - t0) * 1000)
        u["recent_ids_count"] = len(ids)

        old_total = new_total = 0.0
        for t in CHILD_TABLES:
            old = fetch_all(lambda: c.table(t).select("*").eq("user_id", uid))
            new = fetch_all(lambda: c.table(t).select("*").eq("user_id", uid).in_("lecture_id", ids))
            assert all(r["lecture_id"] in ids for r in new), f"{t}: scoped query leaked rows"
            u["tables"][t] = {"old_rows": len(old), "old_kb": size_kb(old), "new_rows": len(new), "new_kb": size_kb(new)}
            old_total += size_kb(old)
            new_total += size_kb(new)

        old_ann = fetch_all(lambda: c.table("announcements").select("*").eq("user_id", uid))
        or_filter = f"completed_at.is.null,lecture_id.in.({','.join(ids)})"
        new_ann = fetch_all(lambda: c.table("announcements").select("*").eq("user_id", uid).or_(or_filter))
        expected = [a for a in old_ann if a["completed_at"] is None or a["lecture_id"] in ids]
        assert len(expected) == len(new_ann), f"announcement or-filter mismatch {len(expected)} vs {len(new_ann)}"
        active_outside = sum(1 for a in old_ann if a["completed_at"] is None and a["lecture_id"] not in ids)
        u["tables"]["announcements"] = {
            "old_rows": len(old_ann), "old_kb": size_kb(old_ann),
            "new_rows": len(new_ann), "new_kb": size_kb(new_ann),
            "active_rows_from_older_lectures": active_outside,
        }
        old_total += size_kb(old_ann)
        new_total += size_kb(new_ann)

        flagged = {}
        for t in FLAG_TABLES:
            rows = fetch_all(lambda: c.table(t).select("*").eq("user_id", uid).or_(FLAG_FILTER))
            all_rows = fetch_all(lambda: c.table(t).select("id,lecture_id,metadata").eq("user_id", uid))
            exp = [r for r in all_rows if (r.get("metadata") or {}).get("saved") is True
                   or (r.get("metadata") or {}).get("reaction") in ("like", "dislike")]
            assert len(exp) == len(rows), f"{t}: flag filter mismatch {len(exp)} vs {len(rows)}"
            flagged[t] = {"rows": len(rows), "kb": size_kb(rows),
                          "outside_recent": sum(1 for r in rows if r["lecture_id"] not in ids)}
        u["flagged"] = flagged
        u["old_full_pull_kb"] = round(old_total, 1)
        u["new_full_pull_kb"] = round(new_total, 1)
        report["users"].append(u)
        print(json.dumps(u, ensure_ascii=False))

    stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    out = os.path.join(os.path.dirname(__file__), "results", f"scoped_queries_{stamp}.json")
    with open(out, "w") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    print("saved", out)


if __name__ == "__main__":
    sys.exit(main())
