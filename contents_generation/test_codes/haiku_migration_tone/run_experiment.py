"""
Haiku 5.5 移行実験 (Review Cards / Deep Notes / Fun Facts)

目的: gemini-2.5-flash の廃止に伴い、3タスクを anthropic/claude-haiku-5-5 に置き換えたとき
「読みやすさ・口調」が保てるかを確認し、プロンプトを調整していく。

本番との差分は次の3点だけ(それ以外は本番の Service クラス・プロンプト組み立て・入力データをそのまま使う):
  1. model:            gemini/gemini-2.5-flash  ->  anthropic/claude-haiku-5-5
  2. reasoning_effort: (なし)                   ->  "low"  (llm_unified が thinking: adaptive を付与)
  3. max_tokens:       (なし)                   ->  MAX_TOKENS (思考トークン込み。途中切れ防止で高め)
  + --prompt-version で prompts/<ver>/ のプロンプトを差し込める (v0 = 本番プロンプトそのもの)

安全策:
  - R2 の pipeline_cache は読み込みも書き込みも無効化する
    (読めば本番の Gemini 出力が返ってきてしまい、書けば本番キャッシュを汚すため)。
  - Supabase / R2 への書き込みは一切しない(読み取りのみ)。

使い方:
  .venv/bin/python contents_generation/test_codes/haiku_migration_tone/run_experiment.py prepare
  .venv/bin/python contents_generation/test_codes/haiku_migration_tone/run_experiment.py dryrun --prompt-version v0
  .venv/bin/python contents_generation/test_codes/haiku_migration_tone/run_experiment.py run --prompt-version v0
"""

import argparse
import asyncio
import dataclasses
import json
import re
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
from app.services.logic import fun_fact_generation as ff_mod  # noqa: E402
from app.services.logic import review_card_generation as rc_mod  # noqa: E402
from app.services.logic import topic_details_generation as dn_mod  # noqa: E402
from app.services import task_runners as TR  # noqa: E402

MODEL = "anthropic/claude-haiku-5-5"
REASONING_EFFORT = "low"
MAX_TOKENS = 32000

INPUTS_DIR = EXP_DIR / "inputs"
RESULTS_DIR = EXP_DIR / "results"
PROMPTS_DIR = EXP_DIR / "prompts"

DEFAULT_LECTURES = [
    "a028aad6-07ba-4e3f-ac39-7494e9d7f062",  # en->ja アセンブリ命令とレジスタ演算の基礎
    "666b2c9d-a997-451b-9318-98f98c9d29fa",  # en->ja 関数型プログラミングとHaskellの基礎
    "ed333ded-2e09-464a-8224-11b7517fb709",  # en->ja 論理結合子の記号化と真理値表
    "bafdf3c0-6200-4737-a1f7-5f940568d608",  # en->ja 即興スピーチと口頭引用の実践 (非STEM)
    "de2d74b0-36ad-4680-95bb-3fc2676697a8",  # ja->ja クイア視点から捉える性・文化・権力
    "737f0678-19cb-4b23-a0d3-b247ee9f6fa0",  # en->en Context, Design, and User-Centered Interaction
]
TASKS = ["review_cards", "deep_notes", "fun_facts"]

