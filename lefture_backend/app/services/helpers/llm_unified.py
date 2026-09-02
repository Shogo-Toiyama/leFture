# app/services/helpers/llm_unified.py
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Literal
import json
import time
import warnings
import litellm

# LiteLLMの設定：
# プロバイダーがサポートしていないパラメータが送られても、
# エラーで落とさず自動で無視します。
litellm.drop_params = True

# =========================================================
# 💰 価格マトリックス
# =========================================================
PRICE_MATRIX = {
    "tokens": {  # $ per 1,000,000 tokens
        "groq/openai/gpt-oss-120b": {"input": 0.15, "output": 0.60},
        "groq/openai/gpt-oss-20b": {"input": 0.075, "output": 0.30},
        "together_ai/openai/gpt-oss-120b": {"input": 0.15, "output": 0.60},
        # WARNING: Prism-ML/Ternary-Bonsai-27B は現在 Together AI 上で無料/プレビュー枠の可能性がありますが、
        # 将来の有料化・価格改定を見越して安全側に倒し、gpt-oss-20b と同額 ($0.05 / $0.20) に暫定設定しています。
        "together_ai/Prism-ML/Ternary-Bonsai-27B": {"input": 0.05, "output": 0.20},
        "together_ai/openai/gpt-oss-20b": {"input": 0.05, "output": 0.20},
        "deepinfra/openai/gpt-oss-120b": {"input": 0.039, "output": 0.19},
        "deepinfra/deepseek-ai/DeepSeek-V3.2": {"input": 0.26, "output": 0.38},
        "gemini/gemini-2.5-flash-lite": {"input": 0.10, "output": 0.40},
        "gemini/gemini-2.5-flash": {"input": 0.30, "output": 2.50},
        "gemini/gemini-3.1-flash-lite": {"input": 0.40, "output": 1.50},
    },
    "time": {  # $ per unit per second
        "modal/cpu": 0.0000131,     # per core-second
        "modal/t4": 0.000164,       # per GPU-second
        "modal/l4": 0.000222,       # per GPU-second
        "cloudrun/self": 0.000030,  # 概算用。実際より少し高めに見積もる
        "cloudflare/whisper-large-v3-turbo": 0.00000833,
        "groq/whisper-large-v3-turbo": 0.00001111,
    },
    "image": {
        # Cloudflare Workers AI FLUX.1 [schnell]
        # 料金は tile と step の合算で概算する
        # per 512x512 tile / per step
        "cloudflare/flux-1-schnell": {
            "per_tile": 0.0000528,
            "per_step": 0.0001056,
            "default_steps": 4,
        },
        "cloudflare/flux-2-klein-4b": {
            "per_tile": 0.000287,
            "per_step": 0.0,
            "default_steps": 4,
        }
    },
    "count": {  # $ per unit
        "brave/llm_context": 0.005,
    }
}

# =========================================================
# ⚠️ 警告ヘルパー
# =========================================================
def warn_unknown_price(dimension: str, resource: str) -> None:
    warnings.warn(
        f"[BillingEngine] Unknown price key for dimension='{dimension}', resource='{resource}'. "
        f"Cost was recorded as $0.0 without stopping execution.",
        RuntimeWarning,
        stacklevel=2,
    )


# =========================================================
# 📈 コスト記録
# =========================================================
@dataclass
class CostRecord:
    dimension: Literal["tokens", "time", "count", "image"]
    resource: str
    usage: Dict[str, float]
    cost_usd: float
    task_type: Optional[str] = None
    note: Optional[str] = None


