"""
Deep Notes readability experiment (Haiku 5.5)

Question: does removing "Keep sentences short and break a long sentence into two" and adding a
"Connected Reasoning" rule make Deep Notes read less choppy (sentences that connect to each other)?

Baseline = the production Deep Notes already in Supabase (production already runs Haiku 5.5 with
reasoning_effort=low, max_tokens=32000), so only the new prompt is generated here.

Everything except the prompt file is the production code path:
  - app.services.logic.topic_details_generation.TopicDetailGenerationService.run_from_memory
  - inputs (role_classification / core_extraction) downloaded from R2 for the lecture's completed job
Safety: R2 pipeline_cache reads and writes are disabled; no writes to Supabase or R2.

Usage (from repo root):
  .venv/bin/python contents_generation/test_codes/deepnote_readability/run.py prepare
  .venv/bin/python contents_generation/test_codes/deepnote_readability/run.py dryrun --topics 1 3
  .venv/bin/python contents_generation/test_codes/deepnote_readability/run.py run --topics 1 3
"""

import argparse
import asyncio
import dataclasses
import json
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

EXP_DIR = Path(__file__).resolve().parent
REPO_ROOT = EXP_DIR.parents[2]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv  # noqa: E402

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

from app.core.r2_storage import storage_service  # noqa: E402
from app.core.supabase import get_supabase_client  # noqa: E402
from app.services.helpers import helpers as H  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, LLMResult, UnifiedLLM  # noqa: E402
from app.services.logic import topic_details_generation as dn_mod  # noqa: E402
from app.services import task_runners as TR  # noqa: E402

LECTURE_ID = "4ff6ef52-5b48-4eab-82fa-662da2c7de09"  # DNS、NAT、鍵共有とネットワークループ (2026-11-06)
PROMPT_FILE = "topic_details_generation_prompt.txt"
INPUTS_DIR = EXP_DIR / "inputs"
RESULTS_DIR = EXP_DIR / "results"
PROMPTS_DIR = EXP_DIR / "prompts"


def prepare() -> None:
    sb = get_supabase_client()
    INPUTS_DIR.mkdir(exist_ok=True)
    lec = sb.table("lectures").select("id,user_id,title,title_generated").eq("id", LECTURE_ID).single().execute().data
    job = sb.table("processing_jobs").select("id,status,created_at").eq("lecture_id", LECTURE_ID) \
        .eq("status", "COMPLETED").order("created_at", desc=True).limit(1).execute().data[0]
    payload = lambda t: TR._get_dependency_payload_sync(job["id"], t)  # noqa: E731
    role = TR._download_from_r2_to_memory_sync(payload("ROLE_CLASSIFICATION")["role_classification_path"])
    core = TR._download_from_r2_to_memory_sync(payload("CORE_EXTRACTION")["core_extraction_path"])
    content_language, transcript_language, is_bilingual = H._get_content_language_context(LECTURE_ID)
    baseline = sb.table("deep_notes").select("topic_number,note_contents,created_at") \
        .eq("lecture_id", LECTURE_ID).is_("deleted_at", "null").order("topic_number").execute().data
    data = {
        "lecture": lec, "job_id": job["id"],
        "language": {"content_language": content_language, "transcript_language": transcript_language,
                     "is_bilingual": is_bilingual},
        "role_classification": role, "core_extraction": core, "production_deep_notes": baseline,
    }
    (INPUTS_DIR / f"{LECTURE_ID}.json").write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    for t in core.get("topics", []):
        print(f"topic idx={t.get('idx')} type={t.get('topic_type')} {t.get('start_sid')}-{t.get('end_sid')} {t.get('title')}")
    print(f"lang {transcript_language}->{content_language} bilingual={is_bilingual} | sentences={len(role)} "
          f"| baseline notes={[b['topic_number'] for b in baseline]}")