# ---------------------------------------------------------------------------
# プロンプト版ごとの「コード側の変更」(本番では Service 側に入れる予定のもの)を再現する
#   rc_keywords:      ${CURRENT_TOPIC_KEYWORDS} に今のトピックのキーワードを埋める
#   rc_lang_reminder: user メッセージ末尾に出力言語を再掲 (probe_language_drift で効果確認済み)
#   rc_json_schema:   json_schema で構造化出力 (Anthropic native structured output) を強制する
# ---------------------------------------------------------------------------
VERSION_PATCHES: Dict[str, Dict[str, bool]] = {
    "v0": {},
    "v1": {"rc_keywords": True, "rc_lang_reminder": True, "rc_json_schema": True},
    # v1b: v1 と同じプロンプト・コード変更だが json_schema なし (v1 で空ブロック・カード欠落が出たための切り分け)
    "v1b": {"rc_keywords": True, "rc_lang_reminder": True},
    # v1c: v1 と同じだが、ブロック種別ごとに必須フィールドを持つ厳密スキーマ (anyOf)
    "v1c": {"rc_keywords": True, "rc_lang_reminder": True, "rc_json_schema_strict": True},
    "v2": {"rc_keywords": True, "rc_lang_reminder": True, "rc_json_schema_strict": True},
}
VERSION_PROMPT_DIR = {"v1b": "v1", "v1c": "v1"}

_STR = {"type": "string"}
REVIEW_CARD_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "required": ["topic_evaluation", "review_cards"],
    "properties": {
        "topic_evaluation": {
            "type": "object",
            "additionalProperties": False,
            "required": ["micro_topics", "card_mapping_strategy", "core_concept_identified"],
            "properties": {
                "micro_topics": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "additionalProperties": False,
                        "required": ["idx", "title", "summary", "start_sid", "end_sid"],
                        "properties": {"idx": {"type": "integer"}, "title": _STR, "summary": _STR,
                                       "start_sid": _STR, "end_sid": _STR},
                    },
                },
                "card_mapping_strategy": _STR,
                "core_concept_identified": _STR,
            },
        },
        "review_cards": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["card_type", "hero_emoji", "title", "content_blocks"],
                "properties": {
                    "card_type": {"type": "string", "enum": ["hook", "core_why", "gotcha", "next_action"]},
                    "hero_emoji": _STR,
                    "title": _STR,
                    "content_blocks": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["type"],
                            "properties": {
                                "type": {"type": "string", "enum": ["paragraph", "quote", "callout", "code", "list"]},
                                "text": _STR,
                                "alert_type": {"type": "string", "enum": ["info", "warning", "error"]},
                                "code_string": _STR,
                                "language": _STR,
                                "explanation": _STR,
                                "items": {"type": "array", "items": _STR},
                            },
                        },
                    },
                },
            },
        },
    },
}
def _block(type_name: str, required: List[str], props: Dict[str, Any]) -> Dict[str, Any]:
    return {"type": "object", "additionalProperties": False, "required": ["type"] + required,
            "properties": {"type": {"type": "string", "enum": [type_name]}, **props}}


REVIEW_CARD_SCHEMA_STRICT: Dict[str, Any] = json.loads(json.dumps(REVIEW_CARD_SCHEMA))
REVIEW_CARD_SCHEMA_STRICT["properties"]["review_cards"]["items"]["properties"]["content_blocks"]["items"] = {
    "anyOf": [
        _block("paragraph", ["text"], {"text": _STR}),
        _block("quote", ["text"], {"text": _STR}),
        _block("callout", ["alert_type", "text"],
               {"alert_type": {"type": "string", "enum": ["info", "warning", "error"]}, "text": _STR}),
        _block("code", ["code_string"], {"code_string": _STR, "language": _STR, "explanation": _STR}),
        _block("list", ["items"], {"items": {"type": "array", "items": _STR}}),
    ]
}
RC_TOPIC_RE = re.compile(r"Generate Review Cards for Topic: (.*)$", re.S)


# ---------------------------------------------------------------------------
# 本番 R2 キャッシュの無効化 (読み書き両方)
# ---------------------------------------------------------------------------
def _disable_r2_cache() -> None:
    storage_service.load_json_cache = lambda path: None  # type: ignore[assignment]
    storage_service.save_json_cache = lambda path, data: f"(experiment: not saved) {path}"  # type: ignore[assignment]