# =========================================================
# 📈 コスト計算エンジン
# =========================================================
class BillingEngine:
    def __init__(self, task_type: Optional[str] = None) -> None:
        self.task_type = task_type
        self.records: List[CostRecord] = []

    def add_token_cost(self, model: str, input_tokens: int, output_tokens: int) -> None:
        rates = PRICE_MATRIX["tokens"].get(model)
        if rates is None:
            warn_unknown_price("tokens", model)
            rates = {"input": 0.0, "output": 0.0}

        cost = (
            (input_tokens / 1_000_000) * rates["input"]
            + (output_tokens / 1_000_000) * rates["output"]
        )

        self.records.append(
            CostRecord(
                dimension="tokens",
                resource=model,
                usage={"input": float(input_tokens), "output": float(output_tokens)},
                cost_usd=cost,
                task_type=self.task_type,
            )
        )

    def add_time_cost(
        self,
        resource: str,
        seconds: float,
        multiplier: float = 1.0,
        note: Optional[str] = None,
    ) -> None:
        rate = PRICE_MATRIX["time"].get(resource)
        if rate is None:
            warn_unknown_price("time", resource)
            rate = 0.0

        cost = seconds * multiplier * rate

        self.records.append(
            CostRecord(
                dimension="time",
                resource=resource,
                usage={"seconds": float(seconds), "multiplier": float(multiplier)},
                cost_usd=cost,
                task_type=self.task_type,
                note=note,
            )
        )

    def add_count_cost(self, resource: str, count: int, note: Optional[str] = None) -> None:
        # 後方互換用。今後は image 課金を優先して使う想定
        warnings.warn(
            "[BillingEngine] add_count_cost() is kept for backward compatibility. "
            "Prefer add_image_cost() for image models with tile/step pricing.",
            DeprecationWarning,
            stacklevel=2,
        )

        # count系価格表が無い場合も止めない
        rate_table = PRICE_MATRIX.get("count", {})
        rate = rate_table.get(resource)
        if rate is None:
            warn_unknown_price("count", resource)
            rate = 0.0

        cost = count * rate

        self.records.append(
            CostRecord(
                dimension="count",
                resource=resource,
                usage={"count": float(count)},
                cost_usd=cost,
                task_type=self.task_type,
                note=note,
            )
        )

    def add_image_cost(
        self,
        resource: str,
        tiles: int,
        steps: Optional[int] = None,
        note: Optional[str] = None,
    ) -> None:
        pricing = PRICE_MATRIX["image"].get(resource)
        if pricing is None:
            warn_unknown_price("image", resource)
            pricing = {"per_tile": 0.0, "per_step": 0.0, "default_steps": 0}

        actual_steps = pricing["default_steps"] if steps is None else steps
        cost = tiles * pricing["per_tile"] + actual_steps * pricing["per_step"]

        self.records.append(
            CostRecord(
                dimension="image",
                resource=resource,
                usage={"tiles": float(tiles), "steps": float(actual_steps)},
                cost_usd=cost,
                task_type=self.task_type,
                note=note,
            )
        )

    def total_usd(self) -> float:
        return sum(r.cost_usd for r in self.records)

    def report(self) -> str:
        lines = ["\n=== 📊 3D Cost Report ==="]

        for r in self.records:
            if r.dimension == "tokens":
                lines.append(
                    f"  [Tokens] {r.resource}: "
                    f"{int(r.usage['input'])} in, {int(r.usage['output'])} out "
                    f"-> ${r.cost_usd:.6f}"
                )

            elif r.dimension == "time":
                multiplier = r.usage.get("multiplier", 1.0)
                suffix = f" x{multiplier:.2f}" if multiplier != 1.0 else ""
                note_suffix = f" ({r.note})" if r.note else ""
                lines.append(
                    f"  [Time]   {r.resource}: "
                    f"{r.usage['seconds']:.2f}s{suffix} "
                    f"-> ${r.cost_usd:.6f}{note_suffix}"
                )

            elif r.dimension == "count":
                note_suffix = f" ({r.note})" if r.note else ""
                lines.append(
                    f"  [Count]  {r.resource}: "
                    f"{int(r.usage['count'])} units "
                    f"-> ${r.cost_usd:.6f}{note_suffix}"
                )

            elif r.dimension == "image":
                note_suffix = f" ({r.note})" if r.note else ""
                lines.append(
                    f"  [Image]  {r.resource}: "
                    f"{int(r.usage['tiles'])} tiles, {int(r.usage['steps'])} steps "
                    f"-> ${r.cost_usd:.6f}{note_suffix}"
                )

        lines.append("  -------------------------")
        lines.append(f"  TOTAL: ${self.total_usd():.6f}")
        return "\n".join(lines)

    def report_by_task(self) -> str:
        TASK_ORDER = [
            "CHECK_AND_ASSEMBLE",
            "CORE_EXTRACTION",
            "ROLE_CLASSIFICATION",
            "ANNOUNCEMENT_GENERATION",
            "TOPIC_MAPPING",
            "REVIEW_CARD_GENERATION",
            "IMAGE_PROMPT_GENERATION",
            "IMAGE_RENDERING",
            "FUN_FACT_SEARCH",
            "FUN_FACTS_GENERATION",
            "DETAIL_CONTENTS_GENERATION"
        ]

        from collections import defaultdict
        grouped = defaultdict(list)
        for r in self.records:
            grouped[r.task_type].append(r)

        lines = ["\n=== 📊 3D Grouped Cost Report ==="]

        sorted_tasks = []
        for task in TASK_ORDER:
            if task in grouped or (task is None and None in grouped):
                sorted_tasks.append(task)
        for task in grouped:
            if task not in sorted_tasks:
                sorted_tasks.append(task)

        for task in sorted_tasks:
            records = grouped[task]
            task_label = task if task is not None else "UNGROUPED"
            task_total = sum(r.cost_usd for r in records)
            lines.append(f"\n📂 [{task_label}] Subtotal: ${task_total:.6f}")

            for r in records:
                if r.dimension == "tokens":
                    lines.append(
                        f"  - [Tokens] {r.resource}: "
                        f"{int(r.usage['input'])} in, {int(r.usage['output'])} out "
                        f"-> ${r.cost_usd:.6f}"
                    )
                elif r.dimension == "time":
                    multiplier = r.usage.get("multiplier", 1.0)
                    suffix = f" x{multiplier:.2f}" if multiplier != 1.0 else ""
                    note_suffix = f" ({r.note})" if r.note else ""
                    lines.append(
                        f"  - [Time]   {r.resource}: "
                        f"{r.usage['seconds']:.2f}s{suffix} "
                        f"-> ${r.cost_usd:.6f}{note_suffix}"
                    )
                elif r.dimension == "count":
                    note_suffix = f" ({r.note})" if r.note else ""
                    lines.append(
                        f"  - [Count]  {r.resource}: "
                        f"{int(r.usage['count'])} units "
                        f"-> ${r.cost_usd:.6f}{note_suffix}"
                    )
                elif r.dimension == "image":
                    note_suffix = f" ({r.note})" if r.note else ""
                    lines.append(
                        f"  - [Image]  {r.resource}: "
                        f"{int(r.usage['tiles'])} tiles, {int(r.usage['steps'])} steps "
                        f"-> ${r.cost_usd:.6f}{note_suffix}"
                    )

        lines.append("\n=================================")
        lines.append(f"TOTAL COST: ${self.total_usd():.6f}")
        return "\n".join(lines)


