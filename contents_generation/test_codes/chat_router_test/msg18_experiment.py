import asyncio
import os
import sys
import time
import json
from dotenv import load_dotenv

load_dotenv('lefture_backend/.env')
sys.path.insert(0, 'lefture_backend')

from app.services.helpers.llm_unified import BillingEngine, UnifiedLLM, Message, LLMOptions, StreamState
from app.services.chat_service import (
    ANSWER_MODEL,
    estimate_tokens,
    build_history_messages,
    _build_answer_messages,
    _format_student_memos,
    _render_conditional_sections,
    fill_placeholders,
    _load_prompt,
    format_screen_context,
    render_for_answer,
    plan_visibility,
    render_ai_code_rule,
    format_sources_block,
    Material,
    ScreenPage,
    Attachment,
    PreparedTurn,
    RouterDecision,
    ConversationMemory,
)
from supabase import create_client

client = create_client(os.environ['SUPABASE_URL'], os.environ['SUPABASE_SECRET_KEY'])
thread_id = 'b70b7b26-21d3-4e56-944b-459411578cd1'

# 1. Fetch thread messages
all_msgs = client.table('chat_messages').select('*').eq('thread_id', thread_id).order('created_at').execute().data

# Msg 18 is the target user message ("あ、今前君があげてくれた単語まとめを上から順番に追いかけてるの。次に行っていいかな？")
m18 = all_msgs[18]
assert '単語まとめを上から順番に' in m18['content']

# Actual assistant response in thread (Baseline Run 1)
actual_m19 = all_msgs[19]

# Rebuild history up to Msg 17
history_rows = all_msgs[:18]
history = build_history_messages(history_rows, max_turns=6, max_chars=3000)

# Attachments
att_data = client.table('chat_attachments').select('*').eq('thread_id', thread_id).execute().data
attachments = [Attachment(
    id=r['id'], title=r['title'], content=r.get('content_text') or '', summary=r.get('summary') or '',
    sections=[], token_count=r.get('token_count') or 1000,
) for r in att_data]
visibility = plan_visibility(attachments)

# Router decision for this turn
decision = RouterDecision(
    intent="learning",
    reply_language="ja",
    needs_retrieval=False,
    needs_reasoning=False,
    thread_title=None,
)

# PreparedTurn exactly matching production state at Msg 18
turn = PreparedTurn(
    user_id=m18['user_id'],
    thread_id=thread_id,
    is_new_thread=False,
    thread_has_title=True,
    user_message_id=m18['id'],
    assistant_message_id="experiment-msg-19",
    content=m18['content'],
    selected_text=None,
    lecture_label=None,
    context_lecture_id=None,
    attachments=attachments,
    summary_blocks=[],
    summary_level2=[],
    history_rows=history_rows,
)

memory = ConversationMemory.from_blocks([], [])

# Build messages using the actual production function
# We will create baseline_messages and candidate_messages by temporarily swapping/customizing prompts

# Load current prompts
baseline_sys_raw = _load_prompt("chat_answer_prompt.txt")
turn_raw = _load_prompt("chat_answer_turn_prompt.txt")

# Candidate System Prompt
# Add Context Anchoring & Affirmative Missing-Info, and remove the unsolicited "easy next step" rule
candidate_sys_raw = baseline_sys_raw.replace(
    "- Close with high-energy encouragement and an inviting, easy next step so they feel totally supported, hyped, and ready to finish!",
    "- Close with high-energy encouragement and warmth so they feel totally supported, hyped, and ready to continue!"
)

# Insert the Context Anchoring section before HOW TO RESPOND
anchor_section = """### CONTEXT ANCHORING AND MISSING INFORMATION
- Resolving brief, fragmented, or pronoun-heavy messages:
  When the student's message is short, uses pronouns ("this", "that"), or omits the subject or object ("Will it be livelock?", "Next please", "Why is that?", "Is this correct?"), pause to identify what they are anchoring on before answering:
  1. An answer or reaction to a question or prompt you asked in your previous turn.
  2. The concept, mechanism, or example you just explained in the preceding message.
  3. The next item in an ongoing sequence, problem set, or topic-by-topic review (e.g., advancing through a lecture list).
  4. Specifically quoted/selected text, or a newly attached image or document.
  5. The content of the page or section currently open on screen.
  Ground your answer directly in that intended context (for example, if they are answering your question, first give clear, encouraging feedback on their answer before expanding; if they are advancing through a list or series, smoothly proceed to the next item in that sequence rather than stalling or repeating past items).

- When materials are missing:
  Only when the student explicitly asks you to find, verify, or quote information from their lecture or class materials and that specific topic is not present in the provided sources, state clearly and humbly that it isn't covered in what you can currently see, and offer to explain from core principles or look at additional notes. In ordinary conversation or concept explanations where the student did not ask to look up a lecture reference, never output unprompted search disclaimers.

"""

candidate_sys_raw = candidate_sys_raw.replace("### HOW TO RESPOND", anchor_section + "### HOW TO RESPOND")