# ---------------------------------------------------------------------------
# プロンプト差し込み: prompts/<ver>/ にファイルがあればそれを、無ければ本番プロンプトを使う
# ---------------------------------------------------------------------------
def _install_prompt_loader(version: str) -> Dict[str, str]:
    used: Dict[str, str] = {}
    original_loader = H._load_prompt

    prompt_dir = VERSION_PROMPT_DIR.get(version, version)

    def loader(filename: str) -> str:
        override = PROMPTS_DIR / prompt_dir / filename
        if override.exists():
            used[filename] = str(override.relative_to(EXP_DIR))
            return override.read_text(encoding="utf-8")
        used[filename] = "production"
        return original_loader(filename)

    for mod in (rc_mod, dn_mod, ff_mod):
        mod._load_prompt = loader  # type: ignore[attr-defined]
    return used


# ---------------------------------------------------------------------------
# LLM ラッパー: モデルとオプション(思考・max_tokens)だけ差し替え、各呼び出しを記録する
# ---------------------------------------------------------------------------
class ExperimentLLM(UnifiedLLM):
    def __init__(self, billing: BillingEngine, task: str, lecture_id: str, dry_run: bool,
                 inp: Optional[Dict[str, Any]] = None, patches: Optional[Dict[str, bool]] = None):
        super().__init__(billing)
        self.task = task
        self.lecture_id = lecture_id
        self.dry_run = dry_run
        self.inp = inp or {}
        self.patches = patches or {}
        self.calls: List[Dict[str, Any]] = []
        # --only: 指定したトピックだけ API を呼び、それ以外は呼ばずにスタブを返す。
        # プロンプトは全トピック分を本番通りに組み立てるので、最初/最後のトピック判定などは本番と同じになる。
        self.only: Optional[set] = None
        self.skipped_topics: set = set()

    def _topic_key(self, messages) -> str:
        user_text = messages[1].content
        if self.task == "review_cards":
            title = RC_TOPIC_RE.search(user_text).group(1).strip()
            return str(next(t["idx"] for t in self.inp["core_extraction"]["topics"] if t.get("title") == title))
        if self.task == "deep_notes":
            seg = user_text.split("Topic segment:\n", 1)[1].split("\n\nPartial transcript", 1)[0]
            return str(json.loads(seg)["idx"])
        return "ff"

    def _apply_patches(self, messages, options):
        if self.task != "review_cards":
            return messages, options
        p = self.patches
        sys_text, user_text = messages[0].content, messages[1].content
        if p.get("rc_keywords"):
            title = RC_TOPIC_RE.search(user_text).group(1).strip()
            topic = next(t for t in self.inp["core_extraction"]["topics"] if t.get("title") == title)
            kws = rc_mod._keyword_strings(topic)
            sys_text = sys_text.replace("${CURRENT_TOPIC_KEYWORDS}", "\n".join(f"- {k}" for k in kws) or "N/A")
        if p.get("rc_lang_reminder"):
            lang = self.inp["language"]["content_language"]
            user_text += f"\n\nWrite every card title and every text field in {lang}."
        if p.get("rc_json_schema"):
            options = dataclasses.replace(options, json_schema=REVIEW_CARD_SCHEMA)
        if p.get("rc_json_schema_strict"):
            options = dataclasses.replace(options, json_schema=REVIEW_CARD_SCHEMA_STRICT)
        messages = [dataclasses.replace(messages[0], content=sys_text),
                    dataclasses.replace(messages[1], content=user_text)] + list(messages[2:])
        return messages, options

    async def generate(self, model, messages, options=None):  # type: ignore[override]
        if self.only is not None:
            key = self._topic_key(messages)
            if key not in self.only:
                self.skipped_topics.add(key)
                return _mock_result(self.task, options.output_type)
        options = dataclasses.replace(options, reasoning_effort=REASONING_EFFORT, max_tokens=MAX_TOKENS)
        messages, options = self._apply_patches(messages, options)
        kwargs = self._build_kwargs(MODEL, messages, options)
        record: Dict[str, Any] = {
            "task": self.task,
            "lecture_id": self.lecture_id,
            "original_model": model,
            "model": MODEL,
            "request_kwargs": {k: v for k, v in kwargs.items() if k != "messages"},
            "system_chars": len(messages[0].content) if messages else 0,
            "user_chars": sum(len(m.content) for m in messages[1:]),
        }
        if self.dry_run:
            record["messages"] = [{"role": m.role, "content": m.content} for m in messages]
            self.calls.append(record)
            return _mock_result(self.task, options.output_type)

        t0 = time.perf_counter()
        res: LLMResult = await super().generate(MODEL, messages, options)
        record.update(
            elapsed_seconds=round(time.perf_counter() - t0, 2),
            input_tokens=res.input_tokens,
            output_tokens=res.output_tokens,
            cache_read_tokens=res.cache_read_tokens,
            cache_write_tokens=res.cache_write_tokens,
            finish_reason=res.finish_reason,
            json_parse_error=res.json_parse_error,
            output_text=res.output_text,
            cost_usd=self.billing.records[-2].cost_usd if len(self.billing.records) >= 2 else None,
        )
        self.calls.append(record)
        return res


