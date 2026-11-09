#!/usr/bin/env python3
"""
既存のトピック画像に、縮小版(192x256 WebP, `topic_N_thumb192.webp`)と講義の
表紙サムネイル(`lectures.metadata.cover_thumb_path`)を後から付けるバックフィル。

新しく解析される講義は、IMAGE_RENDERING/FINALIZE_JOBが同じものを作る
(app/services/logic/image_rendering.py の ensure_thumbnail と同じ処理を使う)。
一度きりのローカル実行専用。AIは使わない(R2の読み書きとSupabaseの更新だけ)。

使い方 (lefture_backend/ から実行):
    python scripts/backfill_image_thumbnails.py
        ドライラン(既定)。何も書き込まず、作る予定の件数だけ表示する。

    python scripts/backfill_image_thumbnails.py --apply --user-id <uid>
        1ユーザーだけ実際に書き込む。全体の前の確認用。

    python scripts/backfill_image_thumbnails.py --apply
        全ユーザー分を書き込む。

途中で止めても安全: 既にある縮小版・既に設定済みの表紙はスキップするので、
再実行すると残りだけが処理される。
"""
import argparse
import collections
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from dotenv import load_dotenv  # noqa: E402

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

from app.core.r2_storage import storage_service  # noqa: E402
from app.core.supabase import get_supabase_client  # noqa: E402
from app.services.logic.image_rendering import ensure_thumbnail, thumbnail_path_for  # noqa: E402


def fetch_topic_images(supabase, user_id):
    out, start = [], 0
    while True:
        q = (supabase.table("lecture_topics").select("lecture_id,index,image_path,user_id")
             .not_.is_("image_path", "null"))
        if user_id:
            q = q.eq("user_id", user_id)
        rows = q.order("id").range(start, start + 999).execute().data
        out += rows
        if len(rows) < 1000:
            return out
        start += 1000


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="実際に書き込む(無ければドライラン)")
    ap.add_argument("--user-id", help="このユーザーだけ対象にする")
    ap.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()

    supabase = get_supabase_client()
    topics = fetch_topic_images(supabase, args.user_id)
    by_lecture = collections.defaultdict(list)
    for t in topics:
        by_lecture[t["lecture_id"]].append(t)

    # 1) 縮小版
    missing = [t["image_path"] for t in topics
               if not storage_service.object_exists(thumbnail_path_for(t["image_path"]))]
    print(f"topic images: {len(topics)} in {len(by_lecture)} lecture(s); thumbnails missing: {len(missing)}")

    created, failed = 0, []
    if args.apply and missing:
        started = time.perf_counter()
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            for path, thumb in zip(missing, pool.map(ensure_thumbnail, missing)):
                if thumb:
                    created += 1
                else:
                    failed.append(path)
        print(f"thumbnails created: {created}, failed: {len(failed)} "
              f"({time.perf_counter() - started:.1f}s)")
        for p in failed[:20]:
            print("  failed:", p)

    # 2) 講義の表紙サムネイル(番号が一番小さいトピックの画像)
    lecture_ids = list(by_lecture)
    lectures = {}
    for i in range(0, len(lecture_ids), 100):
        chunk = lecture_ids[i:i + 100]
        for row in supabase.table("lectures").select("id,metadata").in_("id", chunk).execute().data:
            lectures[row["id"]] = row
    to_set = []
    for lid, items in by_lecture.items():
        row = lectures.get(lid)
        if row is None:
            continue  # 講義が物理削除済み
        metadata = row.get("metadata") or {}
        if metadata.get("cover_thumb_path"):
            continue
        first = min(items, key=lambda t: t["index"])
        to_set.append((lid, metadata, thumbnail_path_for(first["image_path"])))
    print(f"lectures needing cover_thumb_path: {len(to_set)}")

    if args.apply:
        updated = skipped = 0
        for lid, metadata, thumb in to_set:
            if not storage_service.object_exists(thumb):
                skipped += 1  # 縮小版が作れなかった講義はタイルが元の方式のまま
                continue
            supabase.table("lectures").update({"metadata": {**metadata, "cover_thumb_path": thumb}})\
                .eq("id", lid).execute()
            updated += 1
        print(f"cover_thumb_path set: {updated}, skipped (no thumbnail): {skipped}")
    else:
        print("dry-run: nothing written. Re-run with --apply to write.")


if __name__ == "__main__":
    main()
