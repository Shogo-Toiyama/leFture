import asyncio
import os
import sys
import json
import time
from pathlib import Path
from dotenv import load_dotenv

REPO_ROOT = Path(__file__).resolve().parents[3]
load_dotenv(REPO_ROOT / 'lefture_backend' / '.env')
sys.path.insert(0, str(REPO_ROOT / 'lefture_backend'))

from app.services.helpers.llm_unified import BillingEngine, UnifiedLLM, Message, LLMOptions
from app.services.chat_screen import ScreenPage
from app.services.chat_summary import rows_after_fold_point
from app.services.chat_attachments import Attachment, assign_handles, plan_visibility, render_for_router
from app.services.chat_service import (
    ROUTER_MODEL,
    ROUTER_SCHEMA,
    build_history_messages,
    format_router_conversation,
    format_screen_context,
    _render_conditional_sections,
    fill_placeholders,
    _load_prompt,
    ConversationMemory,
)
from supabase import create_client

client = create_client(os.environ['SUPABASE_URL'], os.environ['SUPABASE_SECRET_KEY'])
thread_id = 'b70b7b26-21d3-4e56-944b-459411578cd1'


async def main():
    print("🚀 Fetching messages, attachments, and summary blocks from Supabase...")
    all_msgs = client.table('chat_messages').select('*').eq('thread_id', thread_id).order('created_at').execute().data
    print(f"Total messages in thread: {len(all_msgs)}")

    all_blocks = client.table('chat_summary_blocks').select('*').eq('thread_id', thread_id).is_('invalidated_at', 'null').order('block_index').execute().data
    print(f"Total active summary blocks: {len(all_blocks)}")

    # Attachments in this thread (Midterm Exam)
    att_rows = client.table('chat_attachments').select('*').eq('thread_id', thread_id).order('created_at').execute().data
    attachments = []
    for r in att_rows:
        attachments.append(Attachment(
            id=r['id'],
            title=r.get('title') or 'Attachment',
            content=r.get('content') or '',
            summary=r.get('summary') or '',
            sections=[],
            created_at=r.get('created_at') or '',
        ))
    attachments = assign_handles(attachments)
    vis = plan_visibility(attachments, set(), set())
    attachments_text = render_for_router(attachments, vis)

    # Turn 3 (Msg 4 user, Msg 5 assistant) is the 7-topic roadmap source
    turn_3_text = f"[Turn 3] Student: {all_msgs[4]['content']}\n\n[Turn 3] Assistant: {all_msgs[5]['content']}"

    # Course list
    courses_text = "- Computer Networks (CS 118, Fall 2026)"

    # Pre-fetch lecture info for screen context resolution
    lecture_cache = {}
    deep_note_cache = {}

    def get_lecture_title(lec_id):
        if not lec_id:
            return None
        if lec_id not in lecture_cache:
            r = client.table('lectures').select('title, title_generated').eq('id', lec_id).single().execute().data
            lecture_cache[lec_id] = r.get('title') or r.get('title_generated') or 'Computer Networks Lecture'
        return lecture_cache[lec_id]

    def get_deep_note_page(note_id, lec_id):
        if not note_id:
            return None
        if note_id not in deep_note_cache:
            r = client.table('deep_notes').select('topic_number, note_contents').eq('id', note_id).single().execute().data
            content = r.get('note_contents') or ''
            first_line = content.split('\n')[0].replace('#', '').strip() if isinstance(content, str) else 'Deep Note'
            deep_note_cache[note_id] = ScreenPage(
                kind="deep_note",
                lecture_id=lec_id,
                topic_number=r.get('topic_number'),
                title=f'Deep Note "{first_line}"',
                text=content[:500] if isinstance(content, str) else '',
                selection_marked=False,
                truncated=True,
            )
        return deep_note_cache[note_id]

    # Define the 5 real production test cases:
    test_case_configs = [
        {
            "turn_num": 9,
            "msg_idx": 16,
            "name": "Case 1: Turn 9 - 冒頭と末尾に「次」が出現する複合意図レビュー",
            "active_blocks": [],  # At turn 9, summary block 1 was not yet folded
        },
        {
            "turn_num": 11,
            "msg_idx": 20,
            "name": "Case 2: Turn 11 - ロードマップ進行指示（次、単語の確認の続きがしたい）",
            "active_blocks": all_blocks[:1],  # Block 1 active
        },
        {
            "turn_num": 23,
            "msg_idx": 44,
            "name": "Case 3: Turn 23 - 画面表示＋代名詞指示（じゃあ次、この講義にすすみたい）",
            "active_blocks": all_blocks[:2],  # Block 1 & 2 active
        },
        {
            "turn_num": 26,
            "msg_idx": 50,
            "name": "Case 4: Turn 26 - 直接閲覧指示（Topic 5-6のDeepNotesを直接見てまとめて）",
            "active_blocks": all_blocks[:2],
        },
        {
            "turn_num": 27,
            "msg_idx": 52,
            "name": "Case 5: Turn 27 - 通常の技術的疑問（スライディングウィンドウの無限増加とリセット）",
            "active_blocks": all_blocks[:2],
        },
    ]

    billing = BillingEngine()
    llm = UnifiedLLM(billing)

    # Load prompts
    router_sys_prompt_new = _load_prompt("chat_router_prompt.txt")
    router_input_tmpl = _load_prompt("chat_router_input_prompt.txt")

    # Baseline prompt (before referenced_sources additions)
    router_sys_prompt_old = router_sys_prompt_new.replace(
        "(earlier turns, referenced sources, shared materials, screen context, and recent replies)",
        "(earlier turns, shared materials, screen context, and recent replies)"
    ).replace(
        "Explicitly identify the specific concept, problem, code, or item they are pointing to (referencing <referenced_sources> when advancing through an active roadmap, criteria, or outline).",
        "Explicitly identify the specific concept, problem, code, or item they are pointing to."
    ).replace(
        "<referenced_sources>: verbatim text of key earlier turns preserved as an anchor (e.g. an overarching study roadmap, rubric, or assignment outline), or omitted if none. ",
        ""
    )

    results = []

    for cfg in test_case_configs:
        idx = cfg["msg_idx"]
        m = all_msgs[idx]
        user_msg = m['content']
        ctx = m.get('context') or {}

        print(f"\n======================================================================")
        print(f"[{cfg['name']}] (Turn {cfg['turn_num']}, Msg {idx})")
        print(f"User Message: {user_msg[:120]}..." if len(user_msg) > 120 else f"User Message: {user_msg}")
        print(f"======================================================================")

        # Build exact history up to this turn (using production rows_after_fold_point)
        fold_id = cfg["active_blocks"][-1]["end_message_id"] if cfg["active_blocks"] else None
        history_rows = rows_after_fold_point(all_msgs[:idx], fold_id)
        history = build_history_messages(history_rows, max_turns=20, max_chars=None)
        recent_conv = format_router_conversation(history)

        # Build memory from active summary blocks
        memory = ConversationMemory.from_blocks(cfg["active_blocks"])
        earlier_conv = memory.for_router()

        # Build screen context exactly as chat_service does
        lec_id = ctx.get('lecture_id')
        lec_label = get_lecture_title(lec_id)
        screen_obj = ctx.get('screen') or {}
        screen_page = get_deep_note_page(screen_obj.get('id'), lec_id) if screen_obj.get('kind') == 'deep_note' else None
        selected_text = ctx.get('selected_text')

        screen_text = format_screen_context(
            lec_label, selected_text, screen_page, full_page=False
        ) or "(none)"

        options = LLMOptions(output_type="json", json_schema=ROUTER_SCHEMA, temperature=0.0)

        # -------------------------------------------------------------
        # Pattern A: 以前のRouter (No referenced_sources & Old Prompt)
        # -------------------------------------------------------------
        tmpl_a = _render_conditional_sections(router_input_tmpl, {"HAS_REFERENCED_SOURCES": False})
        user_in_a = fill_placeholders(tmpl_a, {
            "EARLIER_CONVERSATION": earlier_conv,
            "REFERENCED_SOURCES": "",
            "RECENT_CONVERSATION": recent_conv,
            "SCREEN_CONTEXT": screen_text,
            "COURSES": courses_text,
            "ATTACHMENTS": attachments_text,
            "IS_FIRST_MESSAGE": "false",
            "NEW_MESSAGE": user_msg,
        })
        msgs_a = [
            Message(role="system", content=router_sys_prompt_old),
            Message(role="user", content=user_in_a),
        ]

        # -------------------------------------------------------------
        # Pattern B: 今回のRouter (With referenced_sources & New Prompt)
        # -------------------------------------------------------------
        tmpl_b = _render_conditional_sections(router_input_tmpl, {"HAS_REFERENCED_SOURCES": True})
        user_in_b = fill_placeholders(tmpl_b, {
            "EARLIER_CONVERSATION": earlier_conv,
            "REFERENCED_SOURCES": turn_3_text,
            "RECENT_CONVERSATION": recent_conv,
            "SCREEN_CONTEXT": screen_text,
            "COURSES": courses_text,
            "ATTACHMENTS": attachments_text,
            "IS_FIRST_MESSAGE": "false",
            "NEW_MESSAGE": user_msg,
        })
        msgs_b = [
            Message(role="system", content=router_sys_prompt_new),
            Message(role="user", content=user_in_b),
        ]

        if "--dry-run" in sys.argv:
            print(f"  [Dry Run] Pattern A input prompt: {len(user_in_a):,} chars")
            print(f"  [Dry Run] Pattern B input prompt: {len(user_in_b):,} chars")
            assert "<referenced_sources>" not in user_in_a
            assert "<referenced_sources>" in user_in_b
            print("  [Dry Run] Sanity check passed for this case.")
            continue

        RUNS_PER_CASE = 2
        runs_a = []
        runs_b = []

        for r_i in range(RUNS_PER_CASE):
            t0 = time.time()
            res_a = await llm.generate(ROUTER_MODEL, msgs_a, options)
            lat_a = time.time() - t0
            runs_a.append({
                "run": r_i + 1,
                "latency_sec": lat_a,
                "tokens": {"in": res_a.input_tokens, "out": res_a.output_tokens},
                "output": res_a.output_json or {},
            })

            t0 = time.time()
            res_b = await llm.generate(ROUTER_MODEL, msgs_b, options)
            lat_b = time.time() - t0
            runs_b.append({
                "run": r_i + 1,
                "latency_sec": lat_b,
                "tokens": {"in": res_b.input_tokens, "out": res_b.output_tokens},
                "output": res_b.output_json or {},
            })

        avg_lat_a = sum(r["latency_sec"] for r in runs_a) / len(runs_a)
        avg_lat_b = sum(r["latency_sec"] for r in runs_b) / len(runs_b)

        print(f"\n--- [Pattern A: 変更前 (Without referenced_sources)] ---")
        for r in runs_a:
            out = r["output"]
            print(f"  Run {r['run']}: Latency: {r['latency_sec']:.2f}s | In: {r['tokens']['in']} tokens | Out: {r['tokens']['out']} tokens")
            print(f"    user_goal: {out.get('user_goal')}")
            print(f"    needs_retrieval: {out.get('needs_retrieval')} | reason: {out.get('retrieval_reason')}")
            print(f"    needs_reasoning: {out.get('needs_reasoning')}")

        print(f"\n--- [Pattern B: 変更後 (With referenced_sources)] ---")
        for r in runs_b:
            out = r["output"]
            print(f"  Run {r['run']}: Latency: {r['latency_sec']:.2f}s | In: {r['tokens']['in']} tokens | Out: {r['tokens']['out']} tokens")
            print(f"    user_goal: {out.get('user_goal')}")
            print(f"    needs_retrieval: {out.get('needs_retrieval')} | reason: {out.get('retrieval_reason')}")
            print(f"    needs_reasoning: {out.get('needs_reasoning')}")

        results.append({
            "case_name": cfg["name"],
            "turn_num": cfg["turn_num"],
            "user_message": user_msg,
            "pattern_a": {
                "runs": runs_a,
                "avg_latency_sec": avg_lat_a,
                "in_tokens": runs_a[0]["tokens"]["in"],
                "out_tokens": runs_a[0]["tokens"]["out"],
                "user_goal": runs_a[0]["output"].get("user_goal"),
                "needs_retrieval": runs_a[0]["output"].get("needs_retrieval"),
                "retrieval_reason": runs_a[0]["output"].get("retrieval_reason"),
                "needs_reasoning": runs_a[0]["output"].get("needs_reasoning"),
            },
            "pattern_b": {
                "runs": runs_b,
                "avg_latency_sec": avg_lat_b,
                "in_tokens": runs_b[0]["tokens"]["in"],
                "out_tokens": runs_b[0]["tokens"]["out"],
                "user_goal": runs_b[0]["output"].get("user_goal"),
                "needs_retrieval": runs_b[0]["output"].get("needs_retrieval"),
                "retrieval_reason": runs_b[0]["output"].get("retrieval_reason"),
                "needs_reasoning": runs_b[0]["output"].get("needs_reasoning"),
            }
        })

    out_file = "contents_generation/test_codes/router_comparison_results.json"
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

    total_usd = billing.total_usd()
    print(f"\n✅ All 5 test cases completed! Total test cost: ${total_usd:.6f}")
    print(f"Results saved to {out_file}")


if __name__ == '__main__':
    asyncio.run(main())
