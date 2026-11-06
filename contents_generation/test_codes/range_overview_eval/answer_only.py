"""
回答役だけをもう一度回す(探索役は呼ばない)。replay.py の結果(results/*_replay.json)に保存した材料を
そのまま使い、回答役のプロンプト(chat_answer_prompt.txt)だけを patched/ の版に差し替える。

確かめたいこと: 回答に内部の記号(C4、C4/L11、L11、T1 など)が出ないか。出た数を、元の回答
(同じ材料・本番のプロンプト)と比べる。

  .venv/bin/python contents_generation/test_codes/range_overview_eval/answer_only.py --dry-run
  .venv/bin/python contents_generation/test_codes/range_overview_eval/answer_only.py
"""

import argparse
import asyncio
import json
import os
import re
import time
from datetime import datetime

import replay  # install() 済みのパッチ版の探索役と chat_service
from replay import CASES, HERE, FrozenDatetime, build_inputs, cs, load_case

from supabase import create_client  # noqa: E402

from app.services.chat_materials import Material  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, StreamState, UnifiedLLM  # noqa: E402

PROMPT = HERE / "patched" / "chat_answer_prompt.txt"
_CODE_RE = re.compile(r"(?<![A-Za-z0-9])(?:C\d+(?:/L\d+(?:-\d+)?)?(?:/T\d+)?|L\d+(?:\s*[-〜~]\s*L?\d+)?|T\d+(?:\s*[-〜~]\s*T?\d+)?)(?![A-Za-z0-9])")


def internal_codes(text: str) -> list[str]:
    return _CODE_RE.findall(re.sub(r"⟦[^⟧]*⟧", "", text or ""))


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--from", dest="src", default=None, help="results/*_replay.json (default: latest)")
    args = ap.parse_args()
    src = args.src or sorted((HERE / "results").glob("*_replay.json"))[-1]
    saved = {r["case"]: r for r in json.loads(open(src, encoding="utf-8").read())["results"]}
    print("materials from", src)

    orig_load = cs._load_prompt
    cs._load_prompt = lambda name: PROMPT.read_text(encoding="utf-8") if name == "chat_answer_prompt.txt" else orig_load(name)

    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    billing = BillingEngine(task_type="answer_codes")
    llm = UnifiedLLM(billing)
    rows = []
    for case in CASES:
        s = saved[case["id"]]
        data = load_case(c, case)
        _nav_input, _tools, turn, decision, memory, history, _blocked, _label = await build_inputs(c, case, data, [])
        materials = [Material(key=m["key"], kind=m["kind"], label=m["label"], content=s["material_contents"][m["key"]],
                              compressed=m["compressed"]) for m in s["materials"]]
        retrieval_reasoning = s["navigator"]["laps"][-1]["reasoning"] if s["navigator"]["laps"] else ""
        FrozenDatetime.frozen = data["when"]
        cs.datetime = FrozenDatetime
        messages = cs._build_answer_messages(turn, decision, memory, history, cs._load_student_profile(c, turn.user_id),
                                             materials, retrieval_reasoning=retrieval_reasoning)
        cs.datetime = datetime
        messages, _ = cs.fit_answer_input(messages)
        before = internal_codes(s["answer"]["text"])
        assert "internal codes such as C4" in messages[0].content, "patched answer prompt not loaded"
        print(f"\n## {case['id']}  materials={len(materials)}  codes in the earlier answer: {len(before)} {before[:8]}")
        if args.dry_run:
            continue
        opts = cs.answer_options(cs.ANSWER_MODEL, cs.ANSWER_REASONING_EFFORT, cs._answer_max_tokens(None, materials))
        state = StreamState()
        n_rec = len(billing.records)
        t0 = time.perf_counter()
        first = None
        async for _ in llm.generate_stream(cs.ANSWER_MODEL, messages, state, opts):
            if first is None:
                first = time.perf_counter() - t0
        total = time.perf_counter() - t0
        after = internal_codes(state.output_text)
        cost = sum(r.cost_usd for r in billing.records[n_rec:])
        rows.append({"case": case["id"], "codes_before": before, "codes_after": after, "answer": state.output_text,
                     "earlier_answer": s["answer"]["text"], "first_token_s": round(first or 0, 2), "seconds": round(total, 2),
                     "input_tokens": state.input_tokens, "output_tokens": state.output_tokens, "cost_usd": round(cost, 6)})
        print(f"  codes now: {len(after)} {after[:8]}  first token {first:.2f}s, total {total:.2f}s, "
              f"in {state.input_tokens:,} / out {state.output_tokens:,}, ${cost:.4f}")
    if args.dry_run:
        return
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out = HERE / "results" / f"{ts}_answer_codes.json"
    out.write_text(json.dumps({"source": str(src), "prompt_line": "see patched/chat_answer_prompt.txt (CITATIONS section)",
                               "total_cost_usd": billing.total_usd(), "rows": rows}, ensure_ascii=False, indent=2), encoding="utf-8")
    md = ["# Answers without internal codes", ""]
    for r in rows:
        md += [f"## {r['case']} (codes: {len(r['codes_before'])} → {len(r['codes_after'])})", "", r["answer"], "", "---", ""]
    (HERE / "results" / f"{ts}_answer_codes.md").write_text("\n".join(md), encoding="utf-8")
    print(f"\nTOTAL COST ${billing.total_usd():.4f}\nsaved {out}")


if __name__ == "__main__":
    asyncio.run(main())
