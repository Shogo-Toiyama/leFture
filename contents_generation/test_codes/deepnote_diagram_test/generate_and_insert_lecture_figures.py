import os
import sys
import asyncio
import time
from dotenv import load_dotenv

# load env from lefture_backend/.env
backend_env = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../lefture_backend/.env"))
load_dotenv(backend_env)

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../lefture_backend")))

from supabase import create_client
from app.services.helpers.llm_unified import BillingEngine, UnifiedLLM
from app.services.helpers.helpers import TaskLogger
from app.services.logic.figure_generation import FigureGenerationService

async def main():
    supabase_url = os.environ["SUPABASE_URL"]
    supabase_key = os.environ["SUPABASE_SECRET_KEY"]
    supabase = create_client(supabase_url, supabase_key)

    lecture_id = "aa5646f7-f693-4199-a77c-3e2aafed13de"

    # 1. Fetch lecture details
    lec_res = supabase.table("lectures").select("id, user_id, title").eq("id", lecture_id).execute()
    if not lec_res.data:
        print(f"❌ Lecture {lecture_id} not found!")
        return
    user_id = lec_res.data[0]["user_id"]
    print(f"Lecture: {lecture_id}, User: {user_id}")

    # 2. Fetch deep_notes
    notes_res = supabase.table("deep_notes").select("topic_number, note_contents").eq("lecture_id", lecture_id).order("topic_number").execute()
    notes = notes_res.data or []
    print(f"Fetched {len(notes)} notes.")

    # 3. Setup FigureGenerationService
    billing = BillingEngine(task_type="FIGURE_GENERATION")
    logger = TaskLogger(user_id, lecture_id, "FIGURE_GENERATION")
    llm = UnifiedLLM(billing)
    service = FigureGenerationService(llm, logger)

    start_time = time.time()
    figures = await service.run_for_notes(notes)
    elapsed = time.time() - start_time

    print(f"\n==========================================")
    print(f"✨ Generation Completed in {elapsed:.2f}s")
    print(f"Generated {len(figures)} figures:")
    for f in figures:
        print(f"  - Topic {f['topic_number']}, Fig #{f['figure_index'] + 1}: {f['title']} ({f['figure_type']}) - HTML len: {len(f['html_content'])} chars")
    print(f"==========================================")

    # 4. Insert into deep_note_figures table
    if figures:
        print(f"\nSaving to Supabase 'deep_note_figures' table...")
        # Clear existing figures for this lecture to ensure idempotency
        supabase.table("deep_note_figures").delete().eq("lecture_id", lecture_id).execute()

        rows = [
            {
                "user_id": user_id,
                "lecture_id": lecture_id,
                "topic_number": f["topic_number"],
                "figure_index": f["figure_index"],
                "figure_type": f["figure_type"],
                "title": f["title"],
                "description": f["description"],
                "html_content": f["html_content"],
            }
            for f in figures
        ]
        insert_res = supabase.table("deep_note_figures").insert(rows).execute()
        print(f"✅ Successfully inserted {len(insert_res.data)} records into deep_note_figures!")

    # 5. Billing & Token metrics report
    print("\n--- Billing / Token Metrics ---")
    total_in = 0
    total_out = 0
    total_cost = 0.0
    for rec in billing.records:
        total_in += rec.input_tokens
        total_out += rec.output_tokens
        total_cost += rec.cost_usd
        print(f"  Model: {rec.model} | In: {rec.input_tokens} tokens | Out: {rec.output_tokens} tokens | Cost: ${rec.cost_usd:.6f}")
    print(f"Total: Input {total_in} tokens, Output {total_out} tokens, Total Cost: ${total_cost:.5f}")

if __name__ == "__main__":
    asyncio.run(main())
