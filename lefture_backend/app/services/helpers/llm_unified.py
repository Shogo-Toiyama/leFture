# app/services/helpers/llm_unified.py
from dataclasses import dataclass, field
from typing import Any, AsyncIterator, Dict, List, Optional, Literal
import base64
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
        # cache_read/cache_write: プロンプトキャッシュの読み込み/書き込み単価。
        # 公式価格ページで確認したモデルにだけ書く。無いモデルはキャッシュ分も
        # 通常の入力単価で計算する(安全側)。Geminiの暗黙キャッシュは書き込みが無料。
        # 2026-09-29確認: ai.google.dev/gemini-api/docs/pricing, developers.openai.com/api/docs/pricing
        "gemini/gemini-2.5-flash-lite": {"input": 0.10, "output": 0.40, "cache_read": 0.01},
        "gemini/gemini-2.5-flash": {"input": 0.30, "output": 2.50},
        # 2026-10-01にGoogle公式価格($0.25/$1.50)に修正(以前は入力$0.40で過大計上)。
        # チャットはここから計算した実コスト×2をクレジットとして請求するため、
        # この表は原価の可視化だけでなく請求額に直結する。
        "gemini/gemini-3.1-flash-lite": {"input": 0.25, "output": 1.50, "cache_read": 0.025},
        # 2026-10-02にGoogle公式価格(ai.google.dev/gemini-api/docs/pricing)で確認。チャットの回答役。
        # 出力には思考のトークンも含まれる。
        "gemini/gemini-3.5-flash-lite": {"input": 0.30, "output": 2.50, "cache_read": 0.03},
        # 2026-10-03にGoogle公式価格で確認。2026年末までのプロモーション価格($0.75/$3.75/$0.075)ではなく、
        # 2027-01-01からの通常価格を入れている(安全側に倒す。ユーザーの方針)。出力には思考のトークンも含まれる。
        "gemini/gemini-3.8-flash": {"input": 1.50, "output": 7.50, "cache_read": 0.15},
        # 2026-09-22公開のOpenAI公式価格。CORE_EXTRACTIONでgemini-3.1-flash-liteの
        # 代替として採用（安価かつ知識ワーク系ベンチマークで上回るため）。
        # 自動でキャッシュに書き込まれ、書き込みは通常入力の1.25倍(272K以下の短文脈の価格)。
        "gpt-6-luna": {"input": 0.10, "output": 0.50, "cache_read": 0.01, "cache_write": 0.125},
        # 2026-10-07リリース。チャットの回答役(2026-10-07にLunaから変更)。プロンプトが10万トークンを超えると、
        # そのリクエストは入力も出力も5倍の単価になる(long_context)。回答役はchat_serviceの
        # ANSWER_MAX_INPUT_ESTIMATEで超えないように組み立てる。キャッシュ(cache_control)は今は使っていない。
        "anthropic/claude-haiku-5-5": {
            "input": 0.10, "output": 0.50,
            "long_context": {"above_input_tokens": 100_000, "input": 0.50, "output": 2.50},
        },
        # 横断チャットボット段階0(knowledge_chunks)の埋め込みモデル。
        # 埋め込みAPIには出力トークン課金が無いのでoutputは0。
        "gemini/gemini-embedding-2": {"input": 0.20, "output": 0.0},
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


def _cache_note(r: CostRecord) -> str:
    read, write = int(r.usage.get("cache_read", 0)), int(r.usage.get("cache_write", 0))
    if not read and not write:
        return ""
    return f" (cache read {read}, write {write})"


