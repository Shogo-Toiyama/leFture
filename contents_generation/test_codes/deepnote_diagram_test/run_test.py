import asyncio
import os
import sys
import time
import json
import re
import argparse
from pathlib import Path
from dotenv import load_dotenv

# Load environment
base_dir = Path(__file__).resolve().parent
repo_root = base_dir.parents[2]
load_dotenv(repo_root / 'lefture_backend/.env')
sys.path.insert(0, str(repo_root / 'lefture_backend'))

from app.services.helpers.llm_unified import UnifiedLLM, BillingEngine, Message, LLMOptions

TEST_MODELS = [
    {
        "name": "Claude Haiku 5.5",
        "model_id": "anthropic/claude-haiku-5-5",
    }
]

REASONING_EFFORT = "low"
RUN_ID = "run_7_haiku_reasoning_low_no_cache"
ENABLE_CACHE = False

def load_prompt() -> str:
    with open(base_dir / 'prompt.txt', 'r', encoding='utf-8') as f:
        return f.read()

def load_test_cases() -> list:
    with open(base_dir / 'test_cases.json', 'r', encoding='utf-8') as f:
        return json.load(f)

def extract_html(raw_response: str) -> str:
    """Robustly extract HTML code block from Markdown response"""
    cleaned = raw_response.strip()
    if "```" in cleaned:
        match = re.search(r'```(?:html)?\s*\n(.*?)(?:\n```|$)', cleaned, re.DOTALL | re.IGNORECASE)
        if match:
            return match.group(1).strip()
    return cleaned

