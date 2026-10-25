import os
import sys
import json
import time
import argparse
import asyncio
from datetime import datetime
from typing import List, Dict, Any, Optional

# Add backend to path so we can import helpers
sys.path.insert(0, os.path.abspath("lefture_backend"))

from dotenv import load_dotenv
load_dotenv("lefture_backend/.env")

import litellm

# Model to test
MODEL_NAME = "anthropic/claude-haiku-5-5"

# Pricing (5-minute TTL test)
PRICE_INPUT = 0.10 / 1_000_000
PRICE_OUTPUT = 0.50 / 1_000_000
PRICE_CACHE_WRITE_5M = 0.125 / 1_000_000  # 1.25x
PRICE_CACHE_READ = 0.010 / 1_000_000       # 0.10x

PROMPT_DIR = "lefture_backend/app/services/prompts"

def load_prompt_file(name: str) -> str:
    path = os.path.join(PROMPT_DIR, name)
    with open(path, "r", encoding="utf-8") as f:
        return f.read()

def build_system_prompt_blocks(profile: str = "", memory_summary: str = "", use_cache: bool = True) -> List[Dict[str, Any]]:
    """
    Builds system prompt in 2 blocks:
      Block 1: Fixed base instructions from chat_answer_prompt.txt (~4,900 tokens) -> Breakpoint 1
      Block 2: Dynamic profile & summary blocks
    """
    base_instructions = load_prompt_file("chat_answer_prompt.txt")
    
    blocks = []
    # Block 1: Pure fixed instructions
    block1: Dict[str, Any] = {
        "type": "text",
        "text": base_instructions.strip(),
    }
    if use_cache:
        # Breakpoint 1 on the fixed instruction
        block1["cache_control"] = {"type": "ephemeral"}
    blocks.append(block1)
    
    # Block 2: Profile & Summary
    dynamic_parts = []
    if profile:
        dynamic_parts.append(f"<student_profile>\n{profile}\n</student_profile>")
    if memory_summary:
        dynamic_parts.append(f"<conversation_summary>\n{memory_summary}\n</conversation_summary>")
    
    if dynamic_parts:
        blocks.append({
            "type": "text",
            "text": "\n\n".join(dynamic_parts)
        })
        
    return blocks

def format_history_messages(history_rows: List[Dict[str, Any]], use_cache_on_last: bool = True) -> List[Dict[str, Any]]:
    """
    Formats past history turns.
    If use_cache_on_last is True, adds Breakpoint 2 on the last assistant message.
    """
    messages = []
    asst_indices = []
    
    for row in history_rows:
        role = row["role"]
        content = row.get("content") or ""
        messages.append({"role": role, "content": content})
        if role == "assistant":
            asst_indices.append(len(messages) - 1)
            
    if use_cache_on_last and asst_indices:
        last_idx = asst_indices[-1]
        asst_msg = messages[last_idx]
        asst_msg["content"] = [
            {
                "type": "text",
                "text": asst_msg["content"],
                "cache_control": {"type": "ephemeral"}
            }
        ]
        
    return messages

def build_test_turn_messages(
    system_blocks: List[Dict[str, Any]],
    history_messages: List[Dict[str, Any]],
    student_message: str,
    sources_text: Optional[str] = None
) -> List[Dict[str, Any]]:
    """
    Assembles the final litellm messages payload mirroring production chat_service.py.
    """
    messages = [{"role": "system", "content": system_blocks}]
    messages.extend(history_messages)
    
    # Last turn user message
    turn_parts = []
    if sources_text:
        turn_parts.append(f"<sources>\n{sources_text}\n</sources>")
    turn_parts.append(student_message)
    
    messages.append({
        "role": "user",
        "content": "\n\n".join(turn_parts)
    })
    return messages

