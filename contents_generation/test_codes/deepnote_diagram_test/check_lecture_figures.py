import os
import sys
from dotenv import load_dotenv

# load env from lefture_backend/.env
backend_env = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../lefture_backend/.env"))
load_dotenv(backend_env)

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../lefture_backend")))

from supabase import create_client

supabase_url = os.environ["SUPABASE_URL"]
supabase_key = os.environ["SUPABASE_SECRET_KEY"]
supabase = create_client(supabase_url, supabase_key)

lecture_id = "aa5646f7-f693-4199-a77c-3e2aafed13de"

# 1. Check lecture
lec_res = supabase.table("lectures").select("id, user_id, title").eq("id", lecture_id).execute()
print(f"Lecture: {lec_res.data}")

# 2. Check deep_notes
notes_res = supabase.table("deep_notes").select("id, topic_number, note_contents").eq("lecture_id", lecture_id).order("topic_number").execute()
print(f"Found {len(notes_res.data)} deep notes.")

from app.services.logic.figure_generation import FIGURE_TAG_REGEX, parse_figure_attrs

found_figures = []
for n in notes_res.data:
    contents = n.get("note_contents") or ""
    t_num = n.get("topic_number")
    matches = list(FIGURE_TAG_REGEX.finditer(contents))
    if matches:
        print(f"\n--- Topic {t_num} has {len(matches)} figure tag(s) ---")
        for m in matches:
            tag_content = m.group(1).strip()
            attrs = parse_figure_attrs(tag_content)
            print(f"  Tag: {m.group(0)}")
            print(f"  Attrs: {attrs}")
            found_figures.append({"topic_number": t_num, "attrs": attrs, "raw": m.group(0)})

print(f"\nTotal figure tags found: {len(found_figures)}")