def _mock_result(task: str, output_type: str) -> LLMResult:
    if task == "review_cards":
        cards = [{"card_type": t, "hero_emoji": "🧪", "title": "dry", "content_blocks": []}
                 for t in ("hook", "core_why", "gotcha", "next_action")]
        j = {"topic_evaluation": {}, "review_cards": cards}
        return LLMResult(output_text=json.dumps(j), output_json=j, model_used="mock")
    if task == "fun_facts":
        j = {"title": "dry", "hook": "dry", "body": "dry"}
        return LLMResult(output_text=json.dumps(j), output_json=j, model_used="mock")
    return LLMResult(output_text="# dry", output_json=None, model_used="mock")


# ---------------------------------------------------------------------------
# prepare: 本番パイプラインと同じ入力を R2 / Supabase から取得してローカルに保存 (読み取りのみ)
# ---------------------------------------------------------------------------
def prepare(lecture_ids: List[str]) -> None:
    sb = get_supabase_client()
    INPUTS_DIR.mkdir(exist_ok=True)
    for lid in lecture_ids:
        lec = sb.table("lectures").select(
            "id,user_id,title,title_generated,recording_language,display_language,detected_recording_language"
        ).eq("id", lid).single().execute().data
        job = sb.table("processing_jobs").select("id,status,created_at").eq("lecture_id", lid)\
            .eq("status", "COMPLETED").order("created_at", desc=True).limit(1).execute().data[0]
        job_id = job["id"]

        def payload(task_type: str) -> dict:
            return TR._get_dependency_payload_sync(job_id, task_type)

        role = TR._download_from_r2_to_memory_sync(payload("ROLE_CLASSIFICATION")["role_classification_path"])
        core = TR._download_from_r2_to_memory_sync(payload("CORE_EXTRACTION")["core_extraction_path"])
        bp = payload("FUN_FACT_BRAINSTORMING").get("fun_fact_brainstorming_path")
        seed = TR._download_from_r2_to_memory_sync(bp) if bp else {}
        sp = payload("FUN_FACT_SEARCH").get("search_results_path")
        search = TR._download_from_r2_to_memory_sync(sp) if sp else []

        content_language, transcript_language, is_bilingual = H._get_content_language_context(lid)
        student_profile = H._get_student_profile(lec["user_id"])

        # 参考用: 既存の Gemini 出力 (DB)
        ref_rc = sb.table("review_cards").select("topic_number,card_type,title,hero_emoji,card_content,created_at")\
            .eq("lecture_id", lid).is_("deleted_at", "null").order("topic_number").order("created_at").execute().data
        ref_dn = sb.table("deep_notes").select("topic_number,note_contents,created_at")\
            .eq("lecture_id", lid).is_("deleted_at", "null").order("topic_number").execute().data
        ref_ff = sb.table("fun_facts").select("title,hook,body,metadata,created_at")\
            .eq("lecture_id", lid).is_("deleted_at", "null").execute().data

        data = {
            "lecture": lec,
            "job_id": job_id,
            "language": {
                "content_language": content_language,
                "transcript_language": transcript_language,
                "is_bilingual": is_bilingual,
            },
            "student_profile": student_profile,
            "role_classification": role,
            "core_extraction": core,
            "fun_fact_seed": seed,
            "fun_fact_search": search,
            "gemini_reference": {"review_cards": ref_rc, "deep_notes": ref_dn, "fun_facts": ref_ff},
        }
        (INPUTS_DIR / f"{lid}.json").write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
        academic = [t for t in core.get("topics", []) if t.get("topic_type") == "ACADEMIC"]
        print(f"✅ {lid[:8]} {(lec['title'] or lec['title_generated'] or '')[:30]} | "
              f"{transcript_language}->{content_language} bilingual={is_bilingual} | "
              f"sentences={len(role)} academic_topics={len(academic)} seed={'yes' if seed else 'no'} "
              f"search={len(search)} | ref rc={len(ref_rc)} dn={len(ref_dn)} ff={len(ref_ff)}")