async def run_step(step_name: str, messages: List[Dict[str, Any]], dry_run: bool = False) -> Dict[str, Any]:
    print(f"\n=======================================================")
    print(f"▶️ RUNNING: {step_name}")
    print(f"=======================================================")
    
    # Count tokens approx
    total_chars = sum(
        len(b.get("text", "")) if isinstance(m.get("content"), list) else len(m.get("content", ""))
        for m in messages
        for b in (m.get("content") if isinstance(m.get("content"), list) else [{"text": m.get("content", "")}])
    )
    print(f"Messages count: {len(messages)}, Approx total chars: {total_chars:,}")
    
    # Check cache breakpoints
    breakpoints = []
    for i, m in enumerate(messages):
        c = m.get("content")
        if isinstance(c, list):
            for bi, b in enumerate(c):
                if "cache_control" in b:
                    breakpoints.append(f"Msg #{i} ({m['role']}) block #{bi}: {b['cache_control']}")
    print(f"Active Cache Breakpoints ({len(breakpoints)}):")
    for bp in breakpoints:
        print(f"  📍 {bp}")
        
    if dry_run:
        print("🔍 [DRY-RUN] Validation passed. Skipping real API call.")
        return {
            "step_name": step_name,
            "dry_run": True,
            "breakpoints": breakpoints,
            "chars": total_chars
        }
        
    # Execute actual call (single call, measuring total latency and token usage)
    start_t = time.perf_counter()
    
    response = await litellm.acompletion(
        model=MODEL_NAME,
        messages=messages,
        max_tokens=600,
        temperature=1.0,
    )
    
    total_time = time.perf_counter() - start_t
    output_text = response.choices[0].message.content or ""
    usage = response.usage
    
    in_tokens = getattr(usage, "prompt_tokens", 0) or 0
    out_tokens = getattr(usage, "completion_tokens", 0) or 0
    details = getattr(usage, "prompt_tokens_details", None)
    
    # Anthropic usage fields
    read_tokens = int(getattr(details, "cached_tokens", 0) or getattr(usage, "cache_read_input_tokens", 0) or 0)
    write_tokens = int(getattr(details, "cache_creation_tokens", 0) or getattr(usage, "cache_creation_input_tokens", 0) or 0)
    
    uncached_in = max(0, in_tokens - read_tokens - write_tokens)
    cost = (
        (read_tokens * PRICE_CACHE_READ) +
        (write_tokens * PRICE_CACHE_WRITE_5M) +
        (uncached_in * PRICE_INPUT) +
        (out_tokens * PRICE_OUTPUT)
    )
    
    print(f"\n📊 [METRICS - {step_name}]")
    print(f"  Latency (Total Time): {total_time:.2f}s")
    print(f"  Input Tokens: {in_tokens:,} (Read: {read_tokens:,}, Write: {write_tokens:,}, Uncached: {uncached_in:,})")
    print(f"  Output Tokens: {out_tokens:,}")
    print(f"  Estimated Cost: ${cost:.6f}")
    print(f"  Sample Output: {output_text[:120].replace(chr(10), ' ')}...")
    
    return {
        "step_name": step_name,
        "latency_s": total_time,
        "input_tokens": in_tokens,
        "read_tokens": read_tokens,
        "write_tokens": write_tokens,
        "uncached_input": uncached_in,
        "output_tokens": out_tokens,
        "cost_usd": cost,
        "output_sample": output_text[:200]
    }

