"""
資料添付の目次づくり(chat_attachments.read_attachment)を、2.5 Flash-LiteとGPT-6 Lunaで比べる(2026-10-04)。

本番のコード(区切り・プロンプト・波で読む処理)をそのまま使い、モデルだけ差し替える。
文書は実在のもの3本(日本語の長い設計書・英語の利用規約・日本語の短めのメモ)。
採点はClaudeが構成名を伏せたblind_*.mdを読んで行う(「この目次だけで、どの節に何があるか分かるか」)。

実行例:
  python run_toc.py
"""

import asyncio
import json
import random
import sys
import time
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv  # noqa: E402

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

import app.services.chat_attachments as ca  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, UnifiedLLM  # noqa: E402

RESULTS_DIR = Path(__file__).parent / "results"
DOCS = {
    "roadmap_ja": REPO_ROOT / "docs/chatbot_context_and_retrieval_roadmap.md",
    "tos_en": REPO_ROOT / "docs/legal_docs/version_05/terms_of_service.md",
    "launch_tips_ja": REPO_ROOT / "docs/launch_tips.md",
}
MODELS = {"flash_lite": "gemini/gemini-2.5-flash-lite", "luna": "gpt-6-luna"}
# ONLY=luna python run_toc.py: 本番の形(並列の小さな束)でLunaだけ回す
import os  # noqa: E402
if os.environ.get("ONLY"):
    MODELS = {k: v for k, v in MODELS.items() if k == os.environ["ONLY"]}


async def run_one(model: str, text: str) -> dict:
    ca.ATTACHMENT_MODEL = model
    billing = BillingEngine(task_type="CHAT_MESSAGE")
    llm = UnifiedLLM(billing)
    t0 = time.perf_counter()
    r = await ca.read_attachment(llm, text)
    return {
        "seconds": round(time.perf_counter() - t0, 1),
        "cost_usd": billing.total_usd(),
        "blocked": r.blocked, "error": r.error,
        "title": r.title, "summary": r.summary,
        "sections": [s.to_json() for s in r.sections],
        "usage": r.usage_json(),
    }


async def main() -> None:
    RESULTS_DIR.mkdir(exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out: dict = {}
    for doc, path in DOCS.items():
        text = path.read_text()
        out[doc] = {"chars": len(text)}
        for name, model in MODELS.items():
            print(f"▶ {doc} × {name}")
            out[doc][name] = await run_one(model, text)
            # 現行の(GPT系の)オプションの違いで失敗していないか、すぐ見えるように
            print(f"  {out[doc][name]['seconds']}s ${out[doc][name]['cost_usd']:.5f} "
                  f"blocked={out[doc][name]['blocked']} error={out[doc][name]['error']}")
    (RESULTS_DIR / f"run_{stamp}.json").write_text(json.dumps(out, ensure_ascii=False, indent=2))

    # 構成名を伏せた採点用(文書ごとにX/Yをランダムに割り当てる)
    key, lines = {}, []
    for doc, res in out.items():
        names = list(MODELS)
        random.shuffle(names)
        key[doc] = dict(zip(["X", "Y"], names))
        # 1構成だけのときもX一つで出す
        lines.append(f"# {doc} ({res['chars']:,} chars)\n")
        for label, name in zip(["X", "Y"], names):
            r = res[name]
            lines.append(f"## {label}\n\n**{r['title']}**\n\n{r['summary']}\n")
            for s in r["sections"]:
                lines.append(f"- S{s['index']} [{s['start']}-{s['end']}] **{s['title']}** — {s['description']}")
            lines.append("")
    (RESULTS_DIR / f"blind_{stamp}.md").write_text("\n".join(lines))
    (RESULTS_DIR / f"key_{stamp}.json").write_text(json.dumps(key, indent=2))
    print(f"✅ results/blind_{stamp}.md")


if __name__ == "__main__":
    asyncio.run(main())
