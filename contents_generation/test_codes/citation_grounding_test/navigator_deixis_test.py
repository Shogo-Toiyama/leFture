"""
探索役の指示語(「これ」「こんなこと」)の対象決め: 選択 → 前の会話 → 画面、の優先順位を
2026-10-03に追加したプロンプトが正しく効くかの確認。

対象は本番で実際に起きた誤り(フロントエンド/バックエンドの話と勘違いして検索した)。
選択テキストを履歴に残す修正(chat_service.build_history_messages)の効果も込みで確認する
(新しいプロンプトだけでなく、入力自体も直っているかを見る)。1周目の判断(decide_lap)だけを
見るので、実際の検索(RPC)は実行しない=安価。

実行: python navigator_deixis_test.py
"""
import asyncio
import sys
from datetime import date
from pathlib import Path

TEST_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TEST_DIR))

import build_cases as bc  # noqa: E402
from app.core.supabase import get_supabase_client  # noqa: E402
from app.services import chat_service as cs  # noqa: E402
from app.services.chat_map import load_student_map, resolve_timezone  # noqa: E402
from app.services.chat_navigator import NavigatorInput, NavState, decide_lap  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, UnifiedLLM  # noqa: E402

TARGET_QUESTION = "こんなこと先生説明してたっけ"


async def main():
    admin = get_supabase_client()
    tid = admin.table("chat_messages").select("thread_id").eq("user_id", bc.OWN_USER_ID) \
        .ilike("content", f"{TARGET_QUESTION}%").limit(1).execute().data[0]["thread_id"]
    rows = admin.table("chat_messages").select("*").eq("thread_id", tid).eq("user_id", bc.OWN_USER_ID) \
        .order("created_at").execute().data
    target_idx = next(i for i, r in enumerate(rows) if r["role"] == "user" and r["content"].startswith(TARGET_QUESTION))
    target = rows[target_idx]
    history_rows = rows[:target_idx]  # これが修正の効果(selected_textの織り込み)を受ける側

    smap = load_student_map(admin, bc.OWN_USER_ID, resolve_timezone(None))
    blocked = cs._load_blocked_source_types(bc.OWN_USER_ID)
    history = cs.build_history_messages(history_rows, cs.RAW_MAX_TURNS, cs.HISTORY_MAX_CHARS_PER_MESSAGE)
    print("--- recent_conversation(探索役に見せる形) ---")
    print(cs.format_router_conversation(history))
    print()

    nav_input = NavigatorInput(
        message=target["content"], selected_text=(target.get("context") or {}).get("selected_text"),
        screen_lecture_id=(target.get("context") or {}).get("lecture_id"), recent_conversation=history,
        today=date.today(), student_map=smap, blocked_source_types=blocked,
    )
    llm = UnifiedLLM(BillingEngine(task_type="navigator_deixis_test"))
    for i in range(3):
        out, err = await decide_lap(llm, nav_input, NavState(), lap=1)
        if err:
            print(f"[{i}] ERROR: {err}")
            continue
        print(f"[{i}] reasoning: {out.get('reasoning')}")
        print(f"    missing:   {out.get('missing')}")
        print(f"    operations:{out.get('operations')}")
    print(f"\ncost ${llm.billing.total_usd():.4f}")


if __name__ == "__main__":
    asyncio.run(main())