async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="Validate payload without making real API calls")
    args = parser.parse_args()
    
    # Load extracted raw cases
    cases_file = "contents_generation/test_codes/prompt_caching_test/cases/raw_cases.json"
    with open(cases_file, "r", encoding="utf-8") as f:
        raw_cases = json.load(f)
        
    thread_dhcp = raw_cases["6a3080e4-3eb0-4c0a-af46-f77cdd6ad769"]["messages"]
    thread_async = raw_cases["ba9a18c9-6fec-42ac-9fcc-416554d574cb"]["messages"]
    
    # Profile & mock summaries
    profile = "Student: CS major, interested in systems and networking."
    
    results = []
    
    # ----------------------------------------------------
    # STEP 1: Thread A (DHCP) - Turn 1 (Cold Start)
    # ----------------------------------------------------
    # Question: "DHCPって授業でやったっけ？"
    sys_blocks_1 = build_system_prompt_blocks(profile=profile, use_cache=True)
    msgs_step1 = build_test_turn_messages(
        system_blocks=sys_blocks_1,
        history_messages=[],
        student_message="DHCPって授業でやったっけ？",
        sources_text="[Topic: Network Layer & DHCP] Lecture 12: DHCP dynamic host configuration..."
    )
    res1 = await run_step("Step 1: Thread A Turn 1 (Cold Cache Write)", msgs_step1, dry_run=args.dry_run)
    results.append(res1)
    
    # ----------------------------------------------------
    # STEP 2: Thread A (DHCP) - Turn 2 (Continuous Turn)
    # ----------------------------------------------------
    # History: Turn 1 (User + Assistant)
    # Question: "今何時かわかる？"
    history_step2 = format_history_messages([
        {"role": "user", "content": "DHCPって授業でやったっけ？"},
        {"role": "assistant", "content": "はい、第12回の講義でDHCPについて扱っていますよ！端末が自動でIPアドレスを取得する仕組みです。"}
    ], use_cache_on_last=True)
    
    msgs_step2 = build_test_turn_messages(
        system_blocks=sys_blocks_1,
        history_messages=history_step2,
        student_message="今何時かわかる？"
    )
    res2 = await run_step("Step 2: Thread A Turn 2 (Warm Cache Hit on History)", msgs_step2, dry_run=args.dry_run)
    results.append(res2)
    
    # ----------------------------------------------------
    # STEP 3: Thread B (Async Sampling) - Turn 1 (New Thread / Cross-Thread Hit)
    # ----------------------------------------------------
    # New thread on CS118 async sampling
    # Question: "非同期通信とビットのサンプリングの基本を教えて"
    sys_blocks_b = build_system_prompt_blocks(profile=profile, use_cache=True)
    msgs_step3 = build_test_turn_messages(
        system_blocks=sys_blocks_b,
        history_messages=[],
        student_message="非同期通信とビットのサンプリングの基本を教えて",
        sources_text="[Topic: Physical Layer Sampling] Clock skew and baud rate synchronization..."
    )
    res3 = await run_step("Step 3: Thread B Turn 1 (Cross-Thread Hit on Fixed Prompt)", msgs_step3, dry_run=args.dry_run)
    results.append(res3)
    
    # ----------------------------------------------------
    # STEP 4: Thread A - Turn 3 (Intentional Miss / Historical Rollback Edit)
    # ----------------------------------------------------
    # Replicating real deletion/edit in DB:
    # History is altered (Turn 1 assistant answer re-generated differently)
    history_step4_altered = format_history_messages([
        {"role": "user", "content": "DHCPって授業でやったっけ？"},
        {"role": "assistant", "content": "[EDITED ANSWER] DHCPは第12回と第13回の両方で詳しく解説されています。"}
    ], use_cache_on_last=True)
    
    msgs_step4 = build_test_turn_messages(
        system_blocks=sys_blocks_1,
        history_messages=history_step4_altered,
        student_message="じゃあ、明日の朝やるために、先週の授業の重要ポイント一覧がみたい！",
        sources_text="[Topic: Review Points] Bridges, Spanning Tree, IP Routing summary..."
    )
    res4 = await run_step("Step 4: Thread A Turn 3 (History Altered / Intentional Miss)", msgs_step4, dry_run=args.dry_run)
    results.append(res4)
    
    # Save results
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_json = f"contents_generation/test_codes/prompt_caching_test/results/run_{timestamp}.json"
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print(f"\nSaved execution results to: {out_json}")

if __name__ == "__main__":
    asyncio.run(main())
