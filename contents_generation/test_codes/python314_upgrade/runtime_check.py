"""
Run the same production code paths on the current Python and print a JSON report, so the
3.11 and 3.14 reports can be diffed. No live API calls: every HTTP request to Anthropic and
Gemini is intercepted at httpx.AsyncClient.send and answered with a fixture, cost $0.

Checks:
- pydub: AudioSegment.from_file on an in-memory WAV and len() (what transcription.py does
  with m4a; m4a decoding needs ffmpeg, which is not installed on this PC).
- litellm request bodies built by UnifiedLLM for the production chat calls:
  router (Gemini 3.1 Flash Lite, JSON schema, effort none), navigator-like JSON call
  (Haiku 5.5, schema, effort low), progress label (Haiku 5.5, effort none -> thinking disabled),
  and the streamed answer (Haiku 5.5, effort low).
- Pure helpers: normalize_handle and lecture_handles_to_names.
"""

import asyncio
import io
import json
import os
import struct
import sys
import time
import wave
from datetime import date
from pathlib import Path
from unittest.mock import patch

import httpx

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "lefture_backend"))

from app.services.helpers.llm_unified import BillingEngine, LLMOptions, Message, StreamState, UnifiedLLM  # noqa: E402

FAKE_ENV = {"ANTHROPIC_API_KEY": "fixture", "GEMINI_API_KEY": "fixture", "GOOGLE_API_KEY": "fixture"}


def check_pydub() -> dict:
    from pydub import AudioSegment
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(b"".join(struct.pack("<h", (i * 37) % 2000 - 1000) for i in range(16000 * 2)))
    seg = AudioSegment.from_file(io.BytesIO(buf.getvalue()), format="wav")
    return {"duration_ms": len(seg), "rms": seg.rms, "frame_rate": seg.frame_rate}


def anthropic_json(text: str) -> dict:
    return {"id": "msg_fixture", "type": "message", "role": "assistant", "model": "claude-haiku-5-5",
            "stop_reason": "end_turn", "stop_sequence": None,
            "content": [{"type": "text", "text": text}],
            "usage": {"input_tokens": 30, "output_tokens": 10}}


def anthropic_sse(text: str) -> bytes:
    events = [
        ("message_start", {"type": "message_start", "message": {**anthropic_json(""), "content": [],
                                                                "stop_reason": None}}),
        ("content_block_start", {"type": "content_block_start", "index": 0,
                                 "content_block": {"type": "text", "text": ""}}),
        *[("content_block_delta", {"type": "content_block_delta", "index": 0,
                                   "delta": {"type": "text_delta", "text": part}}) for part in text.split(" ")],
        ("content_block_stop", {"type": "content_block_stop", "index": 0}),
        ("message_delta", {"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence": None},
                           "usage": {"output_tokens": 10}}),
        ("message_stop", {"type": "message_stop"}),
    ]
    return "".join(f"event: {e}\ndata: {json.dumps(d)}\n\n" for e, d in events).encode()


def gemini_json(text: str) -> dict:
    return {"candidates": [{"content": {"parts": [{"text": text}], "role": "model"}, "finishReason": "STOP",
                            "index": 0}],
            "usageMetadata": {"promptTokenCount": 30, "candidatesTokenCount": 10, "totalTokenCount": 40},
            "modelVersion": "gemini-3.1-flash-lite"}


CAPTURED: list[dict] = []


async def fake_send(client, request, **kwargs):
    body = json.loads(request.content) if request.content else None
    CAPTURED.append({"host": request.url.host, "path": request.url.path, "body": body})
    if request.url.host == "api.anthropic.com":
        if body and body.get("stream"):
            return httpx.Response(200, request=request, content=anthropic_sse("Hello from the fixture."),
                                  headers={"content-type": "text/event-stream"})
        text = json.dumps({"status": "ok"}) if "json" in json.dumps(body) else "変数のスコープを確認中"
        return httpx.Response(200, request=request, json=anthropic_json(text))
    if "generativelanguage" in request.url.host:
        return httpx.Response(200, request=request, json=gemini_json(json.dumps({"intent": "learning"})))
    raise RuntimeError(f"unexpected host {request.url.host}")


def strip_volatile(body):
    """Keys whose values change between runs (none expected, kept for safety)."""
    return body


