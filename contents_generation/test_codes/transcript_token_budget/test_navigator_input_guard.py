"""
探索役の1周の入力の上限(NAVIGATOR_MAX_INPUT_ESTIMATE)の確認。API呼び出しなし・$0(LLMは偽物、検索は空)。
本番のターン(navigator_schema_cache/replay.py の build_turn)で:
  1. 本番の上限(60,000)では1周目が普通に呼ばれる(偽のLLMが enough_now を返す)
  2. 上限をその周の入力より小さくすると、LLMを呼ばずに stop_reason="input_limit" で止まる
  .venv/bin/python contents_generation/test_codes/transcript_token_budget/test_navigator_input_guard.py
"""
import asyncio, os, sys
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "navigator_schema_cache"))
import replay  # noqa: E402
from replay import nav, create_client  # noqa: E402


class FakeLLM:
    calls = 0

    async def generate(self, model, messages, options):
        FakeLLM.calls += 1
        r = type("R", (), {})()
        r.output_json = {"status": "enough_now", "reasoning": "fake", "goal": [], "missing": "", "operations": []}
        r.input_tokens = r.output_tokens = r.cache_read_tokens = 0
        r.json_parse_error = None
        r.finish_reason = "stop"
        return r


async def main():
    admin = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    nav_input, _ = await replay.build_turn(admin)
    tools = replay.build_tools(admin, None, nav_input, replay.BillingEngine(task_type="guard_test"), dry_run=True)
    est = (nav.estimate_tokens(nav.build_system_prompt(nav_input.can_transcript))
           + nav.estimate_tokens(nav.build_user_message(nav_input, nav.NavState(), 1)))
    lines = [f"# navigator input guard ({datetime.now():%Y-%m-%d %H:%M}), $0", f"- lap 1 input estimate: {est:,}"]
    r = await nav.navigate(FakeLLM(), nav_input, tools)
    lines.append(f"- limit {nav.NAVIGATOR_MAX_INPUT_ESTIMATE:,}: stop={r.stop_reason}, LLM calls={FakeLLM.calls}, "
                 f"lap1 timing={r.laps[0].timing if r.laps else None}")
    assert r.stop_reason == "enough_now" and FakeLLM.calls == 1
    nav.NAVIGATOR_MAX_INPUT_ESTIMATE = est - 1
    FakeLLM.calls = 0
    r = await nav.navigate(FakeLLM(), nav_input, tools)
    lines.append(f"- limit {nav.NAVIGATOR_MAX_INPUT_ESTIMATE:,}: stop={r.stop_reason}, LLM calls={FakeLLM.calls}, laps={len(r.laps)}")
    assert r.stop_reason == "input_limit" and FakeLLM.calls == 0
    lines.append("PASS")
    text = "\n".join(lines)
    print(text)
    (HERE / "results").mkdir(exist_ok=True)
    (HERE / "results" / f"{datetime.now():%Y%m%d_%H%M%S}_navigator_input_guard.md").write_text(text + "\n", encoding="utf-8")

asyncio.run(main())