class ExperimentLLM(UnifiedLLM):
    """Calls the API only for the chosen topics; records each call. Model/options are production's."""

    def __init__(self, billing: BillingEngine, dry_run: bool, only: set):
        super().__init__(billing)
        self.dry_run, self.only = dry_run, only
        self.calls: List[Dict[str, Any]] = []

    async def generate(self, model, messages, options=None):  # type: ignore[override]
        seg = messages[1].content.split("Topic segment:\n", 1)[1].split("\n\nPartial transcript", 1)[0]
        idx = str(json.loads(seg)["idx"])
        if idx not in self.only:
            return LLMResult(output_text="# skipped", output_json=None, model_used="mock")
        kwargs = self._build_kwargs(model, messages, options)
        rec: Dict[str, Any] = {"topic_idx": idx, "model": model,
                               "request_kwargs": {k: v for k, v in kwargs.items() if k != "messages"},
                               "system_chars": len(messages[0].content), "user_chars": len(messages[1].content)}
        if self.dry_run:
            rec["messages"] = [{"role": m.role, "content": m.content} for m in messages]
            self.calls.append(rec)
            return LLMResult(output_text="# dry", output_json=None, model_used="mock")
        n_before = len(self.billing.records)
        t0 = time.perf_counter()
        res = await super().generate(model, messages, options)
        rec.update(elapsed_seconds=round(time.perf_counter() - t0, 2), input_tokens=res.input_tokens,
                   output_tokens=res.output_tokens, finish_reason=res.finish_reason,
                   cost_usd=round(sum(r.cost_usd for r in self.billing.records[n_before:]
                                      if r.dimension == "tokens"), 6),
                   output_text=res.output_text)
        self.calls.append(rec)
        return res


async def run(mode: str, version: str, topics: List[str]) -> None:
    dry = mode == "dryrun"
    storage_service.load_json_cache = lambda path: None  # type: ignore[assignment]
    storage_service.save_json_cache = lambda path, data: "(experiment: not saved)"  # type: ignore[assignment]
    prompt_path = PROMPTS_DIR / version / PROMPT_FILE
    original_loader = H._load_prompt
    dn_mod._load_prompt = lambda f: prompt_path.read_text(encoding="utf-8") if f == PROMPT_FILE else original_loader(f)  # type: ignore

    inp = json.loads((INPUTS_DIR / f"{LECTURE_ID}.json").read_text(encoding="utf-8"))
    lang = inp["language"]
    billing = BillingEngine(task_type="DEEP_NOTES")
    llm = ExperimentLLM(billing, dry, set(topics))
    svc = dn_mod.TopicDetailGenerationService(llm, H.TaskLogger(inp["lecture"]["user_id"], LECTURE_ID, "EXP:deepnote_readability"))
    t0 = time.perf_counter()
    # Production passes use_prompt_cache=True for multi-topic plans; with 1 call per topic here it only adds
    # a cache write, so it is left off (it does not change the generated text).
    out = await svc.run_from_memory(inp["role_classification"], inp["core_extraction"], uid=inp["lecture"]["user_id"],
                                    lecture_id=LECTURE_ID, content_language=lang["content_language"],
                                    transcript_language=lang["transcript_language"], is_bilingual=lang["is_bilingual"])
    wall = round(time.perf_counter() - t0, 1)
    baseline = {str(b["topic_number"]): b["note_contents"] for b in inp["production_deep_notes"]}
    notes = {str(o["topic_idx"]): o["content"] for o in out if str(o["topic_idx"]) in set(topics)}

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = RESULTS_DIR / f"{ts}_{mode}_{version}"
    out_dir.mkdir(parents=True, exist_ok=True)
    cost = round(sum(c.get("cost_usd") or 0 for c in llm.calls), 6)
    meta = {"mode": mode, "prompt_version": version, "prompt_path": str(prompt_path.relative_to(EXP_DIR)),
            "lecture_id": LECTURE_ID, "topics": topics, "wall_seconds": wall, "token_cost_usd": cost}
    (out_dir / "raw.json").write_text(json.dumps({"meta": meta, "calls": llm.calls, "notes": notes},
                                                 ensure_ascii=False, indent=1), encoding="utf-8")
    if not dry:
        md = [f"# Deep Notes readability — {version} vs production\n", f"```\n{json.dumps(meta, ensure_ascii=False, indent=1)}\n```\n"]
        for t in topics:
            md += [f"\n---\n\n# Topic {t} — PRODUCTION (baseline)\n\n{baseline.get(t, '(none)')}\n",
                   f"\n---\n\n# Topic {t} — {version}\n\n{notes.get(t, '(none)')}\n"]
        (out_dir / "side_by_side.md").write_text("\n".join(md), encoding="utf-8")

    print(f"=== {mode} {version} topics={topics} wall={wall}s cost=${cost} ===")
    for c in llm.calls:
        print({k: c.get(k) for k in ("topic_idx", "model", "elapsed_seconds", "input_tokens", "output_tokens",
                                       "finish_reason", "cost_usd", "system_chars", "user_chars")})
        print("   options:", c["request_kwargs"])
    print("saved:", out_dir)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["prepare", "dryrun", "run"])
    ap.add_argument("--prompt-version", default="v1")
    ap.add_argument("--topics", nargs="*", default=["1", "3"])
    a = ap.parse_args()
    if a.mode == "prepare":
        prepare()
    else:
        asyncio.run(run(a.mode, a.prompt_version, a.topics))


if __name__ == "__main__":
    main()