# ---------------------------------------------------------------------------
# 1講義 × 1タスクの実行 (本番の task_runners と同じ引数で Service を呼ぶ)
# ---------------------------------------------------------------------------
async def run_one(task: str, inp: Dict[str, Any], dry_run: bool, patches: Dict[str, bool],
                  only: Optional[set] = None) -> Dict[str, Any]:
    lec = inp["lecture"]
    lid, uid = lec["id"], lec["user_id"]
    lang = inp["language"]
    billing = BillingEngine(task_type=task.upper())
    llm = ExperimentLLM(billing, task, lid, dry_run, inp=inp, patches=patches)
    llm.only = only
    logger = H.TaskLogger(uid, lid, f"EXP:{task}:{lid[:8]}")
    t0 = time.perf_counter()
    output: Any = None
    error: Optional[str] = None
    try:
        if task == "review_cards":
            svc = rc_mod.ReviewCardGenerationService(llm, logger)
            svc.model_alias = MODEL
            output = await svc.run_from_memory(
                role_classified_data=inp["role_classification"], core_data=inp["core_extraction"],
                uid=uid, lecture_id=lid, content_language=lang["content_language"],
                transcript_language=lang["transcript_language"], is_bilingual=lang["is_bilingual"],
            )
        elif task == "deep_notes":
            # NOTE: 本番は Free プランだと最初の ACADEMIC トピックだけに絞るが、
            # 評価のため全トピックを生成する(1トピックあたりの生成条件は本番と同一)。
            svc = dn_mod.TopicDetailGenerationService(llm, logger)
            svc.model_alias = MODEL
            output = await svc.run_from_memory(
                inp["role_classification"], inp["core_extraction"], uid=uid, lecture_id=lid,
                content_language=lang["content_language"], transcript_language=lang["transcript_language"],
                is_bilingual=lang["is_bilingual"],
            )
        elif task == "fun_facts":
            svc = ff_mod.FunFactGenerationService(llm, logger)
            svc.model_alias = MODEL
            output = await svc.run_from_memory(
                core_data=inp["core_extraction"], seed_data=inp["fun_fact_seed"],
                search_results=inp["fun_fact_search"], student_profile=inp["student_profile"],
                content_language=lang["content_language"],
            )
    except Exception as e:  # 失敗も結果として記録する
        error = f"{type(e).__name__}: {e}"
    # --only で呼ばなかったトピックのスタブ出力は結果から除く
    if llm.skipped_topics and isinstance(output, list):
        output = [o for o in output if str(o.get("topic_idx")) not in llm.skipped_topics]
    return {
        "task": task,
        "lecture_id": lid,
        "language": lang,
        "wall_seconds": round(time.perf_counter() - t0, 2),
        "cost_usd": round(billing.total_usd(), 6),
        "token_cost_usd": round(sum(r.cost_usd for r in billing.records if r.dimension == "tokens"), 6),
        "error": error,
        "output": output,
        "calls": llm.calls,
    }


