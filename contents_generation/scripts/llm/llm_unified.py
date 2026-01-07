# llm_unified.py
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Literal, Union
import json
import os

LLMProvider = Literal["gemini", "openai"]
OutputType = Literal["text", "json"]
ReasoningEffort = Literal["low", "medium", "high"]

@dataclass
class Message:
    role: Literal["system", "user", "assistant"]
    content: str

@dataclass
class Usage:
    input_tokens: int = 0
    output_tokens: int = 0
    reasoning_tokens: int = 0
    total_tokens: int = 0

@dataclass
class LLMResult:
    output_text: str
    output_json: Optional[Dict[str, Any]]
    usage: Usage
    estimated_cost_usd: float = 0.0
    provider: str = ""
    model_name: str = ""
    warnings: List[str] = field(default_factory=list)
    raw: Any = None

@dataclass
class LLMOptions:
    temperature: float = 0.2
    output_type: OutputType = "text"

    # OpenAI: 今は json_object、将来 json_schema に切り替えられるよう箱だけ作る
    json_schema: Optional[Dict[str, Any]] = None

    # Gemini: （必要なら）thinking / google search
    thinking_budget: int = 0
    google_search: bool = False

    # OpenAI (Reasoning)
    reasoning_effort: Optional[ReasoningEffort] = None

    # 追加パラメータはここに入れておく（provider側で拾えるものだけ使う）
    provider_kwargs: Dict[str, Any] = field(default_factory=dict)

# alias → 実モデル名
MODEL_MAP: Dict[LLMProvider, Dict[str, str]] = {
    "gemini": {
        "2_5_flash": "gemini-2.5-flash",
        "2_5_flash_lite": "gemini-2.5-flash-lite",
    },
    "openai": {
        "5_mini": "gpt-5-mini",
        "5_nano": "gpt-5-nano",
        "4_1_mini": "gpt-4.1-mini",
    }
}

# $ / 1M tokens（Standard想定、必要なモデルだけでOK）
PRICING_PER_1M: Dict[LLMProvider, Dict[str, Dict[str, float]]] = {
    "openai": {
        "gpt-5-mini": {"input": 0.25, "output": 2.00},
        "gpt-5-nano": {"input": 0.05, "output": 0.40},
        "gpt-4.1-mini": {"input": 0.40, "output": 1.60},
    },
    "gemini": {
        "gemini-2.5-flash": {"input": 0.30, "output": 2.50},
        "gemini-2.5-flash-lite": {"input": 0.10, "output": 0.40},
    }
}

def estimate_cost(provider: LLMProvider, model_name: str, usage: Usage) -> float:
    price = PRICING_PER_1M.get(provider, {}).get(model_name)
    if not price:
        return 0.0
    return (usage.input_tokens / 1_000_000.0) * price.get("input", 0.0) + \
           (usage.output_tokens / 1_000_000.0) * price.get("output", 0.0)

