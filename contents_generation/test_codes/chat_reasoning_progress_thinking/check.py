"""Reproduce the production progress-label request with a synthetic excerpt."""

import argparse
import asyncio
import json
import os
from pathlib import Path
import sys
from unittest.mock import patch

import httpx
from dotenv import load_dotenv


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "lefture_backend"))
from app.services.helpers.llm_unified import BillingEngine, LLMOptions, Message, UnifiedLLM

MODEL = "anthropic/claude-haiku-5-5"
EXCERPT = (
    "I'm checking which variables are bound in a nested lambda. "
    "The student asks how the scope changes inside the second lambda. "
    "The next step is to compare the two scopes."
)


class OriginalLLM(UnifiedLLM):
    def _build_kwargs(self, model, messages, options):
        kwargs = super()._build_kwargs(model, messages, options)
        kwargs.pop("thinking", None)
        kwargs["reasoning_effort"] = "none"
        return kwargs


class CandidateLLM(UnifiedLLM):
    def _build_kwargs(self, model, messages, options):
        kwargs = super()._build_kwargs(model, messages, options)
        kwargs.pop("reasoning_effort", None)
        kwargs["thinking"] = {"type": "disabled"}
        return kwargs


async def mock_send(self, request, **kwargs):
    return httpx.Response(200, request=request, json={
        "id": "msg_fixture",
        "type": "message",
        "role": "assistant",
        "model": "claude-haiku-5-5",
        "stop_reason": "end_turn",
        "stop_sequence": None,
        "content": [{"type": "text", "text": "変数のスコープを確認中"}],
        "usage": {"input_tokens": 30, "output_tokens": 10},
    })


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--production", action="store_true")
    parser.add_argument("--max-tokens", type=int, default=96)
    parser.add_argument("--capture", type=Path, help="Replay the first three lines from the six previously approved excerpts.")
    args = parser.parse_args()
    if args.live:
        load_dotenv(ROOT / "lefture_backend/.env")
        assert os.environ.get("ANTHROPIC_API_KEY")

    prompt = (
        ROOT / "lefture_backend/app/services/prompts/chat_reasoning_progress_prompt.txt"
    ).read_text().replace("${reply_language}", "Japanese")
    samples = [EXCERPT]
    if args.capture:
        rows = json.loads(args.capture.read_text())
        assert len(rows) == 6
        samples = ["\n\n".join(
            [line.strip() for line in row["thinking_summary"].splitlines() if line.strip()][:3]
        ) for row in rows]
    options = LLMOptions(temperature=1.0, max_tokens=args.max_tokens, reasoning_effort="none")
    variants = (
        [("production", UnifiedLLM, {"type": "disabled"})] if args.production else
        [("original", OriginalLLM, None), ("explicit_disable", CandidateLLM, {"type": "disabled"})]
    )
    send = httpx.AsyncClient.send

    for name, llm_class, expected in variants:
        excerpts = samples * (3 if args.live and not args.production and not args.capture else 1)
        for excerpt in excerpts:
            messages = [Message(role="system", content=prompt), Message(role="user", content=excerpt)]
            payloads = []

            async def capture(client, request, **kwargs):
                assert (request.url.host, request.url.path) == ("api.anthropic.com", "/v1/messages")
                payloads.append(json.loads(request.content))
                return await (send if args.live else mock_send)(client, request, **kwargs)

            billing = BillingEngine(task_type="PROGRESS_THINKING_CHECK")
            with patch.dict(os.environ, {} if args.live else {"ANTHROPIC_API_KEY": "fixture"}):
                with patch.object(httpx.AsyncClient, "send", capture):
                    result = await llm_class(billing).generate(MODEL, messages, options)
            assert len(payloads) == 1
            body = payloads[0]
            assert body.get("thinking") == expected and body["max_tokens"] == args.max_tokens
            text = result.output_text.strip()
            valid_label = bool(text) and len(text) <= 60 and len(text.splitlines()) == 1 and text != "NONE"
            print(json.dumps({
                "variant": name,
                "thinking": body.get("thinking"),
                "max_tokens": body["max_tokens"],
                "finish_reason": result.finish_reason,
                "input_tokens": result.input_tokens,
                "output_tokens": result.output_tokens,
                **({"label": text} if not args.capture else {}),
                "valid_label": valid_label,
                "elapsed_ms": round(result.elapsed_seconds * 1000, 1),
                "provider_usd": sum(record.cost_usd for record in billing.records if record.dimension == "tokens"),
            }, ensure_ascii=False), flush=True)
            if not args.live or args.production:
                assert valid_label


if __name__ == "__main__":
    asyncio.run(main())