# =========================================================
# 🧠 LLM ユニファイド・ラッパー
# =========================================================
@dataclass
class Message:
    role: Literal["system", "user", "assistant"]
    content: str


@dataclass
class LLMOptions:
    temperature: float = 0.2
    output_type: Literal["text", "json"] = "text"
    max_tokens: Optional[int] = None
    max_completion_tokens: Optional[int] = None
    reasoning_effort: Optional[Literal["low", "medium", "high"]] = None


@dataclass
class LLMResult:
    output_text: str
    output_json: Optional[Dict[str, Any]]
    model_used: str
    input_tokens: int = 0
    output_tokens: int = 0
    elapsed_seconds: float = 0.0
    json_parse_error: Optional[str] = None


class UnifiedLLM:
    def __init__(self, billing_engine: BillingEngine):
        self.billing = billing_engine

    async def generate(
        self,
        model: str,
        messages: List[Message],
        options: Optional[LLMOptions] = None,
    ) -> LLMResult:
        options = options or LLMOptions()

        litellm_messages = [{"role": m.role, "content": m.content} for m in messages]

        kwargs: Dict[str, Any] = {
            "model": model,
            "messages": litellm_messages,
            "temperature": options.temperature,
            # 429/5xx/タイムアウト等の一時的な失敗に対し、litellm組み込みの
            # リトライ機構（指数バックオフ）に任せる。100人同時利用でレート制限に
            # 引っかかる確率が上がることへの耐性。
            "num_retries": 3,
        }

        if options.max_tokens is not None:
            kwargs["max_tokens"] = options.max_tokens

        if options.max_completion_tokens is not None:
            kwargs["max_completion_tokens"] = options.max_completion_tokens

        if options.reasoning_effort is not None:
            kwargs["reasoning_effort"] = options.reasoning_effort

        # JSONモードの指定
        # NOTE: GPT-OSS models have a known token conflict between Harmony format and response_format,
        # leading to corrupt prefixes like {"final{":. We rely on raw text + extract_json_string for these models.
        if options.output_type == "json" and "gpt-oss" not in model:
            kwargs["response_format"] = {"type": "json_object"}

        # Gemini 3+ の場合は警告を避けるため temperature などのパラメータを削除する
        # (LiteLLMはGoogle AI StudioのGemini 3+に対してこれらのパラメータを非推奨警告として出力するため)
        if ("gemini-3" in model or "gemini/gemini-3" in model) and "temperature" in kwargs:
            del kwargs["temperature"]

        # 実行時間の概算計測
        start_time = time.perf_counter()

        try:
            response = await litellm.acompletion(**kwargs)
        except Exception as e:
            raise RuntimeError(f"LiteLLM Error with model {model}: {e}") from e

        elapsed_time = time.perf_counter() - start_time
        output_text = response.choices[0].message.content or ""

        usage = getattr(response, "usage", None)
        in_tokens = int(getattr(usage, "prompt_tokens", 0) or 0)
        out_tokens = int(getattr(usage, "completion_tokens", 0) or 0)

        # BillingEngine にコスト記録
        self.billing.add_token_cost(model, in_tokens, out_tokens)

        # Cloud Run は概算。少し高めの単価で丸める
        self.billing.add_time_cost(
            "cloudrun/self",
            elapsed_time,
            note="rough Cloud Run self cost",
        )

        out_json = None
        json_parse_error = None

        if options.output_type == "json":
            from app.services.helpers.helpers import extract_json_string
            cleaned_text = extract_json_string(output_text)
            try:
                out_json = json.loads(cleaned_text) if cleaned_text.strip() else None
            except Exception as e:
                json_parse_error = str(e)
                warnings.warn(
                    f"[UnifiedLLM] JSON parse error for model={model}: {e}. "
                    f"Raw output kept in output_text.",
                    RuntimeWarning,
                    stacklevel=2,
                )

        return LLMResult(
            output_text=output_text,
            output_json=out_json,
            model_used=model,
            input_tokens=in_tokens,
            output_tokens=out_tokens,
            elapsed_seconds=elapsed_time,
            json_parse_error=json_parse_error,
        )