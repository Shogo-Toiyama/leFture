"""Benchmark user-facing progress lines with provider-native streaming endpoints."""

import argparse
import asyncio
from pathlib import Path
from datetime import datetime
import json
import os
import random
import statistics
from string import Template
from time import perf_counter
from zoneinfo import ZoneInfo

from dotenv import load_dotenv
import httpx

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MODELS = {
    "haiku": ("claude-haiku-5-5", 0.10, 0.50),
    "qwen": ("Qwen/Qwen3.5-9B", 0.17, 0.25),
    "luna": ("gpt-6-luna", 0.10, 0.50),
    "qwen_flash": ("Qwen/Qwen3.8-Flash", 0.15, 0.47),
}
TOGETHER_MODELS = {"qwen", "qwen_flash"}


def split_summary(summary):
    lines = [line.strip() for line in summary.splitlines() if line.strip()]
    sizes = [3] * (len(lines) // 3)
    if len(lines) % 3 == 1:
        sizes[-1:] = [2, 2]
    elif len(lines) % 3 == 2:
        sizes.append(2)
    chunks = []
    offset = 0
    for size in sizes:
        chunks.append(lines[offset:offset + size])
        offset += size
    assert all(2 <= len(chunk) <= 3 for chunk in chunks)
    assert [line for chunk in chunks for line in chunk] == lines
    return chunks


def parameters(provider, system, excerpt, key):
    model = MODELS[provider][0]
    messages = [{"role": "system", "content": system}, {"role": "user", "content": excerpt}]
    if provider == "haiku":
        return "https://api.anthropic.com/v1/messages", {
            "x-api-key": key, "anthropic-version": "2023-06-01",
        }, {"model": model, "system": system, "messages": messages[1:], "max_tokens": 96,
            "thinking": {"type": "disabled"}, "stream": True}
    if provider in TOGETHER_MODELS:
        return "https://api.together.ai/v1/chat/completions", {
            "Authorization": f"Bearer {key}",
        }, {"model": model, "messages": messages, "max_tokens": 96, "reasoning": {"enabled": False}, "stream": True}
    return "https://api.openai.com/v1/responses", {
        "Authorization": f"Bearer {key}",
    }, {"model": model, "instructions": system, "input": excerpt, "max_output_tokens": 96,
        "reasoning": {"effort": "none"}, "store": False, "stream": True}


class Stream:
    def __init__(self):
        self.text = []
        self.first = None
        self.last = None
        self.input = None
        self.output = None
        self.cached = 0
        self.cache_write = 0
        self.stop = None
        self.reasoning_observed = False

    def update(self, provider, data, elapsed):
        kind = data.get("type")
        text = ""
        if provider == "haiku":
            if kind == "message_start":
                usage = data["message"]["usage"]
                self.cached = usage.get("cache_read_input_tokens", 0)
                self.cache_write = usage.get("cache_creation_input_tokens", 0)
                self.input = usage["input_tokens"] + self.cached + self.cache_write
            elif kind == "content_block_delta" and data["delta"]["type"] == "text_delta":
                text = data["delta"]["text"]
            elif kind == "message_delta":
                self.output = data["usage"]["output_tokens"]
                self.stop = data["delta"]["stop_reason"]
        elif provider in TOGETHER_MODELS:
            if data.get("choices"):
                choice = data["choices"][0]
                delta = choice.get("delta") or {}
                text = delta.get("content") or ""
                self.reasoning_observed |= bool(delta.get("reasoning") or delta.get("reasoning_content"))
                self.stop = choice.get("finish_reason") or self.stop
            if usage := data.get("usage"):
                self.input = usage["prompt_tokens"]
                self.output = usage["completion_tokens"]
                self.cached = (usage.get("prompt_tokens_details") or {}).get("cached_tokens") or 0
                self.reasoning_observed |= bool((usage.get("completion_tokens_details") or {}).get("reasoning_tokens"))
        else:
            if kind == "response.output_text.delta":
                text = data["delta"]
            elif kind in {"response.completed", "response.incomplete"}:
                usage = data["response"]["usage"]
                self.input = usage["input_tokens"]
                self.output = usage["output_tokens"]
                self.cached = (usage.get("input_tokens_details") or {}).get("cached_tokens") or 0
                self.stop = kind.removeprefix("response.")
        if text:
            self.text.append(text)
            if text.strip():
                self.last = elapsed
                if self.first is None:
                    self.first = elapsed

    def result(self, provider, elapsed):
        text = "".join(self.text).strip()
        costs = None
        if self.input is not None and self.output is not None:
            _, input_rate, output_rate = MODELS[provider]
            cached_rate = 0.01 if provider in {"haiku", "luna"} else input_rate
            costs = ((self.input - self.cached - self.cache_write) * input_rate
                     + self.cached * cached_rate + self.cache_write * 0.125 + self.output * output_rate) / 1e6
        return {"line": text, "elapsed_ms": round(elapsed * 1000, 2),
                "ttft_ms": round(self.first * 1000, 2) if self.first is not None else None,
                "line_ms": round(self.last * 1000, 2) if self.last is not None else None,
                "input_tokens": self.input, "output_tokens": self.output, "cost_usd": costs,
                "reasoning_observed": self.reasoning_observed,
                "stop": self.stop, "format_ok": bool(text) and ("\n" not in text and len(text) <= 60),
                "under_500_ms": self.last is not None and self.last <= 0.5}


def verify_mocks(system, samples):
    fake_events = {
        "haiku": [
            {"type": "message_start", "message": {"usage": {"input_tokens": 20}}},
            {"type": "content_block_delta", "delta": {"type": "text_delta", "text": "確認中…"}},
            {"type": "message_delta", "usage": {"output_tokens": 5}, "delta": {"stop_reason": "end_turn"}},
        ],
        "qwen": [
            {"choices": [{"delta": {"content": "確認中…"}}]},
            {"choices": [{"finish_reason": "stop"}], "usage": {"prompt_tokens": 20, "completion_tokens": 5}},
        ],
        "luna": [
            {"type": "response.output_text.delta", "delta": "確認中…"},
            {"type": "response.completed", "response": {"usage": {"input_tokens": 20, "output_tokens": 5}}},
        ],
    }
    for provider in MODELS:
        stream = Stream()
        for event in fake_events["qwen" if provider in TOGETHER_MODELS else provider]:
            stream.update(provider, event, .25)
        record = stream.result(provider, .35)
        assert record["format_ok"] and record["cost_usd"] and record["ttft_ms"] == 250
        assert record["input_tokens"] == 20 and record["output_tokens"] == 5
    for _, excerpt in samples:
        for provider in MODELS:
            url, headers, payload = parameters(provider, system, excerpt, "fixture")
            assert url.startswith("https://") and headers and payload["stream"] and payload["max_tokens" if provider != "luna" else "max_output_tokens"] >= 16
            supplied_excerpt = payload["input"] if provider == "luna" else payload["messages"][-1]["content"]
            assert supplied_excerpt == excerpt
            if provider in TOGETHER_MODELS:
                assert payload["reasoning"] == {"enabled": False}
    stream = Stream()
    stream.update("qwen_flash", {"choices": [{"delta": {"reasoning_content": "mock"}}]}, .1)
    assert stream.reasoning_observed and not stream.text


async def request(client, provider, system, excerpt, key):
    url, headers, body = parameters(provider, system, excerpt, key)
    stream = Stream()
    started = perf_counter()
    async with client.stream("POST", url, json=body, headers=headers) as response:
        if response.status_code != 200:
            return {"error": f"HTTP {response.status_code}"}
        async for line in response.aiter_lines():
            if not line.startswith("data: "):
                continue
            raw = line.removeprefix("data: ")
            if raw == "[DONE]":
                break
            event = json.loads(raw)
            if event.get("type") in {"error", "response.failed"} or event.get("error"):
                return {"error": "Provider stream error"}
            stream.update(provider, event, perf_counter() - started)
    return stream.result(provider, perf_counter() - started)


def summarize(rows):
    report = {}
    for provider in dict.fromkeys(row["provider"] for row in rows):
        records = [row for row in rows if row["provider"] == provider and "error" not in row]
        latencies = [r["elapsed_ms"] for r in records if r["line"]]
        first = [r["ttft_ms"] for r in records if r["ttft_ms"] is not None]
        line = [r["line_ms"] for r in records if r["line_ms"] is not None]
        costs = [r["cost_usd"] for r in records if r["cost_usd"] is not None]
        report[provider] = {
            "completed": len(latencies), "priced": len(costs),
            "median_ms": statistics.median(latencies) if latencies else None,
            "median_ttft_ms": statistics.median(first) if first else None,
            "median_line_ms": statistics.median(line) if line else None,
            "under_500_ms": sum(r["under_500_ms"] and r["line"] != "NONE" and bool(r["line"]) for r in records),
            "none": sum(r["line"] == "NONE" for r in records), "format_ok": sum(r["format_ok"] for r in records),
            "cost_usd": round(sum(costs), 8) if costs else None,
            "input_tokens": sum(r["input_tokens"] or 0 for r in records) if costs else None,
            "output_tokens": sum(r["output_tokens"] or 0 for r in records) if costs else None,
            "reasoning_observed": sum(r["reasoning_observed"] for r in records),
        }
    return report


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--capture", type=Path, required=True)
    parser.add_argument("--prompt", type=Path, default=HERE / "progress_prompt.txt")
    parser.add_argument("--samples", nargs="+", type=int, help="Replay only the given capture sample numbers.")
    parser.add_argument("--models", nargs="+", choices=MODELS, default=["haiku", "qwen", "luna"])
    args = parser.parse_args()
    system = Template(args.prompt.read_text()).substitute(reply_language="Japanese")
    rows = json.loads(args.capture.read_text())
    assert len(rows) == 6
    if args.samples:
        selected = set(args.samples)
        if missing_samples := selected - {row["sample"] for row in rows}:
            parser.error(f"unknown capture samples: {sorted(missing_samples)}")
        rows = [row for row in rows if row["sample"] in selected]
    samples = []
    partition_counts = []
    for row in rows:
        chunks = split_summary(row["thinking_summary"])
        partition_counts.append([len(chunk) for chunk in chunks])
        samples.append((row["sample"], "\n\n".join(chunks[0])))
    verify_mocks(system, samples)
    print("Dry-run passed. Samples:", [sample for sample, _ in samples],
          "Chunk sizes:", partition_counts, flush=True)
    if not args.live:
        return
    load_dotenv(ROOT / "lefture_backend" / ".env")
    keys = {
        "haiku": os.environ.get("ANTHROPIC_API_KEY"),
        "qwen": next((os.environ[k] for k in ("TOGETHER_API_KEY", "TOGETHER_AI_API_KEY", "TOGETHERAI_API_KEY")
                      if os.environ.get(k)), None),
        "luna": os.environ.get("OPENAI_API_KEY"),
    }
    keys["qwen_flash"] = keys["qwen"]
    if missing := [name for name in args.models if not keys[name]]:
        raise SystemExit(f"Missing credentials for: {', '.join(missing)}")
    jobs = [(provider, sample, excerpt, repeat)
            for provider in args.models for sample, excerpt in samples for repeat in range(1, 3)]
    random.Random(71).shuffle(jobs)
    stamp = datetime.now(ZoneInfo("America/Los_Angeles")).strftime("%Y-%m-%dT%H%M%S%z")
    output = HERE / "inputs" / f"{stamp}-provider-benchmark.json"
    output.touch(0o600, exist_ok=False)
    results = []
    async with httpx.AsyncClient(timeout=15) as client:
        for provider, sample, excerpt, repeat in jobs:
            try:
                record = await request(client, provider, system, excerpt, keys[provider])
            except (httpx.HTTPError, ValueError, KeyError) as exc:
                record = {"error": type(exc).__name__}
            results.append({"provider": provider, "sample": sample, "repeat": repeat, **record})
            output.write_text(json.dumps({"summary": summarize(results), "trials": results},
                                         ensure_ascii=False, indent=2) + "\n")
            print(provider, sample, repeat, record.get("elapsed_ms", record.get("error")), flush=True)
            if provider == "qwen_flash" and (record.get("reasoning_observed")
                                             or record.get("error") in {"HTTP 400", "HTTP 401", "HTTP 403", "HTTP 404", "HTTP 422"}):
                break
    print(json.dumps(summarize(results), indent=2), flush=True)
    print(output.name, flush=True)


if __name__ == "__main__":
    asyncio.run(main())
