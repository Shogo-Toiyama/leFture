#!/usr/bin/env python3
"""
既存の講義のマスター音声を、途中から再生できる「索引が先頭のAAC/MP4」に揃える
バックフィル(app/services/logic/audio_normalization.py と同じ処理)。

新しくアップロードされる音声は、/worker/complete-master-audio-upload が
/worker/normalize-master-audio をタスクとして積むので、これは既存分のため。
一度きりのローカル実行専用。AIは使わない(R2の読み書きとffmpegだけ)。

使い方 (lefture_backend/ から実行。ffmpeg/ffprobeが必要):
    python scripts/backfill_normalize_master_audio.py
        ドライラン(既定)。何も書き込まず、形式ごとの件数と変換予定を表示する。

    python scripts/backfill_normalize_master_audio.py --apply --user-id <uid>
        1ユーザーだけ実際に揃える。全体の前の確認用。

    python scripts/backfill_normalize_master_audio.py --apply [--limit N]
        全ユーザー分(または先頭N件)を揃える。

途中で止めても安全: 既に揃っている音声は先頭の数バイトを読むだけで飛ばすので、
再実行すると残りだけが処理される。検証(AAC・長さ一致・索引が先頭)に通らない
変換結果は上書きしない。
"""
import argparse
import collections
import json
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from dotenv import load_dotenv  # noqa: E402

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

from app.core.supabase import get_supabase_client  # noqa: E402
from app.services.logic.audio_normalization import normalize_master_audio  # noqa: E402


def fetch_audio_paths(supabase, user_id):
    out, start = [], 0
    while True:
        q = supabase.table("lectures").select("id,audio_path").not_.is_("audio_path", "null")
        if user_id:
            q = q.eq("user_id", user_id)
        rows = q.order("id").range(start, start + 999).execute().data
        out += rows
        if len(rows) < 1000:
            return out
        start += 1000


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="実際に揃える(無ければドライラン)")
    ap.add_argument("--user-id", help="このユーザーだけ対象にする")
    ap.add_argument("--limit", type=int, help="先頭N件だけ処理する")
    args = ap.parse_args()

    rows = fetch_audio_paths(get_supabase_client(), args.user_id)
    if args.limit:
        rows = rows[: args.limit]
    print(f"lectures with audio_path: {len(rows)} ({'apply' if args.apply else 'dry-run'})")

    actions = collections.Counter()
    layouts = collections.Counter()
    problems = []
    started = time.perf_counter()
    for i, row in enumerate(rows, 1):
        r = normalize_master_audio(row["audio_path"], dry_run=not args.apply)
        actions[r["action"]] += 1
        layouts[r["layout"]] += 1
        if r["action"] in ("remux", "transcode", "failed", "changed", "unsupported"):
            print(f"[{i}/{len(rows)}] {r['action']:<10} {r['layout']:<12} {row['id']} "
                  f"{json.dumps({k: r[k] for k in ('duration_before', 'duration_after', 'bytes', 'bytes_after', 'checks', 'error') if k in r}, ensure_ascii=False)}")
        if r["action"] in ("failed", "changed", "unsupported"):
            problems.append({"lecture_id": row["id"], **r})

    print(f"\nlayouts: {dict(layouts)}")
    print(f"actions: {dict(actions)}  ({time.perf_counter() - started:.1f}s)")
    if problems:
        print(f"needs attention: {len(problems)}")
    if not args.apply:
        print("dry-run: nothing written. Re-run with --apply to write.")


if __name__ == "__main__":
    main()
