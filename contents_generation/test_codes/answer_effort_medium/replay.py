"""
推論4段階の確認: 振り分け役 v3 が medium と判定したクロックリカバリの計算(スレッド931543fd、fc388cec、2026-10-04)を、
回答役 Haiku 5.5 の effort medium で解けるか。最初の見込みの確認として2回。

再生: reply_ending_eval/replay.build_case(本番の _build_answer_messages、本番のプロンプト)。違い:
  - effort は medium に固定(本番の当時の記録は needs_reasoning なし)
  - 参照資料(<sources>)は空。擬似コードは会話の履歴(b5a71ab3)にある。当時の探索の記録は今の形式ではない
  - プロフィール・覚え書きは今の値。プロンプトキャッシュなし。時刻は元のメッセージの時刻
Baseline = 当時の本番の返信(古いモデル)。

参照解(擬似コードどおり。送信側1ビット=1.08μs、変化点 1.08 / 3.24 / 7.56 / 8.64 / 9.72μs、lagは毎回リセットしない):
  サンプル時刻 0.5, 1.5, 2.58, 3.66, 4.74, 5.82, 6.90, 7.98, 9.06, 10.14 μs
  lag(各ビットのサンプル時点) 0, 0.08, 0.08, ... 0.08、10ビットとも 1001111010 と正しく読める

  .venv/bin/python contents_generation/test_codes/answer_effort_medium/replay.py --dry-run
  .venv/bin/python contents_generation/test_codes/answer_effort_medium/replay.py --runs 2 [--effort low|medium|high]
"""
import argparse, asyncio, json, re, sys, time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "reply_ending_eval"))
import replay as base  # noqa: E402
from replay import cs, create_client, os  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, StreamState, UnifiedLLM  # noqa: E402

USER_MSG = "fc388cec"
REFERENCE_SAMPLES = ["0.5", "1.5", "2.58", "3.66", "4.74", "5.82", "6.9", "7.98", "9.06", "10.14"]


def find_any(c, prefix):
    """reply_ending_eval.find_message は 11/04 以降だけを探すので、古いスレッドのために全期間で探す"""
    rows = c.table("chat_messages").select("id, thread_id, role, content, status, created_at, router, usage") \
        .eq("thread_id", "931543fd-4959-4a03-abe4-81da16b1ec17").order("created_at").execute().data
    i = next(i for i, r in enumerate(rows) if r["id"].startswith(USER_MSG))
    return rows[i + 1]


def sample_hits(text):
    nums = set(re.findall(r"\d+(?:\.\d+)?", text.replace("μ", " ")))
    norm = {n.rstrip("0").rstrip(".") if "." in n else n for n in nums}
    return [s for s in REFERENCE_SAMPLES if s in norm]


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--runs", type=int, default=2)
    ap.add_argument("--effort", default="medium", choices=["low", "medium", "high"])
    args = ap.parse_args()
    EFFORT = args.effort
    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    base.find_message = lambda c_, prefix: find_any(c_, prefix)
    base.VARIANT_PROMPTS.clear()  # 本番のプロンプト
    b = await base.build_case(c, {"id": "clock_recovery", "msg": "next-of-" + USER_MSG})
    assert b["u_row"]["id"].startswith(USER_MSG)
    msgs = b["messages_prod_prompt"]
    print(json.dumps(b["info"], ensure_ascii=False, default=str))
    print(f"est tokens {base.est(msgs):,}; pseudocode in history: {'StartTimer' in ''.join(m.content for m in msgs if isinstance(m.content, str))}")
    print(f"student: {b['u_row']['content'][:80]!r}")
    if args.dry_run:
        print("DRY RUN OK (no API calls)")
        return
    billing = BillingEngine(task_type="answer_effort_medium")
    llm = UnifiedLLM(billing)
    results = []
    for run in range(1, args.runs + 1):
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
        hits = sample_hits(state.output_text)
        print(f"run {run}: TTFT {first or 0:.2f}s total {total:.2f}s in {state.input_tokens:,} out {state.output_tokens:,} "
              f"${cost:.4f} reference sample times found {len(hits)}/10")
        results.append({"run": run, "effort": EFFORT, "answer": state.output_text, "ttft_s": round(first or 0, 2),
                        "total_s": round(total, 2), "input_tokens": state.input_tokens, "output_tokens": state.output_tokens,
                        "cost_usd": round(cost, 6), "reference_samples_found": hits})
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    payload = {"model": cs.ANSWER_MODEL, "effort": EFFORT, "user_message": b["u_row"]["content"], "info": b["info"],
               "production_answer": b["a_row"]["content"], "total_cost_usd": billing.total_usd(), "runs": results}
    (HERE / "results" / f"{ts}_{EFFORT}.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
    md = [f"# Clock recovery at effort {EFFORT} ({ts})", "", f"**Student:** {b['u_row']['content']}", ""]
    for r in results:
        md += [f"## Run {r['run']} — TTFT {r['ttft_s']}s, total {r['total_s']}s, out {r['output_tokens']:,}, ${r['cost_usd']:.4f}", "", r["answer"], ""]
    md += ["## Production (2026-10-04, older model)", "", b["a_row"]["content"]]
    (HERE / "results" / f"{ts}_{EFFORT}_answers.md").write_text("\n".join(md), encoding="utf-8")
    print(f"TOTAL ${billing.total_usd():.4f}")

asyncio.run(main())
