"""
Review Cards が英語で出力されてしまった4トピックを再現して、原因を切り分ける小実験。

- A (v0 そのまま): dry-run で記録した本番プロンプト(system + user)をそのまま 3 回ずつ呼ぶ
- B (末尾に言語指示): user メッセージの末尾に OUTPUT LANGUAGE を 1 文だけ再掲して 3 回ずつ呼ぶ
モデル・オプションは本実験と同じ (Haiku 5.5, reasoning_effort=low, max_tokens=32000)。
"""
import asyncio
import dataclasses
import glob
import json
import re
import sys
from datetime import datetime
from pathlib import Path

EXP = Path(__file__).resolve().parent
sys.path.insert(0, str(EXP))
import run_experiment as E  # noqa: E402  (env / sys.path 設定も兼ねる)
from app.services.helpers.llm_unified import BillingEngine, LLMOptions, Message, UnifiedLLM  # noqa: E402

TARGETS = [("a028aad6", 0), ("ed333ded", 0), ("ed333ded", 4), ("de2d74b0", 0)]  # (lecture prefix, call index)
REPEATS = 3
JP = re.compile(r"[぀-ヿ一-鿿]")


def jp_ratio(out: dict) -> float:
    texts = []
    for c in out.get("review_cards", []):
        texts.append(c.get("title") or "")
        for b in c.get("content_blocks", []):
            texts += [b.get("text") or ""] + list(b.get("items") or [])
    body = re.sub(r"\s|⟦[^⟧]*⟧", "", "".join(texts))
    return len(JP.findall(body)) / max(1, len(body))


async def main() -> None:
    dry = json.loads(Path(sorted(glob.glob(str(EXP / "results/*_dryrun_v0")))[-1], "raw.json").read_text())
    billing = BillingEngine()
    llm = UnifiedLLM(billing)
    opts = LLMOptions(output_type="json", temperature=0.3, reasoning_effort=E.REASONING_EFFORT, max_tokens=E.MAX_TOKENS)
    jobs = []
    for prefix, idx in TARGETS:
        r = next(x for x in dry["results"] if x["task"] == "review_cards" and x["lecture_id"].startswith(prefix))
        msgs = r["calls"][idx]["messages"]
        lang = r["language"]["content_language"]
        for variant in ("A_v0", "B_lang_reminder"):
            user = msgs[1]["content"]
            if variant == "B_lang_reminder":
                user += f"\n\nWrite every card title and every text field in {lang}."
            m = [Message(role="system", content=msgs[0]["content"]), Message(role="user", content=user)]
            for i in range(REPEATS):
                jobs.append((prefix, idx, variant, i, m))

    sem = asyncio.Semaphore(6)

    async def go(job):
        prefix, idx, variant, i, m = job
        async with sem:
            res = await llm.generate(E.MODEL, m, dataclasses.replace(opts))
        out = res.output_json or {}
        return {"lecture": prefix, "topic_pos": idx, "variant": variant, "rep": i,
                "jp_ratio": round(jp_ratio(out), 2),
                "titles": [c.get("title") for c in out.get("review_cards", [])],
                "out_tokens": res.output_tokens, "finish": res.finish_reason}

    rows = await asyncio.gather(*(go(j) for j in jobs))
    cost = round(sum(r.cost_usd for r in billing.records if r.dimension == "tokens"), 4)
    for r in rows:
        print(r["lecture"], r["topic_pos"], r["variant"], r["rep"], r["jp_ratio"], r["titles"][:2])
    print("token cost $", cost)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out = EXP / "results" / f"{ts}_probe_language_drift.json"
    out.write_text(json.dumps({"rows": rows, "token_cost_usd": cost}, ensure_ascii=False, indent=1))
    print("saved", out)


if __name__ == "__main__":
    asyncio.run(main())
