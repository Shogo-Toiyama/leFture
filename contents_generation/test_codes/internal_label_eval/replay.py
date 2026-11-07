"""
回答役が内部のラベル(A1・C4/L11・T1・W2・資料番号など)を生徒に見せてしまう問題の、プロンプト修正の評価。

背景(2026-11-06): 本番の返信434件のうち、A番号が6件(うち5件は今日、スレッド3f8d3695)、C/L/T番号が2件漏れていた。
今のプロンプトはC/L/Tだけを禁止していて、しかもそのルールが CITATIONS(<sources> があるときだけ)の節の中にある。
修正: 独立した INTERNAL LABELS の節に移し、全種類のラベルを挙げ、「機械的に付けた目印で、生徒には見えない」という目的を書く。

Baseline = Supabase にある本番の回答(旧プロンプトは再生成しない)。新プロンプト(prompts/ のコピー)だけで回答役を再生する。

再生の仕方: reply_ending_eval/replay.py と同じく、本番の関数(chat_service._build_answer_messages)で回答役の入力を組み直す。
違いは、本番で探索役が実行した open / by_date を本番の関数(validate_operations + execute_lap)でもう一度実行して、
参照資料(<sources>)も組み直すこと(検索 find は使わないケースだけを選んだ)。探索役の最後の考えは本番の記録をそのまま使う。

本番と違うところ: プロフィール・覚え書きは今の値。プロンプトキャッシュは使わない。時刻は元のメッセージの時刻に固定。

  .venv/bin/python contents_generation/test_codes/internal_label_eval/replay.py --dry-run
  .venv/bin/python contents_generation/test_codes/internal_label_eval/replay.py
"""

import argparse
import asyncio
import json
import re
import sys
import time
from datetime import date, datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "reply_ending_eval"))
import replay as base  # noqa: E402  (lefture_backend への path と .env の読み込みもここで済む)
from replay import cs, create_client, os  # noqa: E402

from app.services import chat_navigator as nav  # noqa: E402
from app.services.chat_lecture_source import DbLectureSource  # noqa: E402
from app.services.chat_map import load_student_map  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, StreamState, UnifiedLLM  # noqa: E402
from zoneinfo import ZoneInfo  # noqa: E402
from app.services import chat_attachments as base_mentions  # noqa: E402

CASES = [
    # 今回の実例: A1(全文)+ C4/C5の目次、推論high。「A1の範囲は」「範囲マップ（A1の番号順）」
    {"id": "A1_full_scope_map", "msg": "13100d37"},
    # A1が要約だけ・参照資料なし。「A1の概要だけで…A1を全文で添付し直して」
    {"id": "A1_summary_only", "msg": "9a9635cc"},
    # 既存のC/L/T禁止があるのに漏れた。「10月29日の講義（C4/L11「…」）」と表の T1〜T6
    {"id": "C4L11_T_table", "msg": "52eadf89"},
]

# 本文から引用(⟦…⟧)・コードを除いて、ラベルらしいものを探す
LABEL_PATTERNS = {
    "C/L/T": r"(?<![A-Za-z0-9])C\d+(?:/L\d+(?:-\d+)?(?:/T\d+)?)?(?![A-Za-z0-9])|(?<![A-Za-z0-9/])L\d+(?:/T\d+)?(?![A-Za-z0-9])|(?<![A-Za-z0-9])T\d(?![A-Za-z0-9])",
    "A": r"(?<![A-Za-z0-9])A\d{1,2}(?:/S\d+)?(?![A-Za-z0-9])",
    "S/H/P": r"(?<![A-Za-z0-9])(?:S|H|P)\d{1,2}(?:/(?:T|S|H)\d+)?(?![A-Za-z0-9])",
    "W/U": r"(?<![A-Za-z0-9])[WU]\d{1,2}(?![A-Za-z0-9])",
    "source#": r"(?:資料|出典|ソース|source)\s?\[?\d+\]?(?![\d.])|\[\d+\]|‹\d",
    "sid": r"(?<![A-Za-z0-9])s\d{2,4}-\d+",
}


def find_labels(text: str) -> dict:
    t = re.sub(r"```.*?```", "", text or "", flags=re.S)
    t = re.sub(r"`[^`]*`", "", t)
    t = re.sub(r"⟦[^⟧]*⟧", "", t)
    out = {}
    for k, p in LABEL_PATTERNS.items():
        hits = [t[max(0, m.start() - 15):m.end() + 10].replace("\n", " ") for m in re.finditer(p, t)]
        if hits:
            out[k] = hits
    return out


