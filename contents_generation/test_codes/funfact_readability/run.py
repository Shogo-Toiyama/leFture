"""
Fun Fact readability & tone experiment (Haiku 5.5)

Question: with a VOICE section (chat/Review-Cards-level energy, hype words welcome, everyday words) and
readability rules (no subject/predicate mismatch, no cramming, connected steps, pay off teasers),
do Fun Facts read more easily and feel more exciting?

Baseline = production fun_facts already in Supabase (production runs Haiku 5.5, reasoning_effort=low,
max_tokens=32000), so only the new prompt is generated.

Everything except the prompt file is the production code path:
  - app.services.logic.fun_fact_generation.FunFactGenerationService.run_from_memory
  - core_extraction / brainstorming seed / search results downloaded from R2 for the lecture's completed job
  - student_profile and content_language fetched the same way task_runners does
    (student_profile is read now, so it can differ from the one used when production ran)
Safety: no writes to Supabase or R2.

Usage (from repo root):
  .venv/bin/python contents_generation/test_codes/funfact_readability/run.py prepare
  .venv/bin/python contents_generation/test_codes/funfact_readability/run.py dryrun
  .venv/bin/python contents_generation/test_codes/funfact_readability/run.py run
"""

import argparse
import asyncio
import json
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List

EXP_DIR = Path(__file__).resolve().parent
REPO_ROOT = EXP_DIR.parents[2]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv  # noqa: E402

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from app.core.supabase import get_supabase_client  # noqa: E402
from app.services.helpers import helpers as H  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, LLMResult, UnifiedLLM  # noqa: E402
from app.services.logic import fun_fact_generation as ff_mod  # noqa: E402
from app.services import task_runners as TR  # noqa: E402

LECTURES = [
    "4ff6ef52",  # DNS、NAT、鍵共有 -> Logjam
    "279da655",  # 火星探査車の安全モード
    "e68ef90c",  # Signal の鍵変更通知
]
PROMPT_FILE = "fun_fact_generation_prompt.txt"
INPUTS_DIR = EXP_DIR / "inputs"
RESULTS_DIR = EXP_DIR / "results"
PROMPTS_DIR = EXP_DIR / "prompts"


def prepare() -> None:
    sb = get_supabase_client()
    for prefix in LECTURES:
        # lecture_id is a uuid column, so resolve the full id from recent lectures
        lec = next(l for l in sb.table("lectures").select("id,user_id,title,title_generated")
                   .gte("created_at", "2026-11-05").execute().data if l["id"].startswith(prefix))
        lid = lec["id"]
        job = sb.table("processing_jobs").select("id").eq("lecture_id", lid).eq("status", "COMPLETED") \
            .order("created_at", desc=True).limit(1).execute().data[0]
        p = lambda t: TR._get_dependency_payload_sync(job["id"], t)  # noqa: E731
        core = TR._download_from_r2_to_memory_sync(p("CORE_EXTRACTION")["core_extraction_path"])
        bp = p("FUN_FACT_BRAINSTORMING").get("fun_fact_brainstorming_path")
        seed = TR._download_from_r2_to_memory_sync(bp) if bp else {}
        sp = p("FUN_FACT_SEARCH").get("search_results_path")
        search = TR._download_from_r2_to_memory_sync(sp) if sp else []
        content_language, _, _ = H._get_content_language_context(lid)
        ff = sb.table("fun_facts").select("title,hook,body,metadata,created_at").eq("lecture_id", lid) \
            .is_("deleted_at", "null").execute().data
        data = {"lecture": lec, "job_id": job["id"], "content_language": content_language,
                "student_profile": H._get_student_profile(lec["user_id"]), "core_extraction": core,
                "fun_fact_seed": seed, "fun_fact_search": search, "production_fun_fact": ff[0] if ff else None}
        (INPUTS_DIR / f"{lid}.json").write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"✅ {lid[:8]} {lec.get('title') or lec.get('title_generated')} | lang={content_language} | "
              f"seed={'yes' if seed else 'no'} search={len(search)} | prod={'yes' if ff else 'no'}")


class ExperimentLLM(UnifiedLLM):
    def __init__(self, billing: BillingEngine, dry_run: bool):
        super().__init__(billing)
        self.dry_run = dry_run
        self.calls: List[Dict[str, Any]] = []

    async def generate(self, model, messages, options=None):  # type: ignore[override]
        kwargs = self._build_kwargs(model, messages, options)
        rec: Dict[str, Any] = {"model": model, "request_kwargs": {k: v for k, v in kwargs.items() if k != "messages"},
                               "system_chars": len(messages[0].content), "user_chars": len(messages[1].content)}
        if self.dry_run:
            rec["messages"] = [{"role": m.role, "content": m.content} for m in messages]
            self.calls.append(rec)
            j = {"title": "dry", "hook": "dry", "body": "dry"}
            return LLMResult(output_text=json.dumps(j), output_json=j, model_used="mock")
        n = len(self.billing.records)
        t0 = time.perf_counter()
        res = await super().generate(model, messages, options)
        rec.update(elapsed_seconds=round(time.perf_counter() - t0, 2), input_tokens=res.input_tokens,
                   output_tokens=res.output_tokens, finish_reason=res.finish_reason,
                   json_parse_error=res.json_parse_error,
                   cost_usd=round(sum(r.cost_usd for r in self.billing.records[n:] if r.dimension == "tokens"), 6),
                   output_text=res.output_text)
        self.calls.append(rec)
        return res