async def run_single_case(model_info: dict, case: dict, prompt_template: str, run_dir: Path, dry_run: bool = False):
    model_id = model_info['model_id']
    model_name = model_info['name']
    case_id = case['id']
    
    # Fill placeholders
    prompt = prompt_template
    prompt = prompt.replace('${FIGURE_TYPE}', case['figure_type'])
    prompt = prompt.replace('${TITLE}', case['title'])
    prompt = prompt.replace('${DESCRIPTION}', case['description'])
    prompt = prompt.replace('${SECTION_CONTEXT}', case['section_context'])
    
    # Message with or without cache
    if ENABLE_CACHE:
        messages = [Message(role="user", content=prompt, cache_control={"type": "ephemeral"})]
    else:
        messages = [Message(role="user", content=prompt)]
    
    print(f"[{model_name}] Starting {case_id} ({case['title']}) [Reasoning: {REASONING_EFFORT}, Cache: {ENABLE_CACHE}] (dry_run={dry_run})...")
    start_time = time.time()
    
    if dry_run:
        elapsed = 0.05
        p_tokens = len(prompt) // 4
        c_tokens = 250
        t_tokens = p_tokens + c_tokens
        cost_usd = 0.0001
        html_code = f"""<div class="deepnote-figure-card" style="background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:20px;box-shadow:0 2px 4px rgba(0,0,0,0.05);">
  <h3 style="margin:0 0 10px 0;color:#0f172a;font-size:16px;">{case['title']} [DRY RUN]</h3>
  <p style="color:#64748b;font-size:13px;line-height:1.5;">{case['description']}</p>
  <div style="margin-top:15px;padding:12px;background:#f8fafc;border-radius:8px;font-size:12px;color:#3b82f6;">
    Mock visual component for {case['figure_type']} (immersive domain)
  </div>
</div>"""
    else:
        billing = BillingEngine(task_type="DEEPNOTE_DIAGRAM_TEST")
        llm = UnifiedLLM(billing)
        options = LLMOptions(
            temperature=0.2,
            reasoning_effort=REASONING_EFFORT,
            max_completion_tokens=8000,
        )
        
        try:
            res = await llm.generate(model_id, messages, options)
            elapsed = time.time() - start_time
            raw_text = res.output_text or ""
            html_code = extract_html(raw_text)
            p_tokens = res.input_tokens
            c_tokens = res.output_tokens
            t_tokens = p_tokens + c_tokens
            cost_usd = billing.total_usd()
        except Exception as e:
            elapsed = time.time() - start_time
            print(f"[{model_name}] ERROR on {case_id}: {e}")
            return {
                "case_id": case_id,
                "title": case['title'],
                "type": case['figure_type'],
                "model_name": model_name,
                "model_id": model_id,
                "reasoning_effort": REASONING_EFFORT,
                "elapsed_seconds": elapsed,
                "cost_usd": 0.0,
                "usage": None,
                "html_path": None,
                "html_code": None,
                "error": str(e)
            }

    # Save individual HTML file with Paper World theme background
    safe_model_name = model_name.lower().replace(" ", "_").replace(".", "_")
    html_filename = f"{case_id}_{safe_model_name}.html"
    html_path = run_dir / html_filename
    
    standalone_html = f"""<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{case['title']} - {model_name}</title>
<style>
  body {{
    background-color: #FAF5E9; /* Orbit Paper World Background */
    color: #1e293b;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    padding: 24px 12px;
    margin: 0;
  }}
  .meta-bar {{
    max-width: 520px;
    margin: 0 auto 16px auto;
    font-size: 13px;
    color: #64748b;
    display: flex;
    justify-content: space-between;
    border-bottom: 1px solid #e2e8f0;
    padding-bottom: 8px;
  }}
  .card-container {{
    max-width: 520px;
    margin: 0 auto;
  }}
</style>
</head>
<body>
  <div class="meta-bar">
    <span><strong>{case['title']}</strong> ({case['figure_type']})</span>
    <span>{model_name} | {elapsed:.2f}s | {t_tokens} tok (${cost_usd:.5f})</span>
  </div>
  <div class="card-container">
    {html_code}
  </div>
</body>
</html>
"""
    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(standalone_html)
        
    print(f"[{model_name}] Finished {case_id} in {elapsed:.2f}s (Tokens: {t_tokens}, Cost: ${cost_usd:.5f}) -> {html_filename}")
    
    return {
        "case_id": case_id,
        "title": case['title'],
        "type": case['figure_type'],
        "model_name": model_name,
        "model_id": model_id,
        "reasoning_effort": REASONING_EFFORT,
        "elapsed_seconds": elapsed,
        "cost_usd": cost_usd,
        "usage": {
            "prompt_tokens": p_tokens,
            "completion_tokens": c_tokens,
            "total_tokens": t_tokens,
        },
        "html_path": str(html_path.relative_to(base_dir)),
        "html_code": html_code,
        "error": None
    }