# ---------------------------------------------------------------------------
# 自動チェック (数値の記録のみ。良し悪しの判断はしない)
# ---------------------------------------------------------------------------
CITE_RE = re.compile(r"⟦[^⟧]*⟧")
BAD_CITE_RE = re.compile(r"(?<!⟦)\[\[s\d|〚|\[s\d{6}\]")
PAREN_GLOSS_RE = re.compile(r"[（(]\s*[A-Za-z][A-Za-z0-9 .,'/&+\-]{1,60}[)）]")


def _texts_of(task: str, output: Any) -> List[str]:
    if output is None:
        return []
    if task == "review_cards":
        out = []
        for topic in output:
            for card in topic.get("review_cards", []):
                out.append(card.get("title") or "")
                for b in card.get("content_blocks", []):
                    out += [b.get("text") or "", b.get("explanation") or ""] + list(b.get("items") or [])
        return out
    if task == "deep_notes":
        return [d.get("content") or "" for d in output]
    if task == "fun_facts":
        return [output.get("title", ""), output.get("hook", ""), output.get("body", "")]
    return []


def check(result: Dict[str, Any]) -> Dict[str, Any]:
    task, output = result["task"], result["output"]
    text = "\n".join(_texts_of(task, output))
    calls = result["calls"]
    c: Dict[str, Any] = {
        "calls": len(calls),
        "error": result["error"],
        "finish_reasons": sorted({str(x.get("finish_reason")) for x in calls}),
        "truncated_calls": sum(1 for x in calls if x.get("finish_reason") == "length"),
        "json_parse_errors": sum(1 for x in calls if x.get("json_parse_error")),
        "chars": len(text),
        "exclamations": text.count("！") + text.count("!"),
        "question_marks": text.count("？") + text.count("?"),
        "citations": len(CITE_RE.findall(text)),
        "malformed_citations": len(BAD_CITE_RE.findall(text)),
        "placeholder_leak": text.count("<original") + text.count("original English term") + text.count("<term"),
        "english_gloss_parens": len(PAREN_GLOSS_RE.findall(text)),
        "input_tokens": sum(x.get("input_tokens") or 0 for x in calls),
        "output_tokens": sum(x.get("output_tokens") or 0 for x in calls),
        "max_output_tokens_single_call": max([x.get("output_tokens") or 0 for x in calls] or [0]),
        "sum_call_seconds": round(sum(x.get("elapsed_seconds") or 0 for x in calls), 1),
        "max_call_seconds": max([x.get("elapsed_seconds") or 0 for x in calls] or [0]),
    }
    if task == "review_cards" and output:
        seqs = [[cd.get("card_type") for cd in t.get("review_cards", [])] for t in output]
        c["topics"] = len(output)
        c["topics_with_bad_card_sequence"] = sum(
            1 for s in seqs if s and s != ["hook", "core_why", "gotcha", "next_action"]
        )
    if task == "fun_facts" and isinstance(output, dict):
        c["fun_fact_sources"] = len(output.get("sources") or [])
    return c


