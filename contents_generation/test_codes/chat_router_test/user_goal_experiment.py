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
    fill_placeholders,
    _load_prompt,
)
from supabase import create_client

client = create_client(os.environ['SUPABASE_URL'], os.environ['SUPABASE_SECRET_KEY'])
thread_id = 'b70b7b26-21d3-4e56-944b-459411578cd1'

all_msgs = client.table('chat_messages').select('*').eq('thread_id', thread_id).order('created_at').execute().data

# Custom history formatter: show all uncompressed messages up to max_chars per message
def format_full_history(history: list[Message], max_chars_per_msg: int = 1200) -> str:
    if not history:
        return "(this is the first message of the conversation)"
    return "\n\n".join(
        f"{'Student' if m.role == 'user' else 'Assistant'}: {m.content[:max_chars_per_msg]}"
        for m in history
    )

ROUTER_SCHEMA_WITH_GOAL = {
    "type": "object",
    "properties": {
        "intent": {"type": "string", "enum": list(INTENTS)},
        "user_goal": {
            "type": "string",
            "description": "Clear, self-contained goal statement explaining the student's actual intent. Captures context anchor, requests, multi-intent components, and what a successful response accomplishes.",
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

generalized_user_goal_prompt = """- `user_goal`: Formulate a clear, self-contained statement in English capturing the student's true goal for this turn:
  - Broad Context & Anchor Resolution:
    * Do not get tunnel-visioned on the most recent 1-2 turns. Look holistically across all visible context (earlier turns, shared materials, screen context, and recent replies) to resolve pronouns ("this", "that"), time references ("earlier", "before"), and progression requests ("next", "continue").
    * Explicitly identify the specific concept, problem, code, or item they are pointing to.
    * STRICT: Never hallucinate or invent specific anchors, names, or items that lack explicit evidence in the visible inputs. If the target is genuinely ambiguous or unspecified, state that it is unspecified.
  - Multi-Intent Handling:
    * Students often combine multiple intents in one turn (e.g., reporting progress + asking a question, stating a reasoning + asking to advance, sharing an observation + requesting advice).
    * Never discard one part in favor of another — capture all distinct requests and questions so the response can address every aspect.
  - Request & Desired Outcome:
    * State what the student is asking, doing, or feeling, and what a complete, satisfying turn achieves (e.g., verifying comprehension, answering specific questions, performing requested operations, confirming readiness to proceed, or offering empathetic reassurance).
    * Detailed when multifaceted; concise when simple.
- `retrieval_reason`: exactly one concise sentence explaining why lecture retrieval is or is not needed."""

candidate_router_prompt = _load_prompt("chat_router_prompt.txt").replace(
    "- `retrieval_reason`: exactly one concise sentence explaining why lecture retrieval is or is not needed.",
    generalized_user_goal_prompt
)

async def run_trial(run_idx: int):
    target_idx = 18
    target_m = all_msgs[target_idx]
    history_rows = all_msgs[:target_idx]
    history = build_history_messages(history_rows, max_turns=len(history_rows), max_chars=3000)
    formatted_history = format_full_history(history, max_chars_per_msg=1200)

    user_input = fill_placeholders(_load_prompt("chat_router_input_prompt.txt"), {
        "EARLIER_CONVERSATION": "(none)",
        "RECENT_CONVERSATION": formatted_history,
        "SCREEN_CONTEXT": "(none)",
        "COURSES": "CS 118: Computer Network Architecture (Fall 2025)",
        "ATTACHMENTS": "(none)",
        "IS_FIRST_MESSAGE": "false",
        "NEW_MESSAGE": target_m['content'],
    })

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
    out = res.output_json or {}

    print(f"\n-------------------------------------------------------")
    print(f"[Run {run_idx}] Latency: {dur:.3f}s | Cost: ${cost:.6f} | Tokens: In={res.input_tokens}, Out={res.output_tokens}")
    print(f"Intent:           {out.get('intent')}")
    print(f"Needs Retrieval:  {out.get('needs_retrieval')}")
    print(f"Retrieval Reason: {out.get('retrieval_reason')}")
    print(f"Needs Reasoning:  {out.get('needs_reasoning')}")
    print(f"User Goal:\n  \"{out.get('user_goal')}\"")
    print(f"-------------------------------------------------------")
    return {
        "run": run_idx,
        "duration": round(dur, 3),
        "cost": cost,
        "input_tokens": res.input_tokens,
        "output_tokens": res.output_tokens,
        "output": out,
    }

async def main():
    print("=======================================================")
    print("TURN 18 EXPERIMENT (3 Runs with Generalized user_goal)")
    target_m = all_msgs[18]
    print(f"Target Msg 18 Content:\n\"{target_m['content']}\"")
    print("=======================================================")
    
    results = []
    for i in range(1, 4):
        r = await run_trial(i)
        results.append(r)
        
    with open("contents_generation/test_codes/turn18_generalized_results.json", "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

if __name__ == '__main__':
    asyncio.run(main())