def raw_ops_from_production(a_row: dict) -> list[list[dict]]:
    """本番の探索役が実行した操作(周ごと)。open / by_date だけ。"""
    laps = ((a_row.get("usage") or {}).get("navigator") or {}).get("laps") or []
    out = []
    for lap in laps:
        ops = []
        for d in lap.get("done") or []:
            if d.startswith("open "):
                ops.append({"op": "open", "handle": d[5:].strip()})
            elif d.startswith("by_date "):
                m = re.match(r"by_date (\d{4}-\d{2}-\d{2})(?: to (\d{4}-\d{2}-\d{2}))?(?: \(within (\S+)\))?", d)
                ops.append({"op": "by_date", "date_from": m.group(1), "date_to": m.group(2) or m.group(1),
                            "within": m.group(3)})
            else:
                raise ValueError(f"unsupported op in replay: {d}")
        if ops:
            out.append(ops)
    return out


async def rebuild_materials(c, a_row: dict, user_id: str, thread_id: str, when: datetime, attachments) -> list:
    tz = ZoneInfo(base.TZ_NAME)
    blocked = cs._load_blocked_source_types(user_id)
    nav_input = nav.NavigatorInput(
        message="", selected_text=None, screen_lecture_id=None, recent_conversation=[],
        today=when.astimezone(tz).date(), student_map=load_student_map(c, user_id, tz),
        current_thread_id=thread_id, blocked_source_types=blocked, attachments=attachments,
    )
    tools = nav.NavigatorTools(search=None, source=DbLectureSource(c, user_id, blocked))
    state = nav.NavState()
    for i, ops in enumerate(raw_ops_from_production(a_row), 1):
        reqs, dropped = nav.validate_operations(ops, nav_input, state)
        assert not dropped, f"dropped in replay: {dropped}"
        record = nav.LapRecord(lap=i, status="need_more", missing="", reasoning="", goal=[], requests=reqs)
        state.laps.append(record)
        await nav.execute_lap(record, nav_input, state, tools)
    opened = [op.material for op in state.opened.values() if op.material]
    return opened + [m for m in state.search_materials if not nav._covered_by_opened(m, opened)]


async def build_case(c, case: dict) -> dict:
    """reply_ending_eval/replay.build_case と同じ組み立て + 参照資料。"""
    real_build_answer = cs._build_answer_messages
    captured = {}

    # base.build_case は materials=[] で _build_answer_messages を呼ぶので、参照資料を差し込む
    def with_materials(turn, decision, memory, history, profile, materials, **kw):
        return real_build_answer(turn, decision, memory, history, profile, captured["materials"], **kw)

    a_row = base.find_message(c, case["msg"])
    thread_id = a_row["thread_id"]
    user_id = c.table("chat_threads").select("user_id").eq("id", thread_id).execute().data[0]["user_id"]
    when = datetime.fromisoformat(a_row["created_at"].replace("Z", "+00:00"))
    # 資料のハンドル(A1…)は base.build_case の中で振られる。ここでは参照資料を組むためだけに同じ規則で振る
    att_rows = c.table("chat_attachments").select(cs.ATTACHMENT_COLUMNS + ", deleted_at") \
        .eq("thread_id", thread_id).eq("status", "ready").lt("created_at", a_row["created_at"]).order("created_at").execute().data
    attachments = base.assign_handles([base.Attachment.from_row(r) for r in att_rows if not r.get("deleted_at")])
    captured["materials"] = await rebuild_materials(c, a_row, user_id, thread_id, when, attachments)

    base.VARIANT_PROMPTS.clear()
    base.VARIANT_PROMPTS.add("chat_answer_prompt.txt")
    base.HERE = HERE  # use_variant は HERE/prompts を読む
    cs._build_answer_messages = with_materials
    try:
        b = await base.build_case(c, case)
    finally:
        cs._build_answer_messages = real_build_answer
    b["materials"] = captured["materials"]
    return b


