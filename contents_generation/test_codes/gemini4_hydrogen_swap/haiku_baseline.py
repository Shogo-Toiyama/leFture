"""
Haiku 5.5 ベースライン再実行 (Hydrogen と同条件の比較用)

Hydrogen の第1ラウンドと同じ入力・同じ本番プロンプト・同じ本番 Service で、モデルだけ
anthropic/claude-haiku-5-5 (本番の設定: effort low, max_tokens 32000, cache_control あり) にして
RC / DN / FF を1回ずつ実行する。前回実験(v2〜v4)は今日の本番プロンプトと違う版だったため。
チャットは本番の Haiku 回答(Supabase に保存済み)をそのまま使うので再実行しない。

  .venv/bin/python contents_generation/test_codes/gemini4_hydrogen_swap/haiku_baseline.py dryrun
  .venv/bin/python contents_generation/test_codes/gemini4_hydrogen_swap/haiku_baseline.py run
"""
import asyncio
import json
import sys
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import swap_experiment as S  # noqa: E402

HAIKU = "anthropic/claude-haiku-5-5"
BUDGET_CAP_USD = 0.03  # Haiku 3呼び出しの概算は約$0.01。これを超えたら中止


async def main(mode: str) -> None:
    dry = mode == "dryrun"
    base = S.base
    base.MODEL, base.REASONING_EFFORT, base.MAX_TOKENS = HAIKU, "low", 32000
    base._disable_r2_cache()
    base._install_prompt_loader("v0")  # v0 = 本番プロンプトそのもの
    results, total = [], 0.0
    for task in ("review_cards", "deep_notes", "fun_facts"):
        lid, topic = S.LECTURES[task]
        inp = json.loads((S.INPUTS_DIR / f"{lid}.json").read_text(encoding="utf-8"))
        if total > BUDGET_CAP_USD:
            raise SystemExit(f"cap ${BUDGET_CAP_USD} exceeded: ${total:.4f}")
        r = await base.run_one(task, inp, dry, {}, {topic})
        r["checks"] = base.check(r)
        total += r["token_cost_usd"]
        c = r["calls"][0] if r["calls"] else {}
        print(f"[{task}] error={r['error']} calls={len(r['calls'])} cost=${r['token_cost_usd']} "
              f"sec={c.get('elapsed_seconds')} in={c.get('input_tokens')} out={c.get('output_tokens')} "
              f"model={c.get('model')} effort={c.get('request_kwargs', {}).get('reasoning_effort')}")
        results.append(r)
    if dry:
        print("DRY RUN OK (no API calls)")
        return
    d = S.RESULTS_DIR / f"{datetime.now():%Y%m%d_%H%M%S}_haiku_baseline"
    d.mkdir(parents=True, exist_ok=True)
    (d / "raw.json").write_text(json.dumps(results, ensure_ascii=False, indent=1, default=str), encoding="utf-8")
    print(f"total ${total:.4f}\nsaved: {d}")


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else "dryrun"))