class UnifiedLLM:
    """
    provider: "gemini" | "openai"
    model: alias (例: "2_5_flash", "5_mini") か実モデル名
    """
    def __init__(self, provider: LLMProvider, api_key: Optional[str] = None):
        self.provider = provider
        self.api_key = api_key or self._load_key(provider)
        self.client = self._init_client()

    def _load_key(self, provider: LLMProvider) -> str:
        env = "GEMINI_API_KEY" if provider == "gemini" else "SHOGO_S_OPENAI_API_KEY"
        v = os.getenv(env)
        if not v:
            raise RuntimeError(f"Missing {env}. Please set it in your environment.")
        return v

    def _init_client(self):
        if self.provider == "gemini":
            from google import genai
            return genai.Client(api_key=self.api_key)
        else:
            from openai import OpenAI
            return OpenAI(api_key=self.api_key)

    def resolve_model(self, model: str) -> str:
        return MODEL_MAP[self.provider].get(model, model)

    def generate(
        self,
        model: str,
        messages: List[Message],
        options: Optional[LLMOptions] = None,
    ) -> LLMResult:
        options = options or LLMOptions()
        model_name = self.resolve_model(model)

        if self.provider == "gemini":
            res = self._gen_gemini(model_name, messages, options)
        else:
            res = self._gen_openai(model_name, messages, options)

        res.provider = self.provider
        res.model_name = model_name
        res.estimated_cost_usd = estimate_cost(self.provider, model_name, res.usage)
        return res

    # -------- Gemini adapter --------
    def _gen_gemini(self, model_name: str, messages: List[Message], options: LLMOptions) -> LLMResult:
        from google.genai import types

        warnings: List[str] = []

        # messages → contents(list[str]) に丸める
        # systemは先頭に、残りは user/assistant を順に連結
        contents: List[str] = []
        for m in messages:
            if m.role == "system":
                contents.append(m.content)
            elif m.role == "user":
                contents.append(m.content)
            elif m.role == "assistant":
                # Geminiにassistant履歴を入れたいケースもあるが、まずは textとして入れる
                contents.append(m.content)

        kwargs: Dict[str, Any] = dict(temperature=options.temperature)

        if options.output_type == "json":
            kwargs["response_mime_type"] = "application/json"
        else:
            kwargs["response_mime_type"] = "text/plain"

        # Gemini固有
        if options.thinking_budget and options.thinking_budget > 0:
            kwargs["thinking_config"] = types.ThinkingConfig(thinking_budget=options.thinking_budget)
        if options.google_search:
            kwargs["tools"] = [types.Tool(google_search=types.GoogleSearch())]

        # OpenAI向けjson_schemaはGeminiでは未使用（無視）
        if options.json_schema:
            warnings.append("json_schema is ignored for gemini (currently).")

        # provider_kwargsから拾えるものだけ拾う（基本無視、必要なら後で拡張）
        if options.provider_kwargs:
            warnings.append(f"provider_kwargs ignored for gemini: {list(options.provider_kwargs.keys())}")

        config = types.GenerateContentConfig(**kwargs)
        resp = self.client.models.generate_content(model=model_name, contents=contents, config=config)

        # usage
        usage = Usage()
        um = getattr(resp, "usage_metadata", None)
        if um is not None:
            prompt_tokens = int(getattr(um, "prompt_token_count", 0) or 0)
            out_tokens = int(getattr(um, "candidates_token_count", 0) or 0)
            total = int(getattr(um, "total_token_count", prompt_tokens + out_tokens) or 0)
            reasoning = max(0, total - prompt_tokens - out_tokens)
            usage = Usage(prompt_tokens, out_tokens, reasoning, total)

        text = getattr(resp, "text", "") or ""
        out_json = None
        if options.output_type == "json":
            try:
                out_json = json.loads(text) if text.strip() else None
            except Exception:
                warnings.append("JSON parse failed. output_json is None.")
                out_json = None

        return LLMResult(output_text=text, output_json=out_json, usage=usage, warnings=warnings, raw=resp)

    # -------- OpenAI adapter (Responses API) --------
    def _gen_openai(self, model_name: str, messages: List[Message], options: LLMOptions) -> LLMResult:
        warnings: List[str] = []

        # system は instructions に寄せる（推奨）
        sys_parts = [m.content for m in messages if m.role == "system"]
        instructions = "\n\n".join(sys_parts).strip() if sys_parts else None

        input_payload = [{"role": m.role, "content": m.content} for m in messages if m.role != "system"]

        # JSON出力指定は response_format ではなく text.format
        text_cfg: Optional[Dict[str, Any]] = None
        if options.output_type == "json":
            if options.json_schema:
                # Structured Outputs (json_schema)
                text_cfg = {
                    "format": {
                        "type": "json_schema",
                        "strict": True,
                        "schema": options.json_schema,
                    }
                }
            else:
                # JSON mode (json_object)
                text_cfg = {"format": {"type": "json_object"}}

        # Gemini固有は無視
        if options.thinking_budget:
            warnings.append("thinking_budget is ignored for openai.")
        if options.google_search:
            warnings.append("google_search is ignored for openai (use tools later).")

        # provider_kwargs は allowlist 方式
        allow = {"max_output_tokens", "top_p", "seed", "service_tier"}
        extra = {k: v for k, v in options.provider_kwargs.items() if k in allow}
        ignored = [k for k in options.provider_kwargs.keys() if k not in allow]
        if ignored:
            warnings.append(f"provider_kwargs ignored for openai: {ignored}")

        # OpenAI reasoning effort (optional)
        reasoning_cfg: Optional[Dict[str, Any]] = None
        if getattr(options, "reasoning_effort", None):
            reasoning_cfg = {"effort": options.reasoning_effort}

        req = dict(
            model=model_name,
            input=input_payload if input_payload else "",
            instructions=instructions,
            text=text_cfg,
            **extra,
        )
        if reasoning_cfg is not None:
            req["reasoning"] = reasoning_cfg

        resp = self.client.responses.create(**req)

        # output text
        text = getattr(resp, "output_text", "") or ""

        # usage
        usage = Usage()
        u = getattr(resp, "usage", None)
        if u is not None:
            in_tok = int(getattr(u, "input_tokens", 0) or 0)
            out_tok = int(getattr(u, "output_tokens", 0) or 0)
            total = int(getattr(u, "total_tokens", in_tok + out_tok) or 0)
            reasoning = int(getattr(u, "reasoning_tokens", 0) or 0) if hasattr(u, "reasoning_tokens") else 0
            usage = Usage(in_tok, out_tok, reasoning, total)

        out_json = None
        if options.output_type == "json":
            try:
                out_json = json.loads(text) if text.strip() else None
            except Exception:
                warnings.append("JSON parse failed. output_json is None.")
                out_json = None

        return LLMResult(output_text=text, output_json=out_json, usage=usage, warnings=warnings, raw=resp)