# =========================================================
# 📈 コスト計算エンジン
# =========================================================
class BillingEngine:
    def __init__(self, task_type: Optional[str] = None) -> None:
        self.task_type = task_type
        self.records: List[CostRecord] = []

    def add_token_cost(
        self,
        model: str,
        input_tokens: int,
        output_tokens: int,
        cache_read_tokens: int = 0,
        cache_write_tokens: int = 0,
    ) -> None:
        """input_tokensはキャッシュ分を含む総数。cache_read/writeはその内訳(APIの報告値)。"""
        rates = PRICE_MATRIX["tokens"].get(model)
        if rates is None:
            warn_unknown_price("tokens", model)
            rates = {"input": 0.0, "output": 0.0}
        # プロンプトが長いと、そのリクエスト全体(入力も出力も)が別の単価になるモデル
        long_context = rates.get("long_context")
        if long_context and input_tokens > long_context["above_input_tokens"]:
            rates = long_context

        cache_read_tokens = max(0, min(cache_read_tokens, input_tokens))
        cache_write_tokens = max(0, min(cache_write_tokens, input_tokens - cache_read_tokens))
        uncached_tokens = input_tokens - cache_read_tokens - cache_write_tokens

        cost = (
            (uncached_tokens / 1_000_000) * rates["input"]
            + (cache_read_tokens / 1_000_000) * rates.get("cache_read", rates["input"])
            + (cache_write_tokens / 1_000_000) * rates.get("cache_write", rates["input"])
            + (output_tokens / 1_000_000) * rates["output"]
        )

        usage = {"input": float(input_tokens), "output": float(output_tokens)}
        if cache_read_tokens:
            usage["cache_read"] = float(cache_read_tokens)
        if cache_write_tokens:
            usage["cache_write"] = float(cache_write_tokens)

        self.records.append(
            CostRecord(
                dimension="tokens",
                resource=model,
                usage=usage,
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
                    f"{int(r.usage['input'])} in{_cache_note(r)}, {int(r.usage['output'])} out "
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
                        f"{int(r.usage['input'])} in{_cache_note(r)}, {int(r.usage['output'])} out "
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
    # 一緒に渡す画像(JPEGのバイト列)。チャットに添付した画像・ページの書き起こしで使う。
    # contentを文字列のまま保つため別の欄にしている(履歴の切り詰め・ログなどはcontentだけを見る)
    images: List[bytes] = field(default_factory=list)


def _litellm_message(m: Message) -> Dict[str, Any]:
    """画像があれば、OpenAI形式の [text, image_url(data URI)...] にする(GeminiもlitellmがOpenAI形式から変換する)。"""
    if not m.images:
        return {"role": m.role, "content": m.content}
    parts: List[Dict[str, Any]] = []
    if m.content:
        parts.append({"type": "text", "text": m.content})
    for data in m.images:
        parts.append({"type": "image_url",
                      "image_url": {"url": "data:image/jpeg;base64," + base64.b64encode(data).decode("ascii")}})
    return {"role": m.role, "content": parts}


@dataclass
class LLMOptions:
    temperature: float = 0.2
    output_type: Literal["text", "json"] = "text"
    max_tokens: Optional[int] = None
    max_completion_tokens: Optional[int] = None
    # "none"はGemini 3系(thinkingLevel: minimal)とgpt-6-luna(推論なし)で使う
    reasoning_effort: Optional[Literal["none", "low", "medium", "high"]] = None
    # output_type="json"のとき、JSON Schemaを渡すとプロバイダー側の構造化出力
    # (Geminiならresponse_schema)で生成を縛る。enum等で出力の形を保証したい
    # 場合(チャットの振り分け役など)に使う。Noneなら従来どおりjson_object。
    json_schema: Optional[Dict[str, Any]] = None


@dataclass
class LLMResult:
    output_text: str
    output_json: Optional[Dict[str, Any]]
    model_used: str
    input_tokens: int = 0
    output_tokens: int = 0
    elapsed_seconds: float = 0.0
    json_parse_error: Optional[str] = None
    cache_read_tokens: int = 0
    cache_write_tokens: int = 0
    # "stop" / "length" / "content_filter"(安全フィルタで遮断) など。
    # litellmがGeminiのSAFETY等を"content_filter"に正規化して返す。
    finish_reason: Optional[str] = None


@dataclass
class StreamState:
    """generate_stream()の結果置き場。async generatorは値を返せないため、
    呼び出し側が用意したこのオブジェクトに最終結果を書き込む。"""
    output_text: str = ""
    finish_reason: Optional[str] = None
    input_tokens: int = 0
    output_tokens: int = 0
    cache_read_tokens: int = 0
    cache_write_tokens: int = 0
    elapsed_seconds: float = 0.0
    usage_estimated: bool = False


def _cache_token_counts(usage: Any) -> tuple[int, int]:
    """
    litellmのusageからキャッシュの(読み込み, 書き込み)トークン数を取る。
    どちらもprompt_tokensの内訳。Geminiの暗黙キャッシュ(cachedContentTokenCount)と
    OpenAIの自動キャッシュ(cached_tokens / cache_write_tokens)は、litellmが
    prompt_tokens_detailsに揃えて入れる(2026-09-29にストリーミング/非ストリーミング
    の両方で実測確認)。
    """
    details = getattr(usage, "prompt_tokens_details", None)
    read = int(getattr(details, "cached_tokens", 0) or 0)
    write = int(getattr(details, "cache_write_tokens", 0) or 0)
    return read, write


_REASONING_EFFORT_PASSTHROUGH_MODELS = frozenset({"gpt-6-luna"})


class UnifiedLLM:
    def __init__(self, billing_engine: BillingEngine):
        self.billing = billing_engine

    def _build_kwargs(
        self,
        model: str,
        messages: List[Message],
        options: LLMOptions,
    ) -> Dict[str, Any]:
        litellm_messages = [_litellm_message(m) for m in messages]

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
            # litellmのモデル表がreasoning_effortを知らないモデルは、明示的に通すよう
            # 頼まないとUnsupportedParamsErrorになる(gpt-6-lunaで2026-09-30に確認)
            if model in _REASONING_EFFORT_PASSTHROUGH_MODELS:
                kwargs["allowed_openai_params"] = ["reasoning_effort"]

        # JSONモードの指定
        # NOTE: GPT-OSS models have a known token conflict between Harmony format and response_format,
        # leading to corrupt prefixes like {"final{":. We rely on raw text + extract_json_string for these models.
        if options.output_type == "json" and "gpt-oss" not in model:
            if options.json_schema is not None:
                kwargs["response_format"] = {
                    "type": "json_schema",
                    "json_schema": {"name": "output", "schema": options.json_schema},
                }
            else:
                kwargs["response_format"] = {"type": "json_object"}

        # Gemini 3+ の場合は警告を避けるため temperature などのパラメータを削除する
        # (LiteLLMはGoogle AI StudioのGemini 3+に対してこれらのパラメータを非推奨警告として出力するため)
        if ("gemini-3" in model or "gemini/gemini-3" in model) and "temperature" in kwargs:
            del kwargs["temperature"]

        return kwargs

    async def generate(
        self,
        model: str,
        messages: List[Message],
        options: Optional[LLMOptions] = None,
    ) -> LLMResult:
        options = options or LLMOptions()
        kwargs = self._build_kwargs(model, messages, options)

        # 実行時間の概算計測
        start_time = time.perf_counter()

        try:
            response = await litellm.acompletion(**kwargs)
        except Exception as e:
            raise RuntimeError(f"LiteLLM Error with model {model}: {e}") from e

        elapsed_time = time.perf_counter() - start_time
        output_text = response.choices[0].message.content or ""
        finish_reason = getattr(response.choices[0], "finish_reason", None)

        usage = getattr(response, "usage", None)
        in_tokens = int(getattr(usage, "prompt_tokens", 0) or 0)
        out_tokens = int(getattr(usage, "completion_tokens", 0) or 0)
        cache_read, cache_write = _cache_token_counts(usage)

        # BillingEngine にコスト記録
        self.billing.add_token_cost(model, in_tokens, out_tokens, cache_read, cache_write)

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
            cache_read_tokens=cache_read,
            cache_write_tokens=cache_write,
            finish_reason=finish_reason,
        )

    async def generate_stream(
        self,
        model: str,
        messages: List[Message],
        state: StreamState,
        options: Optional[LLMOptions] = None,
    ) -> AsyncIterator[str]:
        """
        テキストの差分(delta)を順次yieldするストリーミング版。終了後、
        stateに全文・終了理由・トークン数が入り、コストはgenerate()と同じく
        BillingEngineに記録される(思考トークンはlitellmがoutputに合算する)。

        使い方:
            state = StreamState()
            async for delta in llm.generate_stream(model, messages, state):
                ...
            # ここでstate.output_text / state.finish_reason が確定している
        """
        options = options or LLMOptions()
        kwargs = self._build_kwargs(model, messages, options)
        kwargs["stream"] = True
        kwargs["stream_options"] = {"include_usage": True}

        start_time = time.perf_counter()
        try:
            response = await litellm.acompletion(**kwargs)
        except Exception as e:
            raise RuntimeError(f"LiteLLM Error with model {model}: {e}") from e

        parts: List[str] = []
        async for chunk in response:
            usage = getattr(chunk, "usage", None)
            if usage is not None:
                state.input_tokens = int(getattr(usage, "prompt_tokens", 0) or 0) or state.input_tokens
                state.output_tokens = int(getattr(usage, "completion_tokens", 0) or 0) or state.output_tokens
                read, write = _cache_token_counts(usage)
                state.cache_read_tokens = read or state.cache_read_tokens
                state.cache_write_tokens = write or state.cache_write_tokens
            if not chunk.choices:
                continue
            choice = chunk.choices[0]
            if getattr(choice, "finish_reason", None):
                state.finish_reason = choice.finish_reason
            delta = getattr(getattr(choice, "delta", None), "content", None)
            if delta:
                parts.append(delta)
                yield delta

        state.output_text = "".join(parts)
        state.elapsed_seconds = time.perf_counter() - start_time

        # 通常は最後のチャンクにusageが載る。載らなかった場合だけ概算で埋める
        # (思考トークン分は数えられないので過小になる。課金の取りこぼしを
        # 目立たせるためusage_estimatedを立てて呼び出し側で記録する)。
        if state.input_tokens == 0 and state.output_tokens == 0:
            state.usage_estimated = True
            try:
                state.input_tokens = litellm.token_counter(model=model, messages=kwargs["messages"])
                state.output_tokens = litellm.token_counter(model=model, text=state.output_text)
            except Exception:
                pass

        self.billing.add_token_cost(
            model, state.input_tokens, state.output_tokens,
            state.cache_read_tokens, state.cache_write_tokens,
        )
        self.billing.add_time_cost(
            "cloudrun/self",
            state.elapsed_seconds,
            note="rough Cloud Run self cost",
        )