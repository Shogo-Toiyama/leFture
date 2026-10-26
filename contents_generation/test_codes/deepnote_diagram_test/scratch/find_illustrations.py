import os, json, re
from dotenv import load_dotenv
load_dotenv("lefture_backend/.env")
from supabase import create_client

client = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])

res = client.table("deep_notes").select("id, lecture_id, topic_number, created_at, note_contents").order("created_at", desc=True).limit(500).execute()

figure_regex = re.compile(r"<!--\s*FIGURE:\s*(.*?)\s*-->", re.IGNORECASE | re.DOTALL)
attr_regex = re.compile(r"(\w+)=[\"'](.*?)[\"']", re.DOTALL)

lecture_ids = list(set([r["lecture_id"] for r in res.data if r.get("lecture_id")]))
lec_map = {}
for i in range(0, len(lecture_ids), 40):
    batch = lecture_ids[i:i+40]
    l_res = client.table("lectures").select("id, title, title_generated, courses(course_title)").in_("id", batch).execute()
    for l in l_res.data:
        c_title = l.get("courses", {}).get("course_title") if l.get("courses") else "General"
        l_title = l.get("title") or l.get("title_generated") or "Untitled"
        lec_map[l["id"]] = {"course": c_title, "lecture": l_title}

illustration_candidates = []
for row in res.data:
    contents = row.get("note_contents") or ""
    for m in figure_regex.finditer(contents):
        tag_content = m.group(1).strip()
        attrs = dict(attr_regex.findall(tag_content))
        fig_type = attrs.get("type", "").lower().strip()
        title = attrs.get("title", "").strip()
        desc = attrs.get("description", "").strip()
        
        # Look for illustration, image, drawing, scene, metaphor, conceptual
        is_illus = any(k in fig_type for k in ["illustration", "image", "drawing", "painting", "sketch", "art"]) or \
                   any(k in desc for k in ["様子", "人", "地面", "手作業", "道具", "イメージ", "シーン", "再現", "概念図"])
        if is_illus and not any(k in fig_type for k in ["table", "code", "matrix", "graph", "chart"]):
            lec = lec_map.get(row["lecture_id"], {"course": "Unknown", "lecture": "Unknown"})
            illustration_candidates.append({
                "type": fig_type,
                "title": title,
                "description": desc,
                "course": lec["course"],
                "lecture": lec["lecture"],
                "created_at": row.get("created_at")[:10]
            })

print(f"Found {len(illustration_candidates)} illustration-like candidates:\n")
for idx, c in enumerate(illustration_candidates[:15], 1):
    c_course = c['course']
    c_lec = c['lecture']
    c_type = c['type']
    c_title = c['title']
    c_desc = c['description']
    print(f"[{idx}] Course: {c_course} | Lecture: {c_lec}")
    print(f"    Type: {c_type} | Title: {c_title}")
    print(f"    Desc: {c_desc}")
    print("-" * 60)
