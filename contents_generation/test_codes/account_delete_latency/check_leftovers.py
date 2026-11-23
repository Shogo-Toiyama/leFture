"""削除したアカウントの残り物を確かめる(読み取りのみ)。

使い方: .venv/bin/python contents_generation/test_codes/account_delete_latency/check_leftovers.py <user_id> [lecture_id ...]
  - user_id で絞れるテーブル: 行数
  - lecture_id を渡した場合: lecture_id で絞る子テーブル(lecture_transcripts など user_id を持たないもの)の行数
  - R2 の {user_id}/ 配下のオブジェクト数
support_tickets は意図的に削除対象外なので数えない。
"""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "lefture_backend"))
os.chdir(ROOT / "lefture_backend")
from dotenv import load_dotenv  # noqa: E402
load_dotenv(ROOT / "lefture_backend" / ".env")
from supabase import create_client  # noqa: E402
from app.core.r2_storage import storage_service  # noqa: E402

uid, lecture_ids = sys.argv[1], sys.argv[2:]
c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])

BY_USER = [
    "lectures", "courses", "topic_maps", "announcements", "fun_facts", "review_cards", "deep_notes",
    "keywords", "lecture_topics", "processing_jobs", "chat_threads", "chat_messages", "chat_attachments",
    "chat_summary_blocks", "knowledge_chunks", "profile_items", "profile_observations", "profile_categories",
    "ai_memos", "profile_hypotheses", "profile_blocked_areas", "profile_cover_proposals",
    "profile_extraction_state", "user_subscription_mappings", "credit_grants", "credit_transactions",
    "store_subscription_sync_state", "user_devices",
]
BY_LECTURE = ["lecture_transcripts", "processing_jobs", "lecture_topics", "review_cards", "deep_notes"]

left = {}
for t in BY_USER:
    try:
        n = c.table(t).select("*", count="exact", head=True).eq("user_id", uid).execute().count
    except Exception as e:
        n = f"error: {type(e).__name__}"
    if n:
        left[t] = n
n = c.table("user_profiles").select("*", count="exact", head=True).eq("id", uid).execute().count
if n:
    left["user_profiles"] = n
for t in BY_LECTURE:
    for lid in lecture_ids:
        n = c.table(t).select("*", count="exact", head=True).eq("lecture_id", lid).execute().count
        if n:
            left[f"{t}[lecture_id]"] = left.get(f"{t}[lecture_id]", 0) + n
r2 = storage_service.s3.list_objects_v2(Bucket=storage_service.bucket_name, Prefix=f"{uid}/", MaxKeys=1000)
if r2.get("KeyCount"):
    left["r2_objects"] = r2["KeyCount"]
try:
    c.auth.admin.get_user_by_id(uid)
    left["auth_user"] = "still exists"
except Exception:
    pass
print("no leftovers" if not left else left)
