"""
2段目の要約(chat_summary._fold_level2と同じプロンプト・スキーマ・検証)を、1段目の評価結果
(results/*.json の final_blocks)をつないだ「長いスレッドの代わり」で試す。

保存済みの1段目の節は5本の会話で20節しかないので、言語ごとにつないで1本のスレッドとみなす
(本番の100往復分は25〜35節くらい)。見るもの: 検証に通るか(全節をちょうど1回・順番どおり)、
どれくらい縮んだか、具体的な事実(名前・数字・決めたこと)が残っているか(出力を目で見る)。

  python run_level2_eval.py
"""

import asyncio
import json
import sys
from pathlib import Path

TEST_DIR = Path(__file__).resolve().parent
REPO_ROOT = TEST_DIR.parents[2]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv  # noqa: E402

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from app.services.chat_summary import (  # noqa: E402
    LEVEL2_SCHEMA,
    SUMMARY_MODEL,
    build_level2_messages,
    validate_level2_output,
)
from app.services.helpers.llm_unified import BillingEngine, LLMOptions, UnifiedLLM  # noqa: E402


def long_thread_sections(language: str) -> list[dict]:
    """その言語の会話の1段目の節を、1本のスレッドの通し番号(節・往復)に振り直してつなぐ。"""
    sections, turn_offset = [], 0
    for f in sorted((TEST_DIR / "results").glob("*.json")):
        if f.name.startswith("_"):
            continue
        conv = json.loads(f.read_text(encoding="utf-8"))
        if conv["language"] != language:
            continue
        last_turn = 0
        for block in conv["final_blocks"]:
            for sec in block["sections"]:
                sections.append({"handle": len(sections) + 1, "title": sec["title"], "bullets": sec["bullets"],
                                 "turns": [turn_offset + t for t in sec["turns"]]})
            last_turn = max(last_turn, block["turn_end"])
        turn_offset += last_turn
    return sections


async def run(llm: UnifiedLLM, language: str) -> dict:
    sections = long_thread_sections(language)
    messages = build_level2_messages([], sections, language)
    options = LLMOptions(output_type="json", json_schema=LEVEL2_SCHEMA, temperature=1.0, max_completion_tokens=4000)
    result = await llm.generate(SUMMARY_MODEL, messages, options)
    try:
        groups, error = validate_level2_output(result.output_json, sections, 1), None
    except Exception as e:
        groups, error = [], str(e)
    in_chars = sum(len(s["title"]) + sum(len(b) for b in s["bullets"]) for s in sections)
    out_chars = sum(len(g["title"]) + sum(len(b) for b in g["bullets"]) for g in groups)
    return {"language": language, "sections_in": len(sections), "groups_out": len(groups), "valid": error is None,
            "error": error, "chars_in": in_chars, "chars_out": out_chars,
            "ratio": round(out_chars / in_chars, 2) if in_chars else None, "input": sections, "groups": groups}


async def main() -> None:
    billing = BillingEngine(task_type="chat_summary_level2_eval")
    llm = UnifiedLLM(billing)
    results = await asyncio.gather(run(llm, "ja"), run(llm, "en"))
    for r in results:
        print(f"\n=== {r['language']}: {r['sections_in']} sections → {r['groups_out']} groups, "
              f"valid={r['valid']} {r['error'] or ''} chars {r['chars_in']} → {r['chars_out']} (×{r['ratio']})")
        for g in r["groups"]:
            print(f"H{g['handle']} {g['title']}  ← S{', S'.join(map(str, g['children']))}")
            for b in g["bullets"]:
                print(f"  - {b}")
    out = TEST_DIR / "results" / "_level2.json"
    out.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\ncost ${billing.total_usd():.4f} → {out.relative_to(TEST_DIR)}")


if __name__ == "__main__":
    asyncio.run(main())
