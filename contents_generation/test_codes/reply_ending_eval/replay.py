"""
回答の締め(次の話題の提案・クイズ・誘導質問)を減らすプロンプト修正の評価。

Baseline = Supabase にある本番の回答そのもの(旧プロンプトは再生成しない)。
新プロンプト(prompts/ のコピー)だけで、同じターンの回答役を再生する。

再生の仕方: 本番で材料(検索結果)が空だったターンだけを選び、本番の振り分け役の判断(chat_messages.router)と
探索役の最後の考え(usage.navigator)をそのまま使って、回答役だけを本番の関数(chat_service._build_answer_messages)
で呼ぶ。履歴・要約・添付資料(全文か要約かは本番の usage.attachments.full に合わせる)・画面のページ・返信の抜粋も
本番と同じ関数で組み直す。

本番と違うところ:
- プロフィール・覚え書き(memos)は今の値(その時点の値は残っていない)
- 画面の選択の前後の文脈(selection_before/after)は保存されていないので空
- プロンプトキャッシュは使わない(費用のため)。時刻は元のメッセージの時刻に固定

  .venv/bin/python contents_generation/test_codes/reply_ending_eval/replay.py --dry-run
  .venv/bin/python contents_generation/test_codes/reply_ending_eval/replay.py
"""

import argparse
import asyncio
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from supabase import create_client  # noqa: E402

from app.services import chat_service as cs  # noqa: E402
from app.services.chat_attachments import (Attachment, assign_handles, estimate_tokens, mention_ids,  # noqa: E402
                                           plan_visibility, render_mentions)
from app.services.chat_reasoning import REASONING_CONFIG  # noqa: E402
from app.services.chat_screen import ScreenRef, ScreenSelection, build_reply_quote, load_screen_page  # noqa: E402
from app.services.chat_summary import _BLOCK_COLUMNS, extract_source_turns_to_fetch, rows_after_fold_point  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, StreamState, UnifiedLLM  # noqa: E402
from app.services.profile_store import load_chat_memory  # noqa: E402

TZ_NAME = "America/Los_Angeles"

# expect: drop = 締めの提案・クイズは要らない / keep = 締めに聞き返し・次の一歩があるべき
CASES = [
    {"id": "A00_fumen_data", "msg": "7076dba8", "expect": "drop"},     # 「これなんだっけ？」→ 次の話題の提案
    {"id": "A13_type_ops", "msg": "bda022d1", "expect": "drop"},       # 概念の確認 → ジェネリクスの提案(直前と同じ)
    {"id": "A22_in_japanese", "msg": "db2de4d2", "expect": "drop"},    # 「日本語で説明して」→ 前のクイズを再度
    {"id": "A48_type_inference", "msg": "55c7f82e", "expect": "drop"}, # ユーザーの実例(count := 3 を3回目)
    {"id": "A32_agenda_start", "msg": "054e06c3", "expect": "keep"},   # ユーザーが進め方を決めた → 1問目を求める
    {"id": "A36_need_info", "msg": "b375d0a1", "expect": "keep"},      # 問題文が見えない → 確認が要る
]

VARIANT_PROMPTS = {"chat_answer_prompt.txt", "chat_answer_turn_prompt.txt"}
_orig_load_prompt = cs._load_prompt


def use_variant(on: bool):
    cs._load_prompt = (lambda f: (HERE / "prompts" / f).read_text(encoding="utf-8")
                       if f in VARIANT_PROMPTS else _orig_load_prompt(f)) if on else _orig_load_prompt


class FrozenDatetime(datetime):
    frozen: datetime = None

    @classmethod
    def now(cls, tz=None):
        return cls.frozen.astimezone(tz) if tz else cls.frozen


def find_message(c, prefix: str) -> dict:
    rows = c.table("chat_messages").select("id, thread_id, role, content, status, created_at, router, usage") \
        .eq("role", "assistant").gte("created_at", "2026-11-04T15:00:00+00:00").execute().data
    return next(r for r in rows if r["id"].startswith(prefix))


