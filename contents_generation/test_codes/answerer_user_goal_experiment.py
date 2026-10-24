import asyncio
import os
import sys
import time
import json
from dotenv import load_dotenv

load_dotenv('lefture_backend/.env')
sys.path.insert(0, 'lefture_backend')

from app.services.helpers.llm_unified import BillingEngine, UnifiedLLM, Message, LLMOptions
from app.services.chat_service import (
    ANSWER_MODEL, # "anthropic/claude-haiku-5-5"
    build_history_messages,
    fill_placeholders,
    _load_prompt,
    _render_conditional_sections,
    render_ai_code_rule,
    format_sources_block,
    Material,
)
from supabase import create_client

client = create_client(os.environ['SUPABASE_URL'], os.environ['SUPABASE_SECRET_KEY'])
thread_id = 'b70b7b26-21d3-4e56-944b-459411578cd1'

all_msgs = client.table('chat_messages').select('*').eq('thread_id', thread_id).order('created_at').execute().data

# Test Scenarios with actual user_goals from router experiment
SCENARIOS = {
    16: {
        "name": "Turn 16 (Multi-concept review + Advance)",
        "user_goal": "The student wants to understand the concepts of framing, bit stuffing, CRC, and line coding within the Data Link Layer. They have specific questions about bit stuffing (insertion of 0, global consistency), CRC (error detection limitations, recovery, and consequences of undetected errors), and line coding (efficiency of 4B5B vs. Manchester coding). They also want to confirm their understanding of clock recovery. They are asking for clarification and confirmation of their understanding, and if their understanding is good, they want to move to the next topic.",
    },
    18: {
        "name": "Turn 18 (Clarify list sequence + Can I advance?)",
        "user_goal": "The student wants to continue reviewing the concepts from the provided summary, moving on to the next topic in the list. They are asking for confirmation to proceed.",
    }
}

def build_answerer_payload(target_idx: int):
    target_m = all_msgs[target_idx]
    scenario = SCENARIOS[target_idx]
    history_rows = all_msgs[:target_idx]
    
    # 1. Full uncompressed history messages
    history = build_history_messages(history_rows, max_turns=len(history_rows), max_chars=1200)
    
    # 2. System prompt
    sys_prompt = _load_prompt("chat_answer_prompt.txt")
    sys_prompt = fill_placeholders(sys_prompt, {
        "STUDENT_PROFILE": "(The student has not shared any profile information yet.)",
        "CONVERSATION_NOTES": "(none)",
    })
    
    # 3. Turn prompt with <user_goal> injected
    turn_raw = _load_prompt("chat_answer_turn_prompt.txt")
    
    # Insert <user_goal> right before <how_to_write_this_reply>
    if "<user_goal>" not in turn_raw:
        turn_raw = turn_raw.replace(
            "<how_to_write_this_reply>",
            f"<user_goal>\n{scenario['user_goal']}\n</user_goal>\n\n<how_to_write_this_reply>"
        )
        
    turn_prompt = fill_placeholders(turn_raw, {
        "MESSAGE": target_m['content'],
        "REPLY_LANGUAGE": "ja",
        "SCREEN_CONTEXT": "(none)",
        "ATTACHMENTS": "(none)",
        "SOURCES": "(No materials were retrieved for this message.)",
        "LINK_NOTES": "",
        "AI_CODE_RULE": "",
    })
    turn_prompt = _render_conditional_sections(turn_prompt, {
        "HAS_SCREEN_CONTEXT": False,
        "HAS_ATTACHMENTS": False,
        "HAS_SOURCES": False,
        "HAS_LINK_NOTES": False,
        "HAS_AI_CODE_RULE": False,
    })
    
    messages = [
        Message(role="system", content=sys_prompt),
        *history,
        Message(role="user", content=turn_prompt),
    ]
    
    return {
        "target_idx": target_idx,
        "scenario_name": scenario["name"],
        "user_goal": scenario["user_goal"],
        "model": ANSWER_MODEL,
        "total_messages": len(messages),
        "history_turn_count": len(history) // 2,
        "messages": messages,
    }

EXECUTE = True

async def run_scenario(idx: int):
    payload = build_answerer_payload(idx)
    print(f"\n=================================================================")
    print(f"RUNNING SCENARIO: Turn {idx} - {payload['scenario_name']}")
    print(f"User Goal:\n  \"{payload['user_goal']}\"")
    print(f"=================================================================")
    
    billing = BillingEngine(task_type="CHAT_ANSWER")
    llm = UnifiedLLM(billing)
    options = LLMOptions(temperature=0.7)
    
    t0 = time.perf_counter()
    res = await llm.generate(payload["model"], payload["messages"], options)
    dur = time.perf_counter() - t0
    cost = billing.total_usd()
    
    print(f"\n[Turn {idx} Reply] ({dur:.2f}s, ${cost:.5f}) | In: {res.input_tokens}, Out: {res.output_tokens}")
    print("-----------------------------------------------------------------")
    print(res.output_text)
    print("-----------------------------------------------------------------")
    return {
        "turn": idx,
        "scenario": payload["scenario_name"],
        "user_goal": payload["user_goal"],
        "duration": round(dur, 2),
        "cost": cost,
        "input_tokens": res.input_tokens,
        "output_tokens": res.output_tokens,
        "reply": res.output_text,
    }

async def main():
    print("=================================================================")
    print("ANSWERER (Claude Haiku 5.5) EXPERIMENT EXECUTION")
    print(f"Target Model: {ANSWER_MODEL}")
    print("=================================================================")
    results = []
    for idx in [16, 18]:
        r = await run_scenario(idx)
        results.append(r)
        
    with open("contents_generation/test_codes/answerer_user_goal_results.json", "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

if __name__ == '__main__':
    asyncio.run(main())