async def run_once(llm, billing, b, case):
    base.FrozenDatetime.frozen = b["when"]
    cs.datetime = base.FrozenDatetime
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
    new_labels = find_labels(state.output_text)
    prod_labels = find_labels(b["a_row"]["content"])
    print(f"  effort={b['effort']} TTFT {first or 0:.2f}s total {total:.2f}s in {state.input_tokens:,} "
          f"out {state.output_tokens:,} ${cost:.4f}")
    print(f"  labels  production: {json.dumps(prod_labels, ensure_ascii=False)}")
    print(f"  labels  new prompt: {json.dumps(new_labels, ensure_ascii=False)}")
    return {
        "case": case["id"], "message_id": b["a_row"]["id"], "user_message": b["u_row"]["content"],
        "info": b["info"], "materials": [m.label for m in b["materials"]],
        "new_answer": state.output_text, "production_answer": b["a_row"]["content"],
        "labels_new": new_labels, "labels_production": prod_labels,
        "citations_new": re.findall(r"⟦[^⟧]*⟧", state.output_text),
        "ttft_s": round(first or 0, 2), "total_s": round(total, 2), "input_tokens": state.input_tokens,
        "output_tokens": state.output_tokens, "cost_usd": round(cost, 6),
    }


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--cases", default="")
    ap.add_argument("--tag", default="v1")
    ap.add_argument("--title-mentions", action="store_true",
                    help="v2: 回答役に渡す生徒のメッセージ・履歴の資料の印を [A1 \"…\"] ではなく [Attached material: \"…\"] にする")
    args = ap.parse_args()
    if args.title_mentions:
        def render_mentions_title_only(text, attachments):
            by_id = {a.id: a for a in attachments}

            def sub(m):
                a = by_id.get(m.group(1))
                return "[removed material]" if a is None else f'[Attached material: "{a.title or "untitled"}"]'
            return base_mentions.MENTION_RE.sub(sub, text or "")
        cs.render_mentions = render_mentions_title_only
        base.render_mentions = render_mentions_title_only
    wanted = [x for x in args.cases.split(",") if x]
    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    billing = BillingEngine(task_type="internal_label_eval")
    llm = UnifiedLLM(billing)
    results = []
    for case in [k for k in CASES if not wanted or k["id"] in wanted]:
        b = await build_case(c, case)
        sys_v = b["messages_variant"][0].content
        sys_p = b["messages_prod_prompt"][0].content
        assert "### INTERNAL LABELS" in sys_v and "### INTERNAL LABELS" not in sys_p, "variant prompt not applied"
        turn_v = b["messages_variant"][-1].content
        print(f"\n## {case['id']}  user: {b['u_row']['content'][:70]!r}")
        print(f"  {json.dumps(b['info'], ensure_ascii=False, default=str)}")
        print(f"  materials: {[m.label for m in b['materials']]}")
        print(f"  production materials: {[m.get('handle') for m in (b['a_row'].get('usage') or {}).get('materials') or []]}")
        print(f"  est tokens variant={base.est(b['messages_variant']):,} (prod recorded input={b['info']['prod_input_tokens']})")
        print(f"  student msg as answerer sees it: {turn_v.split('</student_message>')[0][-160:]!r}")
        print(f"  labels in input (turn msg): A={len(re.findall(r'A[0-9]', turn_v))} has_sources={'<sources>' in turn_v and 'No materials' not in turn_v}")
        if args.dry_run:
            continue
        results.append(await run_once(llm, billing, b, case))
    if args.dry_run:
        print("\nDRY RUN OK (no API calls)")
        return
    print(f"\nTOTAL COST ${billing.total_usd():.4f}")
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    (HERE / "results" / f"{ts}_{args.tag}.json").write_text(
        json.dumps({"total_cost_usd": billing.total_usd(), "results": results}, ensure_ascii=False, indent=2, default=str),
        encoding="utf-8")
    md = ["# Internal label replay (baseline = production)", ""]
    for r in results:
        md += [f"## {r['case']}", "", f"**Student:** {r['user_message']}", "",
               f"**Labels (production):** {json.dumps(r['labels_production'], ensure_ascii=False)}", "",
               f"**Labels (new prompt):** {json.dumps(r['labels_new'], ensure_ascii=False)}", "",
               "### New prompt", "", r["new_answer"], "", "### Production (baseline)", "", r["production_answer"], "", "---", ""]
    (HERE / "results" / f"{ts}_{args.tag}_answers.md").write_text("\n".join(md), encoding="utf-8")
    print("saved", HERE / "results" / f"{ts}_{args.tag}.json")


if __name__ == "__main__":
    asyncio.run(main())
