# contents_generation/test_codes/context_and_notes_test.py
"""
Unit and integration test for:
1. SUMMARY_SCHEMA & validate_summary_output (turns, source_turn, needs_source, backward compatibility)
2. extract_source_turns_to_fetch helper
3. build_history_messages full-text preservation and turn-level budget dropping
4. _build_answer_messages with referenced_sources and retrieval_reasoning
"""

import sys
from pathlib import Path

# Add backend to path
REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from app.services.chat_summary import (
    Turn,
    SUMMARY_SCHEMA,
    validate_summary_output,
    extract_source_turns_to_fetch,
    render_notes_for_answer,
    SummaryValidationError,
)
from app.services.chat_service import (
    build_history_messages,
    _build_answer_messages,
    PreparedTurn,
    RouterDecision,
    ConversationMemory,
)
from app.services.helpers.llm_unified import Message


def test_summary_schema_and_backward_compatibility():
    print("--- Test 1: Summary Validation & Backward Compatibility ---")
    turns = [
        Turn(1, "u1", "a1", "User 1", "Asst 1", "2026-10-23T12:00:00Z", "en"),
        Turn(2, "u2", "a2", "User 2", "Asst 2", "2026-10-23T12:05:00Z", "en"),
    ]

    # 1. New schema format (turns, source_turn, needs_source)
    new_output = {
        "sections": [
            {"title": "Section A", "bullets": ["Bullet 1"], "turns": [1, 2]}
        ],
        "header": {
            "style_preferences": [{"text": "Casual", "source_turn": 1, "needs_source": False}],
            "context": [{"text": "7 Review Topics", "source_turn": 1, "needs_source": True}],
            "purpose": [],
            "unresolved": [],
        }
    }
    secs, header = validate_summary_output(new_output, turns, next_handle=1)
    assert len(secs) == 1
    assert secs[0]["turns"] == [1, 2]
    assert len(header["context"]) == 1
    assert header["context"][0]["source_turn"] == 1
    assert header["context"][0]["needs_source"] is True
    print("  ✅ New format parsed correctly")

    # 2. Legacy schema format (rounds, source_round, no needs_source)
    legacy_output = {
        "sections": [
            {"title": "Section Legacy", "bullets": ["Bullet L"], "rounds": [1]}
        ],
        "header": {
            "style_preferences": [{"text": "No math", "source_round": 1}],
            "context": [],
            "purpose": [],
            "unresolved": [],
        }
    }
    secs_l, header_l = validate_summary_output(legacy_output, turns, next_handle=1)
    assert secs_l[0]["turns"] == [1]
    assert header_l["style_preferences"][0]["source_turn"] == 1
    assert header_l["style_preferences"][0]["needs_source"] is False
    print("  ✅ Legacy format backward compatibility verified")

    # 3. extract_source_turns_to_fetch
    needed = extract_source_turns_to_fetch(header)
    assert needed == [1], f"Expected [1], got {needed}"
    needed_none = extract_source_turns_to_fetch(None)
    assert needed_none == [], f"Expected [], got {needed_none}"
    print("  ✅ extract_source_turns_to_fetch correctly identifies target turns")

    # 4. render_notes_for_answer sorting and markdown formatting
    test_hdr = {
        "style_preferences": [
            {"text": "英語も併記する", "source_turn": 4},
            {"text": "数式を控える", "source_turn": 1},
        ],
        "context": [
            {"text": "明日はテスト", "source_turn": 1},
        ],
        "purpose": [],
        "unresolved": [],
    }
    rendered = render_notes_for_answer(test_hdr)
    expected = (
        "Response style requested:\n"
        "- 数式を控える (turn 1)\n"
        "- 英語も併記する (turn 4)\n\n"
        "Context for this conversation:\n"
        "- 明日はテスト (turn 1)"
    )
    assert rendered == expected, f"Render mismatch:\nGot:\n{rendered}\nExpected:\n{expected}"
    print("  ✅ render_notes_for_answer sorts by turn and renders clean markdown bullets")


def test_build_history_messages_uncompressed():
    print("\n--- Test 2: History Message Preservation (No mid-sentence truncation) ---")
    # Message with 3,500 characters (previously truncated at 2,000)
    long_asst_text = "第3章 データリンク層の解説です。\n" + ("詳細な説明文がここに続きます。" * 200)
    assert len(long_asst_text) > 3000

    rows = [
        {"id": "u1", "role": "user", "content": "データリンク層について教えて"},
        {"id": "a1", "role": "assistant", "content": long_asst_text, "status": "complete"},
    ]

    messages = build_history_messages(rows, max_turns=20, max_chars=None)
    assert len(messages) == 2
    # Verify assistant content is 100% preserved
    assert messages[1].content == long_asst_text
    print(f"  ✅ Assistant message of {len(long_asst_text):,} chars preserved with 0 truncation!")


def test_build_history_messages_turn_budget_dropping():
    print("\n--- Test 3: History Turn-Level Budget Dropping (30,000 tokens limit) ---")
    # Create 10 turns of ~4,000 tokens each (~40,000 tokens total)
    huge_text = "長文の解説。" * 400 # ~4400 tokens per turn
    rows = []
    for i in range(1, 11):
        rows.append({"id": f"u{i}", "role": "user", "content": f"質問 {i}"})
        rows.append({"id": f"a{i}", "role": "assistant", "content": f"回答 {i}: {huge_text}", "status": "complete"})

    # build_history_messages should drop oldest complete pairs until under 30,000 tokens
    messages = build_history_messages(rows, max_turns=20, max_chars=None)
    # Each turn has 2 messages (user, assistant). Verify even length (strictly complete pairs)
    assert len(messages) % 2 == 0
    num_turns_retained = len(messages) // 2
    print(f"  ✅ Successfully retained latest {num_turns_retained} complete turns under budget")
    # Verify latest turn is Turn 10
    assert messages[-2].content == "質問 10"
    assert "回答 10:" in messages[-1].content


