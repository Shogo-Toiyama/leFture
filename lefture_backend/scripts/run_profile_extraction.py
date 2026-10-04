"""
自分像プロフィール(ロードマップ9章)をローカルから1ユーザー分だけ流す確認用スクリプト。
本番ではpatrol → Cloud Tasks → /worker/profile-observe・/worker/profile-consolidate が呼ぶ処理を、
同じ関数(app/services/profile_store.py)でその場で順に呼ぶ。DBは .env の Supabase(本番)を使う。

テストに使ってよいのは本人のアカウントだけ(lefture.app@gmail.com = 5be0566d-…)。他のユーザーでは使わない。

実行:
  python scripts/run_profile_extraction.py --user-id 5be0566d-9b7a-499f-b7d2-f1c736fd5082 --dry-list
  python scripts/run_profile_extraction.py --user-id 5be0566d-9b7a-499f-b7d2-f1c736fd5082 --max-threads 5
  python scripts/run_profile_extraction.py --user-id ... --consolidate-only
"""

import argparse
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parents[1] / ".env")

from app.core.supabase import get_supabase_client  # noqa: E402
from app.services import profile_store  # noqa: E402


def _pending_threads(admin_client, user_id: str, limit: int) -> list[dict]:
    rows = admin_client.table("chat_threads").select("id, title, last_message_at, profile_observed_until") \
        .eq("user_id", user_id).is_("deleted_at", "null").order("last_message_at").execute().data or []
    return [r for r in rows if not r.get("profile_observed_until") or r["profile_observed_until"] < r["last_message_at"]][:limit]


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--user-id", required=True)
    ap.add_argument("--max-threads", type=int, default=5)
    ap.add_argument("--dry-list", action="store_true", help="観察する予定のスレッドを表示するだけ")
    ap.add_argument("--consolidate-only", action="store_true")
    args = ap.parse_args()

    admin_client = get_supabase_client()
    if not args.consolidate_only:
        threads = _pending_threads(admin_client, args.user_id, args.max_threads)
        print(f"{len(threads)} thread(s) to observe")
        for t in threads:
            print(f"  - {t['id']} {t.get('title')!r} last={t['last_message_at']}")
        if args.dry_list:
            return
        for t in threads:
            result = await profile_store.observe_thread_task(t["id"])
            print(f"observe {t['id']}: {result}")

    result = await profile_store.consolidate_user_task(args.user_id)
    print(f"consolidate: {result}")


if __name__ == "__main__":
    asyncio.run(main())
