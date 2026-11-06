"""
回答役のプロンプトキャッシュが、今回の変更で効かなくならないかの確認(本番の組み立てとキャッシュの印をそのまま使う)。

同じターン(10/29の範囲の質問、replay.pyで作った材料)の回答役のメッセージを、本番の
apply_prompt_cache_controls で印を付けて2回送る:
  1回目: ふだんの上限(ANSWER_MAX_OUTPUT_TOKENS)
  2回目: 範囲の材料があるときの上限(ANSWER_MAX_OUTPUT_TOKENS_WIDE)
max_tokens が変わってもキャッシュから読めるか(cache_read_tokens)を見る。Anthropicの資料には
max_tokensがキャッシュを無効にするかが書かれていない(2026-11-06に確認)ため。

  .venv/bin/python contents_generation/test_codes/range_overview_eval/cache_check.py --dry-run
  .venv/bin/python contents_generation/test_codes/range_overview_eval/cache_check.py
"""

import argparse
import asyncio
import json
import os
from datetime import datetime

from replay import CASES, HERE, FrozenDatetime, build_inputs, cs, load_case

from supabase import create_client  # noqa: E402

from app.services.chat_attachments import estimate_tokens  # noqa: E402
from app.services.chat_materials import Material  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, StreamState, UnifiedLLM  # noqa: E402

CASE_ID = "pl_oct29_scope"


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    src = sorted((HERE / "results").glob("*_replay.json"))[-1]
    saved = {r["case"]: r for r in json.loads(src.read_text(encoding="utf-8"))["results"]}[CASE_ID]
    case = next(c for c in CASES if c["id"] == CASE_ID)
    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    data = load_case(c, case)
    _ni, _tools, turn, decision, memory, history, _b, _l = await build_inputs(c, case, data, [])
    materials = [Material(key=m["key"], kind=m["kind"], label=m["label"], content=saved["material_contents"][m["key"]],
                          compressed=m["compressed"]) for m in saved["materials"]]
    FrozenDatetime.frozen = data["when"]
    cs.datetime = FrozenDatetime
    messages = cs._build_answer_messages(turn, decision, memory, history, cs._load_student_profile(c, turn.user_id),
                                         materials, retrieval_reasoning=saved["navigator"]["laps"][-1]["reasoning"])
    messages, _ = cs.fit_answer_input(messages)
    messages = cs.apply_prompt_cache_controls(messages, cs.ANSWER_MODEL)
    marked = [i for i, m in enumerate(messages) if getattr(m, "cache_control", None)]
    print(f"messages={len(messages)} cache marks at {marked} (roles {[messages[i].role for i in marked]}); "
          f"system ~{estimate_tokens(messages[0].content):,} est tokens; "
          f"answer rule in system: {'internal codes such as C4' in messages[0].content}")
    configs = [("normal", cs.ANSWER_MAX_OUTPUT_TOKENS), ("wide", cs.ANSWER_MAX_OUTPUT_TOKENS_WIDE)]
    for name, max_out in configs:
        o = cs.answer_options(cs.ANSWER_MODEL, cs.ANSWER_REASONING_EFFORT, max_out)
        print(f"  {name}: max_tokens={o.max_tokens} reasoning_effort={o.reasoning_effort} temperature={o.temperature}")
    if args.dry_run:
        return
    billing = BillingEngine(task_type="answer_cache_check")
    llm = UnifiedLLM(billing)
    rows = []
    for name, max_out in configs:
        opts = cs.answer_options(cs.ANSWER_MODEL, cs.ANSWER_REASONING_EFFORT, max_out)
        state = StreamState()
        n = len(billing.records)
        async for _ in llm.generate_stream(cs.ANSWER_MODEL, messages, state, opts):
            pass
        cost = sum(r.cost_usd for r in billing.records[n:])
        rows.append({"call": name, "max_tokens": opts.max_tokens, "input_tokens": state.input_tokens,
                     "cache_read_tokens": state.cache_read_tokens, "cache_write_tokens": state.cache_write_tokens,
                     "output_tokens": state.output_tokens, "cost_usd": round(cost, 6)})
        print(f"  {name}: in={state.input_tokens:,} cache_read={state.cache_read_tokens:,} "
              f"cache_write={state.cache_write_tokens:,} out={state.output_tokens:,} ${cost:.4f}")
    cs.datetime = datetime
    out = HERE / "results" / f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_cache_check.json"
    out.write_text(json.dumps({"case": CASE_ID, "rows": rows, "total_cost_usd": billing.total_usd()}, indent=2), encoding="utf-8")
    print(f"TOTAL ${billing.total_usd():.4f}  saved {out}")


if __name__ == "__main__":
    asyncio.run(main())
