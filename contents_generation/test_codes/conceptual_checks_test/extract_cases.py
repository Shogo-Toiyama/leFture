#!/usr/bin/env python3
"""
SupabaseからCase E, F, Gの本番実行時の完全なコンテキストを抽出して固定する。
"""

import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from supabase import create_client

from app.services.chat_screen import ScreenRef, load_screen_page
from app.services.chat_service import _load_student_profile
from app.services.profile_store import load_chat_memory

supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])

CASES_INFO = [
    {
        "case_id": "E",
        "name": "確認の質問(データリンク層)",
        "user_message_id": "abd41f59-9b8b-46ba-bd1a-a6f89be595c1",
        "assistant_message_id": "4374b6d6-2a75-4bed-9858-ac3e443dd5a6",
        "ideal": "そうそう、そのイメージで合ってるよ!送る前に「チェック用の印(チェックサム)」を付けておいて、届いたときに「印と中身が合ってるか」を確かめる。まさにそれ!\n\nちなみに、送る側は「データが正しい」って確かめてるわけじゃなくて、中身から計算した印を付けてるだけなんだ。だから届いたときに印が合わなければ、「途中で壊れたな」ってわかるんだよ。",
    },
    {
        "case_id": "F",
        "name": "確認の質問(4B/5B)",
        "user_message_id": "30caf7a4-2b1f-48e1-9669-34a048559bb2",
        "assistant_message_id": "06ce4092-602e-49e7-a818-fdb63176a523",
        "ideal": "そう、それ!!そこまでつながれば完璧だよ✨ 遷移があるから受信側が時計を合わせ続けられて、読み間違いが減る。その遷移を確保するコストが、マンチェスターは2倍で、4B/5Bは1.25倍で済む、ってことだね!\n\nちなみに、遷移が直接守ってるのは「時計のずれ」で、ノイズによるビット反転までは防げない、ってところまで覚えておくと完璧!",
    },
    {
        "case_id": "G",
        "name": "確認の質問(Hop-by-Hop)",
        "user_message_id": "13fb67af-2710-4b92-b659-b620377b0e75",
        "assistant_message_id": "fd53690f-b07a-407b-8084-61557899ef99",
        "ideal": "途中のルーターが、その区間でエラーを回復してあげる。仕組みはまさにそれ!✨ そのうえで、この話のキモは「何のためにやるか」なので、そこを一緒に見てみよう。\n\n実は、途中で何もしなくても、壊れたデータが読めないまま届いて終わり、にはならないんだ。壊れたフレームはチェックサムで弾かれて捨てられるし、最後は送信元と宛先のTCPが「届いてないよ」と気づいて送り直してくれる。だから、ホップごとの回復がなくても、最終的にはちゃんと届く。\n\nじゃあ何が嬉しいかというと、送り直す距離。…",
    },
]

out_cases = []

for item in CASES_INFO:
    u_msg = (
        supabase.table("chat_messages")
        .select("*")
        .eq("id", item["user_message_id"])
        .single()
        .execute()
        .data
    )
    a_msg = (
        supabase.table("chat_messages")
        .select("*")
        .eq("id", item["assistant_message_id"])
        .single()
        .execute()
        .data
    )

    thread_id = u_msg["thread_id"]
    user_id = u_msg["user_id"]
    created_at = u_msg["created_at"]

    # 当該質問より前のメッセージ履歴を取得
    history_res = (
        supabase.table("chat_messages")
        .select("role, content, created_at, status")
        .eq("thread_id", thread_id)
        .lt("created_at", created_at)
        .order("created_at")
        .execute()
    )
    history_rows = [
        {"role": m["role"], "content": m["content"]}
        for m in (history_res.data or [])
        if m.get("content") and m.get("status") != "cancelled"
    ]

    # コンテキスト（画面、講義）
    ctx = u_msg.get("context") or {}
    screen_dict = ctx.get("screen") or {}
    lecture_id = ctx.get("lecture_id")

    lecture_label = None
    if lecture_id:
        lec_res = (
            supabase.table("lectures")
            .select("title, course_id")
            .eq("id", lecture_id)
            .maybe_single()
            .execute()
        )
        if lec_res and lec_res.data:
            lecture_label = lec_res.data.get("title")

    # 画面ページ本文を本番コードで復元
    screen_page_dict = None
    if screen_dict and screen_dict.get("kind"):
        ref = ScreenRef(kind=screen_dict["kind"], id=screen_dict.get("id"))
        page = load_screen_page(
            admin_client=supabase,
            user_id=user_id,
            ref=ref,
            lecture_id=lecture_id,
            selection=None,
            blocked_source_types=frozenset(),
        )
        if page:
            screen_page_dict = {
                "kind": page.kind,
                "lecture_id": page.lecture_id,
                "topic_number": page.topic_number,
                "title": page.title,
                "text": page.text,
                "selection_marked": page.selection_marked,
                "truncated": page.truncated,
            }

    # ユーザープロファイル
    profile = _load_student_profile(supabase, user_id)

    # メモ・オープンクエスチョン
    student_memos, open_questions = load_chat_memory(supabase, user_id)


    router_info = a_msg.get("router") or {
        "reply_language": "ja",
        "needs_reasoning": True,
    }

    out_cases.append(
        {
            "case_id": item["case_id"],
            "name": item["name"],
            "user_id": user_id,
            "thread_id": thread_id,
            "question": u_msg["content"],
            "actual_previous_answer": a_msg["content"],
            "ideal_answer": item["ideal"],
            "history_rows": history_rows,
            "lecture_label": lecture_label,
            "screen_page": screen_page_dict,
            "profile": profile,
            "student_memos": student_memos,
            "open_questions": open_questions,
            "router": router_info,
        }
    )


out_dir = Path(__file__).parent / "cases"
out_dir.mkdir(parents=True, exist_ok=True)
out_file = out_dir / "cases.json"
with open(out_file, "w", encoding="utf-8") as f:
    json.dump(out_cases, f, indent=2, ensure_ascii=False)

print(f"Successfully extracted {len(out_cases)} cases to {out_file}")