async def check_llm() -> dict:
    schema = {"type": "object", "properties": {"status": {"type": "string"}}, "required": ["status"]}
    router_schema = {"type": "object", "properties": {"intent": {"type": "string"}}, "required": ["intent"]}
    msgs = [Message(role="system", content="You are a test."), Message(role="user", content="Hi")]
    calls = {
        "router_gemini": ("gemini/gemini-3.1-flash-lite",
                          LLMOptions(temperature=0.0, output_type="json", reasoning_effort="none",
                                     json_schema=router_schema)),
        "navigator_like_haiku": ("anthropic/claude-haiku-5-5",
                                 LLMOptions(temperature=0.2, output_type="json", reasoning_effort="low",
                                            json_schema=schema, max_tokens=2000)),
        "progress_haiku": ("anthropic/claude-haiku-5-5",
                           LLMOptions(temperature=1.0, max_tokens=256, reasoning_effort="none")),
    }
    out = {}
    with patch.dict(os.environ, FAKE_ENV), patch.object(httpx.AsyncClient, "send", fake_send):
        for name, (model, opts) in calls.items():
            CAPTURED.clear()
            t0 = time.perf_counter()
            try:
                res = await UnifiedLLM(BillingEngine(task_type="PY314_CHECK")).generate(model, msgs, opts)
                out[name] = {"ok": True, "text": res.output_text, "json": res.output_json,
                             "finish": res.finish_reason, "in": res.input_tokens, "out": res.output_tokens,
                             "requests": [{"host": c["host"], "path": c["path"], "body": c["body"]} for c in CAPTURED],
                             "ms": round((time.perf_counter() - t0) * 1000, 1)}
            except Exception as e:
                out[name] = {"ok": False, "error": f"{type(e).__name__}: {e}"[:500],
                             "requests": [{"host": c["host"], "path": c["path"], "body": c["body"]} for c in CAPTURED]}
        # streamed answer
        CAPTURED.clear()
        try:
            chunks = []
            state = StreamState()
            gen = UnifiedLLM(BillingEngine(task_type="PY314_CHECK")).generate_stream(
                "anthropic/claude-haiku-5-5", msgs, state,
                LLMOptions(temperature=1.0, reasoning_effort="low", max_tokens=4000))
            async for ev in gen:
                chunks.append(ev)
            out["answer_stream_haiku"] = {"ok": True, "events": len(chunks), "text": "".join(chunks),
                                          "final_text": state.output_text, "finish": state.finish_reason,
                                          "in": getattr(state, "input_tokens", None),
                                          "out": getattr(state, "output_tokens", None),
                                          "requests": [{"host": c["host"], "path": c["path"], "body": c["body"]}
                                                       for c in CAPTURED]}
        except Exception as e:
            out["answer_stream_haiku"] = {"ok": False, "error": f"{type(e).__name__}: {e}"[:500]}
    return out


def check_helpers() -> dict:
    from app.services.chat_map import MapCourse, MapLecture, StudentMap
    from app.services.chat_navigator import lecture_handles_to_names, normalize_handle
    c = MapCourse(handle="C4", id="c", title="Programming Language", term=None, recorded_language=None,
                  notes_language=None)
    for i, d in enumerate([date(2026, 10, 22), date(2026, 10, 27)], 9):
        c.lectures.append(MapLecture(handle=f"C4/L{i}", id=f"l{i}", course_handle="C4", title=f"Lecture {i}", date=d))
    m = StudentMap.build([c])
    return {
        "normalize": [normalize_handle(x) for x in ["c4/l6-L7", "Ｃ４／Ｌ６", "C4/L06 to L07", "open C4/topics"]],
        "names": lecture_handles_to_names("C4/L9 and C4/L9-10, L1 cache, C4/L10/T2", m, {"C4/L10/T2": "Scope"}),
    }


async def main():
    report = {"python": sys.version.split()[0]}
    for name, fn in (("pydub", check_pydub), ("helpers", check_helpers)):
        try:
            report[name] = fn()
        except Exception as e:
            report[name] = {"error": f"{type(e).__name__}: {e}"}
    report["llm"] = await check_llm()
    print(json.dumps(report, ensure_ascii=False, indent=1, default=str))


if __name__ == "__main__":
    asyncio.run(main())