# ---------------------------------------------------------------------------
async def run_all(mode: str, version: str, lecture_ids: List[str], tasks: List[str], concurrency: int,
                  only: Optional[List[str]] = None) -> Path:
    """only: ["review_cards:a028aad6:2", "deep_notes:666b2c9d:4", "fun_facts:ed333ded"] の形式。"""
    dry = mode == "dryrun"
    _disable_r2_cache()
    used_prompts = _install_prompt_loader(version)
    patches = VERSION_PATCHES.get(version, {})
    inputs = {lid: json.loads((INPUTS_DIR / f"{lid}.json").read_text(encoding="utf-8")) for lid in lecture_ids}

    # (task, lecture) -> 呼ぶトピックの集合。only 指定時は、そこに含まれる組み合わせだけ走らせる。
    plan: Dict[tuple, Optional[set]] = {}
    if only:
        for spec in only:
            parts = spec.split(":")
            task, prefix = parts[0], parts[1]
            lid = next(l for l in lecture_ids if l.startswith(prefix))
            plan.setdefault((task, lid), set()).add(parts[2] if len(parts) > 2 else "ff")
    else:
        plan = {(t, lid): None for lid in lecture_ids for t in tasks}

    sem = asyncio.Semaphore(concurrency)

    async def guarded(task: str, lid: str, topics: Optional[set]):
        async with sem:
            return await run_one(task, inputs[lid], dry, patches, topics)

    t0 = time.perf_counter()
    results = await asyncio.gather(*(guarded(t, lid, topics) for (t, lid), topics in plan.items()))
    lecture_ids = sorted({lid for (_, lid) in plan}, key=lecture_ids.index)
    tasks = sorted({t for (t, _) in plan}, key=TASKS.index)
    wall = round(time.perf_counter() - t0, 1)

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = RESULTS_DIR / f"{ts}_{mode}_{version}"
    out_dir.mkdir(parents=True, exist_ok=True)

    rows = []
    for r in results:
        r["checks"] = check(r)
        rows.append({"task": r["task"], "lecture_id": r["lecture_id"][:8], **r["checks"],
                     "token_cost_usd": r["token_cost_usd"], "wall_seconds": r["wall_seconds"]})

    total_cost = round(sum(r["token_cost_usd"] for r in results), 4)
    meta = {
        "mode": mode, "prompt_version": version, "model": MODEL,
        "reasoning_effort": REASONING_EFFORT, "max_tokens": MAX_TOKENS,
        "prompts_used": used_prompts, "code_patches": patches, "lectures": lecture_ids, "tasks": tasks,
        "wall_seconds_total": wall, "token_cost_usd_total": total_cost,
        "created_at": ts,
    }
    (out_dir / "raw.json").write_text(json.dumps({"meta": meta, "results": results}, ensure_ascii=False, indent=1),
                                      encoding="utf-8")
    (out_dir / "summary.json").write_text(json.dumps({"meta": meta, "rows": rows}, ensure_ascii=False, indent=1),
                                          encoding="utf-8")

    print(f"\n=== {mode} {version} | {len(results)} runs | wall {wall}s | token cost ${total_cost} ===")
    keys = ["task", "lecture_id", "calls", "error", "truncated_calls", "json_parse_errors", "chars",
            "exclamations", "citations", "placeholder_leak", "input_tokens", "output_tokens",
            "max_call_seconds", "token_cost_usd"]
    print("\t".join(keys))
    for row in rows:
        print("\t".join(str(row.get(k, ""))[:40] for k in keys))
    print(f"\nprompts used: {used_prompts}")
    print(f"saved: {out_dir}")
    return out_dir


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["prepare", "dryrun", "run"])
    ap.add_argument("--prompt-version", default="v0")
    ap.add_argument("--lectures", nargs="*", default=DEFAULT_LECTURES)
    ap.add_argument("--tasks", nargs="*", default=TASKS, choices=TASKS)
    ap.add_argument("--concurrency", type=int, default=6)
    ap.add_argument("--only", nargs="*", default=None,
                    help='e.g. review_cards:a028aad6:2 deep_notes:666b2c9d:4 fun_facts:ed333ded')
    a = ap.parse_args()
    if a.mode == "prepare":
        prepare(a.lectures)
    else:
        asyncio.run(run_all(a.mode, a.prompt_version, a.lectures, a.tasks, a.concurrency, a.only))


if __name__ == "__main__":
    main()
