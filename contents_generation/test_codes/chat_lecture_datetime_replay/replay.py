"""Rebuild the two chat turns from read-only Supabase data and replay the answer."""

import argparse
import asyncio
from dataclasses import asdict
from datetime import datetime
import importlib.util
import json
import os
from pathlib import Path
import sys
from time import perf_counter
from types import SimpleNamespace
from unittest.mock import patch
from zoneinfo import ZoneInfo

os.environ.setdefault("LITELLM_LOCAL_MODEL_COST_MAP", "True")

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "reply_ending_eval"))
import replay as base
from jsonschema import validate
from app.services import chat_map, chat_navigator as nav
from app.services.chat_lecture_source import DbLectureSource
from app.services.chat_thread_source import DbChatThreadSource
from app.services.chat_materials import format_sources_block
from app.services.helpers.llm_unified import _litellm_message

cs = base.cs
TZ = ZoneInfo(base.TZ_NAME)
CASES = ("exam", "web_followup")


def candidate_map():
    name = "app.services.chat_map_candidate"
    spec = importlib.util.spec_from_file_location(name, HERE / "patched" / "chat_map.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def check_order(module):
    # Include a DST fold, equivalent timestamps, and missing/bad dates.
    course = {"id": "course"}
    records = [
        ("later", "2026-11-01T01:10:00-08:00", 1),
        ("earlier", "2026-11-01T01:50:00-07:00", 5),
        ("same-earlier", "2026-11-01T08:50:00Z", 3),
        ("missing", None, 1),
        ("invalid", "invalid", 2),
    ]
    lectures = [{"id": key, "course_id": "course", "lecture_datetime": when, "sort_order": order}
                for key, when, order in records]
    db = MockMapClient({"courses": [course], "lectures": lectures})
    mapped = module.load_student_map(db, "user", TZ).courses[0].lectures
    assert [lec.id for lec in mapped] == ["same-earlier", "earlier", "later", "missing", "invalid"]
    assert [lec.handle for lec in mapped] == [f"C1/L{n}" for n in range(1, 6)]


class MockMapClient:
    def __init__(self, rows):
        self.rows = rows

    def table(self, table):
        self.current = table
        return self

    def select(self, _):
        return self

    def eq(self, *_):
        return self

    def is_(self, *_):
        return self

    def order(self, _):
        return self

    def execute(self):
        return SimpleNamespace(data=self.rows[self.current])


class DryNavigator:
    def __init__(self, course_handle):
        self.course_handle = course_handle
        self.calls = 0

    async def generate(self, model, messages, options):
        self.calls += 1
        assert model == nav.NAVIGATOR_MODEL
        assert all(_litellm_message(message)["content"] for message in messages)
        operations = [{"op": "open", "handle": f"{self.course_handle}/topics"}] if self.calls == 1 else []
        data = {"reasoning": "Use the course topic list.", "need": "explicit", "fetch_from": ["class"],
                "status": "need_more" if operations else "enough_now", "missing": "",
                "operations": operations, "goal": []}
        validate(data, options.json_schema)
        return SimpleNamespace(output_json=data, input_tokens=0, cache_read_tokens=0, output_tokens=0)


def find_saved_reply(client, title_and_time):
    title, created_at = title_and_time
    found = client.table("chat_threads").select("id").eq("title", title).is_("deleted_at", "null").execute().data
    assert found, "No matching thread title"
    rows = client.table("chat_messages").select("id,thread_id,role,content,status,created_at,router,usage") \
        .in_("thread_id", [row["id"] for row in found]).eq("created_at", created_at) \
        .eq("role", "assistant").is_("deleted_at", "null").execute().data
    assert len(rows) == 1, "Expected exactly one saved reply"
    return rows[0]


async def build_case(client, case, selector):
    saved = find_saved_reply(client, selector)
    answer_args = {}
    build_answer = cs._build_answer_messages

    def capture(*args, **kwargs):
        answer_args["positional"] = args
        answer_args["keyword"] = kwargs
        return build_answer(*args, **kwargs)

    with patch.object(cs, "_build_answer_messages", capture), patch.object(base, "find_message", return_value=saved), \
         patch.object(base, "use_variant"):
        built = await base.build_case(client, {"id": case, "msg": "scoped lookup"})
    return built, answer_args


async def run_case(client, module, case, selector, dry_run):
    built, answer_args = await build_case(client, case, selector)
    turn = built["turn"]
    decision = built["decision"]
    if decision.needs_reasoning:
        raise ValueError("This harness covers the normal answer path captured in these two turns.")
    billing = base.BillingEngine(task_type="CHAT_DATETIME_REPLAY")
    llm = None if dry_run else base.UnifiedLLM(billing)
    positionals = answer_args["positional"]
    kwargs = answer_args["keyword"]
    navigation = None
    materials = []
    retrieval_ms = 0
    if case == "exam":
        assert decision.needs_retrieval
        blocked = cs._load_blocked_source_types(turn.user_id)
        student_map = module.load_student_map(client, turn.user_id, TZ)
        screen_lecture = student_map.lecture(student_map.lecture_handle(turn.context_lecture_id))
        course = student_map.course(screen_lecture.course_handle)
        assert [lecture.date for lecture in course.lectures if lecture.date] == sorted(
            lecture.date for lecture in course.lectures if lecture.date)
        assert str(screen_lecture.date) == "2026-11-05" and screen_lecture.handle.endswith("/L13")
        exam_dates = [str(lecture.date) for lecture in course.lectures[9:13]]
        assert exam_dates == ["2026-10-27", "2026-10-29", "2026-11-03", "2026-11-05"]
        print(f"Exam screen lecture handle {screen_lecture.handle}", flush=True)
        chat_source = DbChatThreadSource(client, turn.user_id)
        chat_map_context = chat_map.load_chat_map(turn.summary_blocks,
            await chat_source.recent_threads_with_trail(turn.thread_id, 20), turn.summary_level2)
        when = built["when"].astimezone(TZ)
        nav_input = nav.NavigatorInput(
            message=turn.message_for_prompt, selected_text=turn.selected_text,
            screen_lecture_id=turn.context_lecture_id, screen_course_id=turn.context_course_id,
            recent_conversation=positionals[3], today=when.date(), current_time_str=when.strftime("%Y-%m-%d (%a) %H:%M"),
            student_map=student_map, chat_map=chat_map_context, current_thread_id=turn.thread_id,
            previous_turn_refs=cs._previous_turn_refs(turn.history_rows),
            blocked_source_types=blocked, screen_topic_index=cs._screen_topic_index(turn),
            screen_page_title=turn.screen_page.title if turn.screen_page else None,
            screen_page_excerpt=turn.screen_page.excerpt() if turn.screen_page else None,
            attachments=turn.attachments, attachment_visibility=kwargs["attachment_visibility"],
            links=cs._turn_links(turn), user_goal=decision.user_goal, referenced_sources=kwargs["referenced_sources"],
        )

        async def unavailable_search(requests):
            return [RuntimeError("Vector search requires an authenticated user session in this replay.")
                    for _ in requests]

        started = perf_counter()
        navigation = await nav.navigate(llm or DryNavigator(course.handle), nav_input, nav.NavigatorTools(
            search=unavailable_search, source=DbLectureSource(client, turn.user_id, blocked), chat_source=chat_source))
        retrieval_ms = round((perf_counter() - started) * 1000)
        materials = await cs.select_materials_async(
            [material for material in navigation.materials if material.source_type not in blocked], billing=billing)
        assert materials, f"Exam navigation returned no materials ({navigation.stop_reason})"
        kwargs["retrieval_reasoning"] = navigation.laps[-1].reasoning
        if dry_run:
            tree = next(m.content for m in materials if m.kind == "course_topics")
            assert tree.index("2026-11-05") < tree.index("2026-11-10")
    else:
        assert not decision.needs_retrieval

    previous = await cs._fetch_previous_citations(client, turn.thread_id, turn.history_rows)
    carried = cs.previous_web_materials(previous, materials)
    if case == "web_followup":
        assert carried and "Waymo" in format_sources_block(carried)
    materials.extend(carried)
    base.FrozenDatetime.frozen = built["when"]
    with patch.object(cs, "datetime", base.FrozenDatetime):
        messages, _ = cs.fit_answer_input(cs._build_answer_messages(*positionals[:5], materials, **kwargs))
    messages = cs.apply_prompt_cache_controls(messages, cs.ANSWER_MODEL)
    options = cs.answer_options(cs.ANSWER_MODEL, built["effort"], cs._answer_max_tokens(navigation, materials))
    assert all(_litellm_message(message)["content"] for message in messages)
    assert options.max_tokens or options.max_completion_tokens
    metrics = {"case": case, "prompt_estimate": base.est(messages), "retrieval_ms": retrieval_ms,
               "previous_web_sources": len(carried), "material_kinds": [material.kind for material in materials],
               "navigator_stop": navigation.stop_reason if navigation else None,
               "navigator_laps": len(navigation.laps) if navigation else 0}
    if dry_run:
        assert not billing.records
        print(json.dumps(metrics), flush=True)
        return metrics, None

    print(f"Generating answer for {case}", flush=True)
    state = base.StreamState()
    started = perf_counter()
    first = None
    async for delta in llm.generate_stream(cs.ANSWER_MODEL, messages, state, options):
        if first is None and delta:
            first = perf_counter()
    assert state.output_text.strip()
    metrics.update(answer_ms=round((perf_counter() - started) * 1000),
                   answer_ttft_ms=round((first - started) * 1000) if first else None,
                   answer_input_tokens=state.input_tokens, answer_output_tokens=state.output_tokens,
                   answer_cache_read_tokens=state.cache_read_tokens, cost_usd=round(billing.total_usd(), 8),
                   usage=[{k: v for k, v in asdict(record).items() if k != "note"} for record in billing.records])
    answer = cs.normalize_citations(state.output_text, materials)
    return metrics, answer


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--order-only", action="store_true")
    parser.add_argument("--exam", nargs=2, metavar=("TITLE", "REPLY_AT"))
    parser.add_argument("--web-followup", nargs=2, metavar=("TITLE", "REPLY_AT"))
    args = parser.parse_args()
    module = candidate_map() if args.candidate else chat_map
    check_order(module)
    if args.order_only:
        print("Chronological order, equal instants, and missing dates: OK")
        return
    client = base.create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    stamp = datetime.now(TZ).strftime("%Y-%m-%dT%H%M%S%z")
    for case in CASES:
        selector = getattr(args, case)
        if not selector:
            continue
        metrics, answer = await run_case(client, module, case, selector, args.dry_run)
        if answer:
            raw_dir = HERE / "inputs"
            raw_dir.mkdir(exist_ok=True, mode=0o700)
            answer_path = raw_dir / f"{stamp}-{case}-answer.md"
            answer_path.touch(mode=0o600, exist_ok=False)
            answer_path.write_text(answer + "\n")
        output = HERE / "results" / f"{stamp}-{case}{'-dry-run' if args.dry_run else ''}.json"
        output.write_text(json.dumps(metrics, indent=2) + "\n")
        print(output.name, flush=True)


if __name__ == "__main__":
    asyncio.run(main())
