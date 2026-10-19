#!/usr/bin/env python3
"""
過学習の確認用: 調整に使った E/F/G(ba9a18c9のスレッド)とは別のスレッドから、
「確認の質問」のターンを本番どおりの文脈で固定する。

3種類を混ぜている:
  A  理解はほぼ合っている確認の質問 → 全面的に認めて、補足はおまけにしてほしい
  B  本当にずれている確認の質問     → 訂正はちゃんと残してほしい(認めすぎないか)
  C  具体的な手順・計算の確認       → 今までどおり、どの手順が違うかを正確に言ってほしい

使い方: python extract_holdout.py  → cases/holdout_cases.json
"""

import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from supabase import create_client

from app.services.chat_screen import ScreenRef, load_screen_page
from app.services.chat_service import _load_student_profile
from app.services.profile_store import load_chat_memory

supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])

# (case_id, 種類, 名前, ユーザーの発言のid, そのときの回答のid)。idはholdout_candidates.jsonの選定から。
SELECTED: list[tuple[str, str, str, str, str]] = []
SELECTION_FILE = Path(__file__).parent / "selection.json"


def main() -> None:
    selection = json.loads(SELECTION_FILE.read_text(encoding="utf-8"))
    out_cases = []
    for item in selection:
        u_msg = supabase.table("chat_messages").select("*").eq("id", item["user_message_id"]).single().execute().data
        a_msg = supabase.table("chat_messages").select("*").eq("id", item["assistant_message_id"]).single().execute().data
        thread_id, user_id, created_at = u_msg["thread_id"], u_msg["user_id"], u_msg["created_at"]

        history_rows = [
            {"role": m["role"], "content": m["content"]}
            for m in (
                supabase.table("chat_messages")
                .select("role, content, created_at, status")
                .eq("thread_id", thread_id)
                .lt("created_at", created_at)
                .order("created_at")
                .execute()
                .data
                or []
            )
            if m.get("content") and m.get("status") != "cancelled"
        ]

        ctx = u_msg.get("context") or {}
        screen_dict = ctx.get("screen") or {}
        lecture_id = ctx.get("lecture_id")

        lecture_label = None
        if lecture_id:
            lec = supabase.table("lectures").select("title").eq("id", lecture_id).maybe_single().execute()
            if lec and lec.data:
                lecture_label = lec.data.get("title")

        screen_page = None
        if screen_dict.get("kind"):
            page = load_screen_page(
                admin_client=supabase,
                user_id=user_id,
                ref=ScreenRef(kind=screen_dict["kind"], id=screen_dict.get("id")),
                lecture_id=lecture_id,
                selection=None,
                blocked_source_types=frozenset(),
            )
            if page:
                screen_page = {
                    "kind": page.kind,
                    "lecture_id": page.lecture_id,
                    "topic_number": page.topic_number,
                    "title": page.title,
                    "text": page.text,
                    "selection_marked": page.selection_marked,
                    "truncated": page.truncated,
                }

        student_memos, open_questions = load_chat_memory(supabase, user_id)
        out_cases.append(
            {
                "case_id": item["case_id"],
                "kind": item["kind"],
                "name": item["name"],
                "note": item.get("note", ""),
                "user_id": user_id,
                "thread_id": thread_id,
                "question": u_msg["content"],
                "actual_previous_answer": a_msg["content"],
                "history_rows": history_rows,
                "lecture_label": lecture_label,
                "screen_page": screen_page,
                "profile": _load_student_profile(supabase, user_id),
                "student_memos": student_memos,
                "open_questions": open_questions,
                # 本番の振り分けの結果をそのまま使う(needs_reasoningなら推論mediumで答える)
                "router": a_msg.get("router") or {"reply_language": "ja", "needs_reasoning": False},
            }
        )

    out_dir = Path(__file__).parent / "cases"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / "holdout_cases.json"
    out_file.write_text(json.dumps(out_cases, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Extracted {len(out_cases)} cases to {out_file}")
    for c in out_cases:
        print(f"  {c['case_id']} [{c['kind']}] needs_reasoning={c['router'].get('needs_reasoning')} history={len(c['history_rows'])} page={'yes' if c['screen_page'] else 'no'}  {c['name']}")


if __name__ == "__main__":
    main()