def build_prompt_messages(sys_prompt_text: str):
    # System message
    system_template = _render_conditional_sections(sys_prompt_text, {
        "HAS_MEMORY": False,
        "HAS_NOTES": False,
        "HAS_STUDENT_MEMOS": False,
        "HAS_OPEN_QUESTIONS": False,
    })
    system = fill_placeholders(system_template, {
        "STUDENT_PROFILE": "",
        "STUDENT_MEMOS": "",
        "OPEN_QUESTIONS": "",
        "CONVERSATION_SUMMARY": "",
        "CONVERSATION_NOTES": "",
    })
    
    # Turn message
    screen_context = format_screen_context(
        turn.lecture_label, turn.selected_text, turn.screen_page, reply_quote=turn.reply_quote)
    attachments_text = render_for_answer(turn.attachments, visibility)
    ai_code_rule = render_ai_code_rule(turn.attachments)
    
    turn_template = _render_conditional_sections(turn_raw, {
        "HAS_SOURCES": False,
        "HAS_ATTACHMENTS": bool(attachments_text),
        "HAS_AI_CODE_RULE": bool(ai_code_rule),
        "HAS_SCREEN_CONTEXT": bool(screen_context),
        "HAS_LINK_NOTES": False,
    })
    turn_message = fill_placeholders(turn_template, {
        "SOURCES": format_sources_block([]),
        "ATTACHMENTS": attachments_text,
        "AI_CODE_RULE": ai_code_rule,
        "SCREEN_CONTEXT": screen_context,
        "LINK_NOTES": "",
        "REPLY_LANGUAGE": decision.reply_language,
        "MESSAGE": turn.message_for_prompt,
    })
    
    return [
        Message(role="system", content=system),
        *history,
        Message(role="user", content=turn_message, images=turn.answer_images)
    ]

async def run_single_test(name: str, messages: list[Message]):
    options = LLMOptions(max_tokens=2500, reasoning_effort="high")
    billing = BillingEngine(task_type="CHAT_ANSWER")
    llm = UnifiedLLM(billing)
    
    t0 = time.perf_counter()
    state = StreamState()
    output_parts = []
    thought_parts = []
    
    async def on_thought(chunk: str):
        thought_parts.append(chunk)

    async for delta in llm.generate_stream(
        ANSWER_MODEL, messages, state, options, on_thought=on_thought
    ):
        output_parts.append(delta)
            
    t1 = time.perf_counter()
    duration = t1 - t0
    collected_text = "".join(output_parts)
    collected_thought = "".join(thought_parts)
    cost_usd = billing.total_usd()
    
    return {
        "name": name,
        "duration_sec": round(duration, 2),
        "in_tokens": state.input_tokens,
        "out_tokens": state.output_tokens,
        "cost_usd": cost_usd,
        "response": collected_text,
        "thought": collected_thought,
    }

async def main():
    print("==================================================")
    print("MSG 18 EXPERIMENT (Advancing to next topic in sequence)")
    print(f"Target query: {m18['content']}")
    print("==================================================")
    
    results = []
    
    # Record Baseline Run 1 from actual thread
    b1_res = {
        "name": "Baseline Run 1 (Actual in DB)",
        "duration_sec": 7.69,
        "in_tokens": actual_m19.get("usage", {}).get("answer_input_tokens", 20781),
        "out_tokens": actual_m19.get("usage", {}).get("answer_output_tokens", 403),
        "cost_usd": 0.0022796,
        "response": actual_m19.get("content"),
        "thought": "(Actual production execution in DB - no thought logged)",
    }
    results.append(b1_res)
    print(f"\n[Baseline Run 1 (DB)] Out tokens: {b1_res['out_tokens']}, Cost: ${b1_res['cost_usd']:.5f}")
    
    # 1 additional Baseline run (Baseline Run 2)
    print("\n[Running Baseline - Run 2]...")
    baseline_msgs = build_prompt_messages(baseline_sys_raw)
    res_b2 = await run_single_test("Baseline Run 2", baseline_msgs)
    results.append(res_b2)
    print(f"Done in {res_b2['duration_sec']}s. Out tokens: {res_b2['out_tokens']}. Cost: ${res_b2['cost_usd']:.5f}")
    
    # 3 Candidate runs
    candidate_msgs = build_prompt_messages(candidate_sys_raw)
    for run_i in range(1, 4):
        print(f"\n[Running Candidate - Run {run_i}]...")
        res_c = await run_single_test(f"Candidate Run {run_i}", candidate_msgs)
        results.append(res_c)
        print(f"Done in {res_c['duration_sec']}s. Out tokens: {res_c['out_tokens']}. Cost: ${res_c['cost_usd']:.5f}")
        
    output_path = "contents_generation/test_codes/msg18_experiment_results.json"
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
        
    print(f"\nSaved all results to {output_path}!")

if __name__ == '__main__':
    asyncio.run(main())