def _stats(ff: Dict[str, Any]) -> Dict[str, Any]:
    body = re.sub(r"⟦[^⟧]*⟧", "", ff.get("body") or "")
    hook = ff.get("hook") or ""
    sent = lambda t: [s for s in re.split(r"[。！？!?]", t) if s.strip()]  # noqa: E731
    bs = sent(body)
    return {"hook_chars": len(hook), "hook_sentences": len(sent(hook)), "body_chars": len(body),
            "body_sentences": len(bs), "body_avg_sentence_chars": round(sum(map(len, bs)) / max(1, len(bs)), 1),
            "exclamations": (hook + body).count("！") + (hook + body).count("!"),
            "noda_endings": (hook + body).count("のです")}


async def run(mode: str, version: str) -> None:
    dry = mode == "dryrun"
    prompt_path = PROMPTS_DIR / version / PROMPT_FILE
    original_loader = H._load_prompt
    ff_mod._load_prompt = lambda f: prompt_path.read_text(encoding="utf-8") if f == PROMPT_FILE else original_loader(f)  # type: ignore
    inputs = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(INPUTS_DIR.glob("*.json"))]
    inputs.sort(key=lambda d: next(i for i, pre in enumerate(LECTURES) if d["lecture"]["id"].startswith(pre)))

    async def one(inp):
        billing = BillingEngine(task_type="FUN_FACT")
        llm = ExperimentLLM(billing, dry)
        svc = ff_mod.FunFactGenerationService(llm, H.TaskLogger(inp["lecture"]["user_id"], inp["lecture"]["id"], "EXP:ff"))
        err, out = None, None
        try:
            out = await svc.run_from_memory(core_data=inp["core_extraction"], seed_data=inp["fun_fact_seed"],
                                            search_results=inp["fun_fact_search"],
                                            student_profile=inp["student_profile"],
                                            content_language=inp["content_language"])
        except Exception as e:  # record failures as results
            err = f"{type(e).__name__}: {e}"
        return {"lecture_id": inp["lecture"]["id"], "error": err, "output": out, "calls": llm.calls,
                "production": inp["production_fun_fact"]}

    t0 = time.perf_counter()
    results = await asyncio.gather(*(one(i) for i in inputs))
    wall = round(time.perf_counter() - t0, 1)
    cost = round(sum(c.get("cost_usd") or 0 for r in results for c in r["calls"]), 6)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = RESULTS_DIR / f"{ts}_{mode}_{version}"
    out_dir.mkdir(parents=True, exist_ok=True)
    meta = {"mode": mode, "prompt_version": version, "prompt_path": str(prompt_path.relative_to(EXP_DIR)),
            "lectures": [r["lecture_id"] for r in results], "wall_seconds": wall, "token_cost_usd": cost}
    for r in results:
        if r["output"] and not dry:
            r["stats"] = {"production": _stats(r["production"] or {}), version: _stats(r["output"])}
    (out_dir / "raw.json").write_text(json.dumps({"meta": meta, "results": results}, ensure_ascii=False, indent=1),
                                      encoding="utf-8")
    if not dry:
        md = [f"# Fun Fact readability — {version} vs production\n",
              f"```\n{json.dumps(meta, ensure_ascii=False, indent=1)}\n```\n"]
        for r in results:
            for label, ff in (("PRODUCTION (baseline)", r["production"] or {}), (version, r["output"] or {})):
                md.append(f"\n---\n\n## {r['lecture_id'][:8]} — {label}\n\n**{ff.get('title')}**\n\n"
                          f"HOOK: {ff.get('hook')}\n\nBODY:\n\n{ff.get('body')}\n")
        (out_dir / "side_by_side.md").write_text("\n".join(md), encoding="utf-8")

    print(f"=== {mode} {version} | {len(results)} lectures | wall {wall}s | cost ${cost} ===")
    for r in results:
        c = r["calls"][0] if r["calls"] else {}
        print(r["lecture_id"][:8], "error=", r["error"],
              {k: c.get(k) for k in ("elapsed_seconds", "input_tokens", "output_tokens", "finish_reason", "cost_usd",
                                     "system_chars", "user_chars")})
        if r.get("stats"):
            print("   stats:", r["stats"])
    if results and results[0]["calls"]:
        print("options:", results[0]["calls"][0]["request_kwargs"])
    print("saved:", out_dir)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["prepare", "dryrun", "run"])
    ap.add_argument("--prompt-version", default="v1")
    a = ap.parse_args()
    if a.mode == "prepare":
        prepare()
    else:
        asyncio.run(run(a.mode, a.prompt_version))


if __name__ == "__main__":
    main()
