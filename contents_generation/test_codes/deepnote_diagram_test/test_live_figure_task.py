import asyncio
import os
import sys
from pathlib import Path
from dotenv import load_dotenv

# Setup path and env
backend_dir = Path(__file__).resolve().parents[3] / "lefture_backend"
sys.path.insert(0, str(backend_dir))
load_dotenv(backend_dir / ".env")

from supabase import create_client
from app.services.logic.figure_generation import FigureGenerationService
from app.services.helpers.helpers import TaskLogger
from app.services.helpers.llm_unified import UnifiedLLM, BillingEngine

async def run_live_test():
    print("=== Testing Figure Generation on Real Lecture Notes ===")
    supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    
    # Target lecture with figure tags
    lecture_id = "a0c569a9-5c72-4ef9-a61d-ccd1911ecb05"
    
    # 1. Fetch deep_notes
    res = supabase.table("deep_notes").select("topic_number, note_contents").eq("lecture_id", lecture_id).order("topic_number").execute()
    notes = res.data or []
    print(f"Fetched {len(notes)} deep note topics.")

    # 2. Get lecture owner user_id
    lec_res = supabase.table("lectures").select("user_id").eq("id", lecture_id).single().execute()
    user_id = lec_res.data["user_id"]
    print(f"Lecture Owner User ID: {user_id}")

    # 3. Setup service and run
    logger = TaskLogger(user_id, lecture_id, "FIGURE_LIVE_TEST")
    billing = BillingEngine("FIGURE_GENERATION")
    llm = UnifiedLLM(billing)
    service = FigureGenerationService(llm, logger)

    figures = await service.run_for_notes(notes)
    print(f"\n🎉 Successfully generated {len(figures)} figures:")
    for f in figures:
        print(f" - Topic {f['topic_number']} Fig {f['figure_index']} ({f['title']}): {f['figure_type']} | HTML length {len(f['html_content'])} | Elapsed: {f.get('elapsed_seconds', 0):.2f}s")

    # 4. Save to deep_note_figures
    print("\n📝 Saving to database (deep_note_figures)...")
    # Delete existing test rows
    supabase.table("deep_note_figures").delete().eq("lecture_id", lecture_id).execute()
    
    if figures:
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
        print(f"✅ Inserted {len(insert_res.data)} rows into deep_note_figures.")

    # 5. Verify select from deep_note_figures
    verify_res = supabase.table("deep_note_figures").select("topic_number, figure_index, title, figure_type").eq("lecture_id", lecture_id).order("topic_number").execute()
    print(f"✅ Verified {len(verify_res.data)} rows exist in database:")
    for row in verify_res.data:
        print(f"   Row: Topic {row['topic_number']}, Fig {row['figure_index']} -> {row['title']} ({row['figure_type']})")

    print("\n📊 Billing Report:")
    print(billing.report())

if __name__ == "__main__":
    asyncio.run(run_live_test())