async def build_case(c, case: dict) -> dict:
    a_row = find_message(c, case["msg"])
    thread_id = a_row["thread_id"]
    user_id = c.table("chat_threads").select("user_id").eq("id", thread_id).execute().data[0]["user_id"]
    before = c.table("chat_messages").select("id, role, content, status, created_at, context, deleted_at") \
        .eq("thread_id", thread_id).lt("created_at", a_row["created_at"]).order("created_at").execute().data
    u_row = [r for r in before if r["role"] == "user"][-1]
    t_at = u_row["created_at"]
    ctx = u_row.get("context") or {}

    # 要約(そのときにあったブロックだけ)と、畳んでいない履歴
    # 要約は回答の後に非同期で作られるので、そのターンの時点で作られていて、まだ無効になっていなかったものだけ
    def blocks(level):
        meta = {r["id"]: r for r in c.table("chat_summary_blocks").select("id, created_at, invalidated_at")
                .eq("thread_id", thread_id).eq("level", level).execute().data}
        rows = c.table("chat_summary_blocks").select(_BLOCK_COLUMNS).eq("thread_id", thread_id).eq("level", level) \
            .order("block_index").execute().data
        return [b for b in rows if meta[b["id"]]["created_at"] < t_at
                and (not meta[b["id"]]["invalidated_at"] or meta[b["id"]]["invalidated_at"] > t_at)]
    l1, l2 = blocks(1), blocks(2)
    hist = [r for r in before if r["created_at"] < t_at and not r.get("deleted_at")][-cs.RAW_FETCH_MESSAGES:]
    history_rows = rows_after_fold_point(hist, l1[-1]["end_message_id"] if l1 else None)

    # 添付資料: そのときスレッドにあった ready の資料。全文か要約かは本番の記録に合わせる
    att_rows = c.table("chat_attachments").select(cs.ATTACHMENT_COLUMNS + ", deleted_at") \
        .eq("thread_id", thread_id).eq("status", "ready").lt("created_at", t_at).order("created_at").execute().data
    att_rows = [r for r in att_rows if not r.get("deleted_at") or r["deleted_at"] > t_at]
    attachments = assign_handles([Attachment.from_row(r) for r in att_rows])
    prod_att = (a_row.get("usage") or {}).get("attachments") or {}
    full_handles = set(prod_att.get("full") or [])
    for a in attachments:
        a.selected = a.handle in full_handles
    mentions = mention_ids(u_row["content"])
    visibility = plan_visibility(attachments, mentions, set())
    history_rows = [{**r, "content": render_mentions(r.get("content") or "", attachments)}
                    if r.get("role") == "user" else r for r in history_rows]

    lecture_id = ctx.get("lecture_id")
    lecture_label = cs._lecture_label(c, lecture_id, user_id) if lecture_id else None
    course_id = ctx.get("course_id") if not lecture_id else None
    course_label = cs._course_label(c, course_id, user_id) if course_id else None
    blocked = cs._load_blocked_source_types(user_id)
    selected_text = ctx.get("selected_text")
    reply_to = ctx.get("reply_to_message_id")
    screen_page = None
    if ctx.get("screen"):
        sel = ScreenSelection(text=selected_text, before="", after="") if selected_text and not reply_to else None
        screen_page = load_screen_page(c, user_id, ScreenRef(**ctx["screen"]), lecture_id, sel, blocked)
    reply_quote = None
    if reply_to and selected_text:
        rr = c.table("chat_messages").select("content").eq("id", reply_to).execute().data
        if rr:
            reply_quote = build_reply_quote(rr[0]["content"] or "", ScreenSelection(text=selected_text, before="", after=""))

    turn = cs.PreparedTurn(
        user_id=user_id, thread_id=thread_id, is_new_thread=not history_rows and not l1, thread_has_title=True,
        user_message_id=u_row["id"], assistant_message_id="replay", content=u_row["content"], selected_text=selected_text,
        lecture_label=lecture_label, context_lecture_id=lecture_id, timezone_name=TZ_NAME,
        context_course_id=course_id, course_label=course_label,
        history_rows=history_rows, summary_blocks=l1, summary_level2=l2,
        attachments=attachments, mentions=mentions,
    )
    turn.screen_page = screen_page
    turn.reply_quote = reply_quote

    history = cs.build_history_messages(turn.history_rows, cs.RAW_MAX_TURNS, None,
                                        cs._attachment_titles_by_message(attachments))
    memory = cs.ConversationMemory.from_blocks(l1, l2)
    header = l1[-1].get("header") if l1 else None
    need = extract_source_turns_to_fetch(header)
    referenced = await cs._fetch_referenced_source_turns(c, thread_id, need) if need else ""

    router = a_row.get("router") or {}
    decision = cs.RouterDecision(
        intent=router.get("intent") or "learning", needs_retrieval=bool(router.get("needs_retrieval")),
        reply_language=router.get("reply_language") or "Japanese", thread_title=router.get("thread_title"),
        user_goal=router.get("user_goal"), retrieval_reason=router.get("retrieval_reason"),
        needs_reasoning=bool(router.get("needs_reasoning")),
    )
    nav = (a_row.get("usage") or {}).get("navigator") or {}
    laps = nav.get("laps") or []
    retrieval_reasoning = (laps[-1].get("reasoning") or "") if laps else ""
    profile = cs._load_student_profile(c, user_id)
    memos, open_q = load_chat_memory(c, user_id)
    effort = REASONING_CONFIG.single_effort if decision.needs_reasoning and REASONING_CONFIG.mode == "single" \
        else cs.ANSWER_REASONING_EFFORT

    def messages_for(variant: bool):
        use_variant(variant)
        # <current_time> はプロンプトを組むときに入るので、ここで元のメッセージの時刻に固定する
        FrozenDatetime.frozen = datetime.fromisoformat(t_at.replace("Z", "+00:00"))
        cs.datetime = FrozenDatetime
        try:
            msgs = cs._build_answer_messages(turn, decision, memory, history, profile, [],
                                             student_memos=memos, open_questions=open_q,
                                             attachment_visibility=visibility, referenced_sources=referenced,
                                             retrieval_reasoning=retrieval_reasoning)
        finally:
            use_variant(False)
            cs.datetime = datetime
        return cs.fit_answer_input(msgs)[0]

    return {
        "case": case, "a_row": a_row, "u_row": u_row, "turn": turn, "decision": decision, "effort": effort,
        "when": datetime.fromisoformat(t_at.replace("Z", "+00:00")),
        "messages_variant": messages_for(True), "messages_prod_prompt": messages_for(False),
        "info": {
            "history_msgs": len(history), "summary_l1": len(l1), "attachments": [(a.handle, a.title, a.selected) for a in attachments],
            "prod_attachments": prod_att, "screen": screen_page.title if screen_page else None, "reply_quote": bool(reply_quote),
            "needs_reasoning": decision.needs_reasoning, "effort": effort, "retrieval_reasoning": bool(retrieval_reasoning),
            "prod_input_tokens": (a_row.get("usage") or {}).get("answer_input_tokens"),
            "prod_cache_read": (a_row.get("usage") or {}).get("answer_cache_read_tokens"),
        },
    }


