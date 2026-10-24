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
    ScreenPage,
    Attachment,
    PreparedTurn,
)
from supabase import create_client

client = create_client(os.environ['SUPABASE_URL'], os.environ['SUPABASE_SECRET_KEY'])
thread_id = 'b70b7b26-21d3-4e56-944b-459411578cd1'

# Fetch thread messages for realistic history
all_msgs = client.table('chat_messages').select('*').eq('thread_id', thread_id).order('created_at').execute().data

# Schema with user_goal
ROUTER_SCHEMA_WITH_GOAL = {
    "type": "object",
    "properties": {
        "intent": {"type": "string", "enum": list(INTENTS)},
        "user_goal": {
            "type": "string",
            "description": "1-2 concise sentences in English capturing context anchor, student's request, and what a successful response accomplishes. For casual chat or feelings, keep it simple and natural.",
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

# Candidate Router Prompt with user_goal instruction
candidate_router_prompt = _load_prompt("chat_router_prompt.txt").replace(
    "- `retrieval_reason`: exactly one concise sentence explaining why lecture retrieval is or is not needed.",
    """- `user_goal`: exactly 1-2 concise sentences in English capturing the student's true goal for this turn:
  1. Anchor: What context they are anchoring on (the preceding AI turn/quiz, an ongoing sequence/list in chat, the open screen page, an attached document, or a standalone question). Never invent or assume external lecture materials/topics not mentioned in the inputs.
  2. Request: What they are actually asking, guessing, or doing.
  3. Desired outcome: What a successful response achieves (e.g. validating their guess, confirming they can advance to the next item in the sequence, explaining the core intuition, or offering genuine warmth/empathy).
  For casual chat, personal topics, or emotional venting, keep it simple, warm, and natural (e.g. "Sharing academic stress about multiple deadlines; seeks empathetic listening and encouragement") rather than over-analyzing.
- `retrieval_reason`: exactly one concise sentence explaining why lecture retrieval is or is not needed."""
)

# 5 Scenarios
scenarios = [
    {
        "id": 1,
        "name": "Scenario 1: Quiz Answer (ライブロックになる？)",
        "message": "ライブロックになる？",
        "history_rows": all_msgs[:60], # Up to Msg 59 (quiz turn)
        "screen_page": ScreenPage(
            kind="deep_note", lecture_id="fa43feba-7b95-437d-8a43-c1c43141f079",
            topic_number=5, title='Deep Note "無線LANの隠れ端末とRTS/CTS"',
            text="...",
        ),
        "lecture_label": "Network Fundamental / 共有ネットワークのアクセス制御とスイッチング",
        "selected_text": None,
        "is_first": False,
    },
    {
        "id": 2,
        "name": "Scenario 2: Sequence Advance (単語まとめ追いかけ中、次に行っていい？)",
        "message": "あ、今前君があげてくれた単語まとめを上から順番に追いかけてるの。次に行っていいかな？",
        "history_rows": all_msgs[:18], # Up to Msg 17
        "screen_page": None,
        "lecture_label": None,
        "selected_text": None,
        "is_first": False,
    },
    {
        "id": 3,
        "name": "Scenario 3: Screen Context / Ask AI (これってどういうこと？)",
        "message": "これってどういうこと？図の意味がちょっとよく分かんないかも",
        "history_rows": all_msgs[:50],
        "screen_page": ScreenPage(
            kind="deep_note", lecture_id="fa43feba-7b95-437d-8a43-c1c43141f079",
            topic_number=5, title='Deep Note "無線LANの隠れ端末とRTS/CTS"',
            text="...",
        ),
        "lecture_label": "Network Fundamental / 共有ネットワークのアクセス制御とスイッチング",
        "selected_text": "隠れ端末問題とRTS/CTSハンドシェイクのタイムライン図",
        "is_first": False,
    },
    {
        "id": 4,
        "name": "Scenario 4: Emotional Venting (課題多すぎてパンクしそう)",
        "message": "最近課題が多すぎてマジでパンクしそう…もう嫌だー！",
        "history_rows": [],
        "screen_page": None,
        "lecture_label": None,
        "selected_text": None,
        "is_first": True,
    },
    {
        "id": 5,
        "name": "Scenario 5: Progress Sharing (ロボコン機体テスト動いた！)",
        "message": "今日サークルのロボコンの機体テスト動いたんだよ！！",
        "history_rows": [],
        "screen_page": None,
        "lecture_label": None,
        "selected_text": None,
        "is_first": True,
    },
]

async def run_router_test(scen: dict, run_idx: int):
    billing = BillingEngine(task_type="CHAT_ROUTER")
    llm = UnifiedLLM(billing)
    
    # Build history (using production RAW_MAX_TURNS = 20)
    history = build_history_messages(scen["history_rows"], max_turns=20, max_chars=3000)
    
    screen_ctx = format_screen_context(
        scen["lecture_label"], scen["selected_text"], scen["screen_page"], full_page=False,
    ) or "(none)"
    
    user_input = fill_placeholders(_load_prompt("chat_router_input_prompt.txt"), {
        "EARLIER_CONVERSATION": "(none)",
        "RECENT_CONVERSATION": format_router_conversation(history) if history else "(none)",
        "SCREEN_CONTEXT": screen_ctx,
        "COURSES": "CS 118: Computer Network Architecture (Fall 2025)",
        "ATTACHMENTS": "(none)",
        "IS_FIRST_MESSAGE": "true" if scen["is_first"] else "false",
        "NEW_MESSAGE": scen["message"],
    })
    
    options = LLMOptions(output_type="json", json_schema=ROUTER_SCHEMA_WITH_GOAL, temperature=0.0)
    messages = [
        Message(role="system", content=candidate_router_prompt),
        Message(role="user", content=user_input),
    ]
    
    t0 = time.perf_counter()
    result = await llm.generate(ROUTER_MODEL, messages, options)
    duration = time.perf_counter() - t0
    
    cost_usd = billing.total_usd()
    
    return {
        "scenario_id": scen["id"],
        "scenario_name": scen["name"],
        "run_idx": run_idx,
        "duration_sec": round(duration, 3),
        "in_tokens": result.input_tokens,
        "out_tokens": result.output_tokens,
        "cost_usd": cost_usd,
        "output": result.output_json,
    }

async def main():
    print("==================================================")
    print("ROUTER USER_GOAL EXPERIMENT (5 Scenarios x 3 Runs)")
    print("==================================================")
    
    all_results = []
    
    for scen in scenarios:
        print(f"\n--- Testing {scen['name']} ---")
        scen_runs = []
        for run_i in range(1, 4):
            res = await run_router_test(scen, run_i)
            scen_runs.append(res)
            all_results.append(res)
            out = res["output"] or {}
            print(f"  Run {run_i} ({res['duration_sec']}s, ${res['cost_usd']:.5f}):")
            print(f"    Intent: {out.get('intent')}")
            print(f"    Goal:   \"{out.get('user_goal')}\"")
            print(f"    Retrieval: {out.get('needs_retrieval')} ({out.get('retrieval_reason')})")
            print(f"    Reasoning: {out.get('needs_reasoning')}")
            
    output_path = "contents_generation/test_codes/router_goal_experiment_results.json"
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(all_results, f, ensure_ascii=False, indent=2)
        
    print(f"\nSaved all results to {output_path}!")

if __name__ == '__main__':
    asyncio.run(main())