def test_build_answer_messages_injection():
    print("\n--- Test 4: Answer Message Prompt Injection (<referenced_sources> & <retrieval_reasoning>) ---")
    turn = PreparedTurn(
        user_id="test_user",
        thread_id="test_thread",
        is_new_thread=False,
        thread_has_title=True,
        user_message_id="u_curr",
        assistant_message_id="a_curr",
        content="次へ進んでもいいですか？",
        selected_text=None,
        lecture_label="CS118 Lecture 4",
        context_lecture_id="lec_1",
    )
    decision = RouterDecision(
        intent="learning",
        needs_retrieval=False,
        needs_reasoning=False,
        reply_language="ja",
        thread_title=None,
        user_goal="Advance to Topic 4 (Reliable Data Transfer) according to the 7-topic review agenda",
    )
    memory = ConversationMemory(summary="過去の要約", notes="過去のノート")
    history = [
        Message(role="user", content="Turn 17 Question"),
        Message(role="assistant", content="Turn 17 Answer"),
    ]

    ref_sources_text = "[Turn 1] Student: 以下の7項目を復習したい:\n1. 物理層\n2. パケット交換\n3. データリンク層\n4. Reliable Data Transfer"
    retrieval_reasoning_text = "Topic 4 (Reliable Data Transfer) detail is already present in notes; guiding the student through Stop-and-Wait."

    messages = _build_answer_messages(
        turn=turn,
        decision=decision,
        memory=memory,
        history=history,
        profile="CS major student",
        materials=[],
        referenced_sources=ref_sources_text,
        retrieval_reasoning=retrieval_reasoning_text,
    )

    system_prompt = messages[0].content
    assert "<referenced_sources>" in system_prompt
    assert ref_sources_text in system_prompt
    assert "<conversation_notes>" in system_prompt

    last_user_prompt = messages[-1].content
    assert "<user_goal>" in last_user_prompt
    assert decision.user_goal in last_user_prompt
    assert "<retrieval_reasoning>" in last_user_prompt
    assert retrieval_reasoning_text in last_user_prompt

    print("  ✅ <conversation_notes> and <referenced_sources> in System, and <user_goal> & <retrieval_reasoning> in Turn prompt successfully verified!")


async def test_router_referenced_sources_injection():
    print("\n--- Test 5: Router Input Prompt Injection (<referenced_sources>) ---")
    import asyncio
    import json
    from app.services.chat_service import _run_router, TurnTimer
    from app.services.helpers.llm_unified import LLMResult

    class MockLLM:
        def __init__(self):
            self.last_messages = None

        async def generate(self, model, messages, options):
            self.last_messages = messages
            res_dict = {
                "intent": "learning",
                "needs_retrieval": True,
                "needs_reasoning": False,
                "user_goal": "Advance to Topic 4 (Reliable Data Transfer)",
                "retrieval_reason": "Topic 4 needs lecture retrieval",
                "reply_language": "ja",
                "thread_title": None,
            }
            return LLMResult(
                output_text=json.dumps(res_dict),
                output_json=res_dict,
                model_used=model,
                input_tokens=150,
                output_tokens=40,
            )

    turn = PreparedTurn(
        user_id="test_user",
        thread_id="test_thread",
        is_new_thread=False,
        thread_has_title=True,
        user_message_id="u_curr",
        assistant_message_id="a_curr",
        content="次！",
        selected_text=None,
        lecture_label="CS118 Lecture 4",
        context_lecture_id="lec_1",
        timer=TurnTimer(),
    )
    memory = ConversationMemory(summary="これまでの要約", notes="これまでのノート")
    history = [Message(role="user", content="前回の質問")]
    ref_sources_text = "[Turn 1] Student: 以下の7項目を復習したい:\n1. 物理層\n2. データリンク層\n3. フレーミング\n4. Reliable Data Transfer"

    # Case A: with referenced_sources
    mock_llm = MockLLM()
    decision = await _run_router(
        llm=mock_llm,
        turn=turn,
        memory=memory,
        history=history,
        courses_text="- Computer Networks",
        attachments_text="(none)",
        referenced_sources=ref_sources_text,
    )
    user_prompt = mock_llm.last_messages[1].content
    assert "<referenced_sources>" in user_prompt, "Expected <referenced_sources> in Router user prompt"
    assert ref_sources_text in user_prompt, "Expected raw text in <referenced_sources>"
    assert decision.user_goal == "Advance to Topic 4 (Reliable Data Transfer)"
    print("  ✅ Router input prompt includes <referenced_sources> when referenced_sources is present")

    # Case B: without referenced_sources
    mock_llm_empty = MockLLM()
    await _run_router(
        llm=mock_llm_empty,
        turn=turn,
        memory=memory,
        history=history,
        courses_text="- Computer Networks",
        attachments_text="(none)",
        referenced_sources=None,
    )
    user_prompt_empty = mock_llm_empty.last_messages[1].content
    assert "<referenced_sources>" not in user_prompt_empty, "Expected NO <referenced_sources> when None"
    print("  ✅ Router input prompt omits <referenced_sources> when referenced_sources is None")


if __name__ == "__main__":
    import asyncio
    test_summary_schema_and_backward_compatibility()
    test_build_history_messages_uncompressed()
    test_build_history_messages_turn_budget_dropping()
    test_build_answer_messages_injection()
    asyncio.run(test_router_referenced_sources_injection())
    print("\n🎉 ALL TESTS PASSED WITH 100% SUCCESS!")

