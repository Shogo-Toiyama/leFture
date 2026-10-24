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
    ROUTER_MODEL,
    INTENTS,
    build_history_messages,
    format_router_conversation,
    format_screen_context,
    fill_placeholders,
    _load_prompt,
    PreparedTurn,
)
from supabase import create_client

client = create_client(os.environ['SUPABASE_URL'], os.environ['SUPABASE_SECRET_KEY'])
thread_id = 'b70b7b26-21d3-4e56-944b-459411578cd1'

all_msgs = client.table('chat_messages').select('*').eq('thread_id', thread_id).order('created_at').execute().data

# Msg 16 is the target message
target_m = all_msgs[16]
assert 'データリンク層（フレーム・誤り検出・符号化）に進みたい' in target_m['content']

history_rows = all_msgs[:16] # All messages up to Msg 15
history = build_history_messages(history_rows, max_turns=20, max_chars=3000)

ROUTER_SCHEMA_WITH_GOAL = {
    "type": "object",
    "properties": {
        "intent": {"type": "string", "enum": list(INTENTS)},
        "user_goal": {
            "type": "string",
            "description": "1-2 concise sentences in English capturing context anchor, student's request, and what a successful response accomplishes. Never invent or assume external lecture materials/topics not mentioned in the inputs.",
        },
        "retrieval_reason": {
            "type": "string",
            "description": "Brief explanation (1 sentence) of whether lecture retrieval is needed and why.",
        },
        "needs_retrieval": {"type": "boolean"},
        "needs_reasoning": {"type": "boolean"},
        "reply_language": {"type": "string"},
        "thread_title": {"type": ["string", "null"]},
    },
    "required": [
        "intent",
        "user_goal",
        "retrieval_reason",
        "needs_retrieval",
        "needs_reasoning",
        "reply_language",
        "thread_title",
    ],
}

candidate_router_prompt = _load_prompt("chat_router_prompt.txt").replace(
    "- `retrieval_reason`: exactly one concise sentence explaining why lecture retrieval is or is not needed.",
    """- `user_goal`: exactly 1-2 concise sentences in English capturing the student's true goal for this turn:
  1. Anchor: What context they are anchoring on (the preceding AI turn/quiz, an ongoing sequence/list in chat, the open screen page, an attached document, or a standalone question).
  2. Resolving ambiguity & pronouns: If the student uses pronouns ("this", "that") or vague references ("next topic", "next one", "proceed"), resolve exactly WHAT specific concept, item, or topic from the recent conversation or list they are pointing to (e.g. name the specific next item from the list, such as "Topic 4 (Reliable Data Transfer / Clock recovery)"), rather than just leaving it as a vague "the next topic". Never invent external materials or topics not present in the inputs.
  3. Request: What they are actually asking, guessing, or doing right now.
  4. Desired outcome: What a successful response achieves (e.g. validating their understanding, answering their specific sub-questions, confirming readiness to advance to the specified next item, or offering genuine warmth/empathy).
  For casual chat, personal topics, or emotional venting, keep it simple, warm, and natural (e.g. "Sharing academic stress about multiple deadlines; seeks empathetic listening and encouragement") rather than over-analyzing.
- `retrieval_reason`: exactly one concise sentence explaining why lecture retrieval is or is not needed."""
)

user_input = fill_placeholders(_load_prompt("chat_router_input_prompt.txt"), {
    "EARLIER_CONVERSATION": "(none)",
    "RECENT_CONVERSATION": format_router_conversation(history) if history else "(none)",
    "SCREEN_CONTEXT": "(none)",
    "COURSES": "CS 118: Computer Network Architecture (Fall 2025)",
    "ATTACHMENTS": "(none)",
    "IS_FIRST_MESSAGE": "false",
    "NEW_MESSAGE": target_m['content'],
})

async def run_trial(run_i: int):
    billing = BillingEngine(task_type="CHAT_ROUTER")
    llm = UnifiedLLM(billing)
    options = LLMOptions(output_type="json", json_schema=ROUTER_SCHEMA_WITH_GOAL, temperature=0.0)
    messages = [
        Message(role="system", content=candidate_router_prompt),
        Message(role="user", content=user_input),
    ]
    t0 = time.perf_counter()
    res = await llm.generate(ROUTER_MODEL, messages, options)
    dur = time.perf_counter() - t0
    cost = billing.total_usd()
    return {
        "run": run_i,
        "duration": round(dur, 3),
        "cost": cost,
        "in_tokens": res.input_tokens,
        "out_tokens": res.output_tokens,
        "output": res.output_json,
    }

async def main():
    print("==================================================")
    print("MSG 16 LONG REVIEW TURN EXPERIMENT (3 Runs)")
    print("==================================================")
    results = []
    for i in range(1, 4):
        r = await run_trial(i)
        results.append(r)
        out = r["output"] or {}
        print(f"\n[Run {i}] ({r['duration']}s, ${r['cost']:.5f})")
        print(f"  Intent:    {out.get('intent')}")
        print(f"  Goal:      \"{out.get('user_goal')}\"")
        print(f"  Retrieval: {out.get('needs_retrieval')} ({out.get('retrieval_reason')})")
        print(f"  Reasoning: {out.get('needs_reasoning')}")
        
    with open("contents_generation/test_codes/msg16_experiment_results.json", "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

if __name__ == '__main__':
    asyncio.run(main())