def generate_gallery_html(results: list, cases: list, run_dir: Path):
    """Generate a clean gallery HTML for mobile-focused review"""
    gallery_path = run_dir / "preview_gallery.html"
    
    cards_html = []
    for case in cases:
        case_id = case['id']
        case_results = [r for r in results if r['case_id'] == case_id]
        
        for r in case_results:
            if r['error']:
                content = f"""<div style="color:#dc2626;padding:16px;">{r['error']}</div>"""
            else:
                content = r['html_code']
                
            stats = f"{r['elapsed_seconds']:.2f}s | {r['usage']['total_tokens']} tok | ${r['cost_usd']:.5f}" if not r['error'] else "FAILED"
            
            card_section = f"""
            <section class="case-card">
              <div class="case-header">
                <div>
                  <h2>{case['title']} <span class="badge {case['figure_type']}">{case['figure_type']}</span></h2>
                  <p class="case-desc">{case['description']}</p>
                </div>
                <div class="stats-pill">{stats}</div>
              </div>
              <div class="mobile-viewport">
                {content}
              </div>
            </section>
            """
            cards_html.append(card_section)
        
    full_gallery = f"""<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>DeepNote Diagram Test ({RUN_ID})</title>
<style>
  body {{
    background-color: #FAF5E9; /* Orbit Paper World */
    color: #1e293b;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    margin: 0;
    padding: 32px 16px;
  }}
  header {{
    max-width: 720px;
    margin: 0 auto 32px auto;
    border-bottom: 2px solid #e2e8f0;
    padding-bottom: 16px;
  }}
  h1 {{ margin: 0 0 8px 0; font-size: 22px; color: #0f172a; }}
  .case-card {{
    max-width: 720px;
    margin: 0 auto 40px auto;
    background: #ffffff;
    border-radius: 14px;
    border: 1px solid #e2e8f0;
    box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05);
    overflow: hidden;
  }}
  .case-header {{
    padding: 16px 20px;
    background: #f8fafc;
    border-bottom: 1px solid #e2e8f0;
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 16px;
  }}
  .case-header h2 {{ margin: 0 0 6px 0; font-size: 17px; color: #0f172a; display: flex; align-items: center; gap: 8px; }}
  .badge {{
    font-size: 11px;
    text-transform: uppercase;
    padding: 2px 7px;
    border-radius: 4px;
    font-weight: 600;
  }}
  .badge.diagram {{ background: #4f46e5; color: #fff; }}
  .badge.chart {{ background: #059669; color: #fff; }}
  .case-desc {{ margin: 0; color: #64748b; font-size: 13px; line-height: 1.45; }}
  .stats-pill {{
    background: #eef2ff;
    color: #4f46e5;
    padding: 4px 10px;
    border-radius: 999px;
    font-size: 12px;
    font-weight: 600;
    white-space: nowrap;
  }}
  .mobile-viewport {{
    background: #FAF5E9;
    padding: 24px 16px;
    display: flex;
    justify-content: center;
  }}
</style>
</head>
<body>
  <header>
    <h1>🏛️ DeepNotes Diagram Test ({RUN_ID})</h1>
    <p style="margin: 0; color: #64748b; font-size: 14px;">Claude Haiku 5.5 | Reasoning: LOW | No Cache | Clean Mobile-First Baseline</p>
  </header>
  {''.join(cards_html)}
</body>
</html>
"""
    with open(gallery_path, 'w', encoding='utf-8') as f:
        f.write(full_gallery)
    print(f"\n✨ Generated Gallery -> {gallery_path.relative_to(base_dir)}")

async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true', help='Run mock dry-run without calling APIs')
    args = parser.parse_args()
    
    prompt_template = load_prompt()
    cases = load_test_cases()
    
    folder_name = "dry_run" if args.dry_run else RUN_ID
    run_dir = base_dir / "results" / folder_name
    run_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"=== Starting DeepNote Diagram Test ({folder_name}) ===")
    print(f"Dry Run: {args.dry_run}")
    print(f"Models: {[m['name'] for m in TEST_MODELS]}")
    print(f"Cases: {len(cases)} cases")
    print(f"Reasoning Effort: {REASONING_EFFORT}")
    print(f"Prompt Caching: {ENABLE_CACHE}")
    print(f"Output Directory: {run_dir.relative_to(base_dir)}\n")
    
    all_results = []
    for model_info in TEST_MODELS:
        for case in cases:
            res = await run_single_case(model_info, case, prompt_template, run_dir, dry_run=args.dry_run)
            all_results.append(res)
            if not args.dry_run:
                await asyncio.sleep(0.5)
            
    summary_path = run_dir / "summary.json"
    with open(summary_path, 'w', encoding='utf-8') as f:
        clean_summary = [{k: v for k, v in r.items() if k != 'html_code'} for r in all_results]
        json.dump(clean_summary, f, ensure_ascii=False, indent=2)
        
    generate_gallery_html(all_results, cases, run_dir)
    print(f"\n✅ All steps finished successfully! Results saved to {run_dir.relative_to(base_dir)}")

if __name__ == '__main__':
    asyncio.run(main())
