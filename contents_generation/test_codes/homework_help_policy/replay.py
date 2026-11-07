"""
宿題の手伝い方の新しい方針(docs/homework_help_policy.md、2026-11-07)を入れた回答役のプロンプト案の、最初の見込みの確認。
変更: prompts/chat_answer_prompt.txt の HOMEWORK AND GRADED WORK と、返信の終わり方のルール3。
  - 既定は最後まで解いて、各ステップに理由と講義とのつながりを付ける
  - 段階的な手伝い方(ヒント・穴埋め・別の例…)は、生徒がそう頼んだときだけ
  - エッセイ・レポートは自分で書けるところまで(書き出しの1〜2文は可、全文は不可)
  - AI禁止の課題は今までどおり提出物を書かない

Cases(本番の宿題のターン、各1回):
  clock_recovery: 擬似コードを8%遅い送信で10ビット追う(931543fd / fc388cec)
  lambda_grading: 問1〜問3の自分の答え(ラムダの評価)を見てほしい(3f8d3695 / c7a89472)
  ocaml_first:    OCaml の課題全体を貼って「一問目から解いていきたい」(aca016f4 / 4ea6a277)

再生: reply_ending_eval/replay.build_case(本番の _build_answer_messages)。違い:
  - effort は medium に固定(4段階化の案で、この程度の問題は medium)
  - 参照資料(<sources>)は空。当時の探索の記録は今の形式ではないものがある
  - プロフィール・覚え書きは今の値。プロンプトキャッシュなし。時刻は元のメッセージの時刻
Baseline = 本番の返信(Supabase)。clock_recovery は answer_effort_medium の6本(今のプロンプト)とも比べる。

  .venv/bin/python contents_generation/test_codes/homework_help_policy/replay.py --dry-run
  .venv/bin/python contents_generation/test_codes/homework_help_policy/replay.py
"""
import argparse, asyncio, json, re, sys, time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "reply_ending_eval"))
import replay as base  # noqa: E402
from replay import cs, create_client, os  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, StreamState, UnifiedLLM  # noqa: E402

EFFORT = "medium"
SECTION_MARK = "Holding the answer back and asking them to try a step first rarely makes them learn more"
CASES = [
    {"id": "clock_recovery", "thread": "931543fd", "msg": "fc388cec"},
    {"id": "lambda_grading", "thread": "3f8d3695", "msg": "c7a89472"},
    {"id": "ocaml_first", "thread": "aca016f4", "msg": "4ea6a277"},
]
# 「まず自分でやってみて」型の言い回し(目安。最後は本文を読んで判断する)
TRY_FIRST = r"やってみて|試してみて|考えてみて|教えてくれ|教えてもら|どうなると思|埋めてみ|計算してみ|try (it|this)|your turn"
CLOCK_SAMPLES = ["0.5", "1.5", "2.58", "3.66", "4.74", "5.82", "6.9", "7.98", "9.06", "10.14"]


def find_after(c, case):
    th = next(r for r in c.table("chat_threads").select("id").execute().data if r["id"].startswith(case["thread"]))
    rows = c.table("chat_messages").select("id, thread_id, role, content, status, created_at, router, usage") \
        .eq("thread_id", th["id"]).order("created_at").execute().data
    i = next(i for i, r in enumerate(rows) if r["role"] == "user" and r["id"].startswith(case["msg"]))
    return rows[i + 1]


def clock_hits(text):
    nums = {n.rstrip("0").rstrip(".") if "." in n else n for n in re.findall(r"\d+(?:\.\d+)?", text)}
    return sum(s in nums for s in CLOCK_SAMPLES)


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--cases", default="")
    ap.add_argument("--tag", default="v1")
    args = ap.parse_args()
    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    base.HERE = HERE
    base.VARIANT_PROMPTS.clear()
    base.VARIANT_PROMPTS.add("chat_answer_prompt.txt")
    wanted = [x for x in args.cases.split(",") if x]
    billing = BillingEngine(task_type="homework_help_policy")
    llm = UnifiedLLM(billing)
    results = []
    for case in [k for k in CASES if not wanted or k["id"] in wanted]:
        base.find_message = lambda c_, prefix, case=case: find_after(c_, case)
        b = await base.build_case(c, case)
        assert b["u_row"]["id"].startswith(case["msg"])
        msgs = b["messages_variant"]
        assert SECTION_MARK in msgs[0].content and SECTION_MARK not in b["messages_prod_prompt"][0].content, "variant not applied"
        print(f"\n## {case['id']}  user: {b['u_row']['content'][:70]!r}")
        print(f"  {json.dumps(b['info'], ensure_ascii=False, default=str)}")
        print(f"  est tokens {base.est(msgs):,}; production reply: {len(b['a_row']['content'])} chars")
        if args.dry_run:
            continue
        base.FrozenDatetime.frozen = b["when"]
        cs.datetime = base.FrozenDatetime
        n0 = len(billing.records)
        state = StreamState()
        opts = cs.answer_options(cs.ANSWER_MODEL, EFFORT, cs._answer_max_tokens(None, []))
        t0 = time.perf_counter(); first = None
        try:
            async for _ in llm.generate_stream(cs.ANSWER_MODEL, msgs, state, opts):
                if first is None:
                    first = time.perf_counter() - t0
        finally:
            cs.datetime = datetime
        total = time.perf_counter() - t0
        cost = sum(r.cost_usd for r in billing.records[n0:])
        text = state.output_text
        r = {"case": case["id"], "message_id": b["a_row"]["id"], "user_message": b["u_row"]["content"], "effort": EFFORT,
             "new_answer": text, "production_answer": b["a_row"]["content"],
             "try_first_new": re.findall(TRY_FIRST, text), "try_first_production": re.findall(TRY_FIRST, b["a_row"]["content"]),
             "clock_samples_found": clock_hits(text) if case["id"] == "clock_recovery" else None,
             "ttft_s": round(first or 0, 2), "total_s": round(total, 2), "input_tokens": state.input_tokens,
             "output_tokens": state.output_tokens, "cost_usd": round(cost, 6), "info": b["info"]}
        print(f"  TTFT {r['ttft_s']}s total {r['total_s']}s out {r['output_tokens']:,} ${cost:.4f}  try-first phrases "
              f"new={r['try_first_new']} production={r['try_first_production']}"
              + (f"  clock samples {r['clock_samples_found']}/10" if r["clock_samples_found"] is not None else ""))
        results.append(r)
    if args.dry_run:
        print("\nDRY RUN OK (no API calls)")
        return
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    (HERE / "results").mkdir(exist_ok=True)
    (HERE / "results" / f"{ts}_{args.tag}.json").write_text(
        json.dumps({"total_cost_usd": billing.total_usd(), "results": results}, ensure_ascii=False, indent=2, default=str),
        encoding="utf-8")
    md = [f"# Homework help policy replay {args.tag} (effort {EFFORT}, baseline = production)", ""]
    for r in results:
        md += [f"## {r['case']} ({r['message_id']})", "", f"**Student:** {r['user_message']}", "",
               f"**Cost:** ${r['cost_usd']:.4f}, TTFT {r['ttft_s']}s, total {r['total_s']}s, out {r['output_tokens']:,}", "",
               "### New prompt", "", r["new_answer"], "", "### Production (baseline)", "", r["production_answer"], "", "---", ""]
    (HERE / "results" / f"{ts}_{args.tag}_answers.md").write_text("\n".join(md), encoding="utf-8")
    print(f"\nTOTAL ${billing.total_usd():.4f}")


if __name__ == "__main__":
    asyncio.run(main())
