import os, json
from dotenv import load_dotenv

load_dotenv("lefture_backend/.env")
from supabase import create_client
from app.services.chat_summary import fetch_active_blocks, HEADER_CATEGORIES

def get_thread_notes(admin_client, thread_id: str) -> dict[str, list[dict]]:
    blocks = fetch_active_blocks(admin_client, thread_id, level=1)
    if not blocks:
        return {k: [] for k in HEADER_CATEGORIES}
    last_header = blocks[-1].get("header") or {}
    return {
        k: [
            {
                "text": it.get("text", ""),
                "source_turn": it.get("source_turn") or it.get("source_round"),
                "needs_source": bool(it.get("needs_source", False)),
            }
            for it in (last_header.get(k) or [])
            if it.get("text")
        ]
        for k in HEADER_CATEGORIES
    }

def main():
    client = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    thread_id = "b70b7b26-21d3-4e56-944b-459411578cd1"
    notes = get_thread_notes(client, thread_id)
    print("Result:")
    print(json.dumps(notes, indent=2, ensure_ascii=False))

if __name__ == "__main__":
    main()