def est(msgs) -> int:
    return sum(estimate_tokens(m.content if isinstance(m.content, str) else json.dumps(m.content, ensure_ascii=False)) for m in msgs)


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--cases", default="", help="comma-separated case ids (default: all)")
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--tag", default="v1")
    args = ap.parse_args()
    wanted = [x for x in args.cases.split(",") if x]
    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    billing = BillingEngine(task_type="reply_ending_eval")
    llm = UnifiedLLM(billing)
    results = []
    for case in [k for k in CASES if not wanted or k["id"] in wanted]:
        b = await build_case(c, case)
        sys_v = b["messages_variant"][0].content
        turn_v = b["messages_variant"][-1].content
        print(f"\n## {case['id']} ({case['expect']})  user: {b['u_row']['content'][:80]!r}")
        print(f"  {json.dumps(b['info'], ensure_ascii=False, default=str)}")
        print(f"  est tokens prod-prompt={est(b['messages_prod_prompt']):,} variant={est(b['messages_variant']):,}"
              f"  (prod recorded input={b['info']['prod_input_tokens']})")
        assert "Ending the reply:" in sys_v and "untangle this together" in str(turn_v), "variant prompt not applied"
        assert "Ending the reply:" not in b["messages_prod_prompt"][0].content
        if args.dry_run:
            continue
        for rep in range(args.repeat):
            results.append(await run_once(llm, billing, b, case, rep))
    if args.dry_run:
        print("\nDRY RUN OK (no API calls)")
        return
    finish(billing, results, args.tag)


async def run_once(llm, billing, b, case, rep):
    FrozenDatetime.frozen = b["when"]
    cs.datetime = FrozenDatetime
    n0 = len(billing.records)
    try:
        state = StreamState()
        opts = cs.answer_options(cs.ANSWER_MODEL, b["effort"], cs._answer_max_tokens(None, []))
        t0 = time.perf_counter()
        first = None
        async for _ in llm.generate_stream(cs.ANSWER_MODEL, b["messages_variant"], state, opts):
            if first is None:
                first = time.perf_counter() - t0
        total = time.perf_counter() - t0
    finally:
        cs.datetime = datetime
    cost = sum(r.cost_usd for r in billing.records[n0:])
    print(f"  effort={b['effort']} TTFT {first or 0:.2f}s total {total:.2f}s in {state.input_tokens:,} out {state.output_tokens:,} ${cost:.4f}")
    print("  NEW END: " + state.output_text.strip()[-300:].replace("\n", " ⏎ "))
    return {
        "case": case["id"], "rep": rep, "expect": case["expect"], "message_id": b["a_row"]["id"], "user_message": b["u_row"]["content"],
        "info": b["info"], "new_answer": state.output_text, "production_answer": b["a_row"]["content"],
        "ttft_s": round(first or 0, 2), "total_s": round(total, 2), "input_tokens": state.input_tokens,
        "output_tokens": state.output_tokens, "cost_usd": round(cost, 6),
    }


def finish(billing, results, tag):
    print(f"\nTOTAL COST ${billing.total_usd():.4f}")
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out = HERE / "results" / f"{ts}_{tag}_replay.json"
    out.write_text(json.dumps({"total_cost_usd": billing.total_usd(), "results": results}, ensure_ascii=False, indent=2, default=str),
                   encoding="utf-8")
    md = ["# Reply ending replay (baseline = production)", ""]
    for r in results:
        md += [f"## {r['case']} #{r['rep']} (expect: {r['expect']})", "", f"**Student:** {r['user_message']}", "",
               "### New prompt", "", r["new_answer"], "", "### Production (baseline)", "", r["production_answer"], "", "---", ""]
    (HERE / "results" / f"{ts}_{tag}_replay_answers.md").write_text("\n".join(md), encoding="utf-8")
    print("saved", out)


if __name__ == "__main__":
    asyncio.run(main())
