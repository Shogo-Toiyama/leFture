import os
import sys
import json
import requests
from dotenv import load_dotenv

# Try loading env from multiple paths
load_dotenv()
load_dotenv("../lefture_backend/.env")
load_dotenv("../../lefture_backend/.env")
load_dotenv("lefture_backend/.env")

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_SECRET_KEY = os.environ.get("SUPABASE_SECRET_KEY") or os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

# Fallback to absolute path if needed
if not SUPABASE_URL or not SUPABASE_SECRET_KEY:
    abs_env = "/Users/shogo/DocumentsLocal/Programming/Python/orbit-lecture-companion/lefture_backend/.env"
    if os.path.exists(abs_env):
        load_dotenv(abs_env)
        SUPABASE_URL = os.environ.get("SUPABASE_URL")
        SUPABASE_SECRET_KEY = os.environ.get("SUPABASE_SECRET_KEY") or os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

if not SUPABASE_URL or not SUPABASE_SECRET_KEY:
    print("❌ Error: SUPABASE_URL or SUPABASE_SECRET_KEY (SUPABASE_SERVICE_ROLE_KEY) not found in env.")
    sys.exit(1)

# Parse inputs
LECTURE_ID = ""
EXPECTED_CHUNKS = 0

if len(sys.argv) >= 3:
    LECTURE_ID = sys.argv[1]
    try:
        EXPECTED_CHUNKS = int(sys.argv[2])
    except ValueError:
        print("❌ Error: Expected chunks must be an integer.")
        sys.exit(1)
elif len(sys.argv) == 2:
    LECTURE_ID = sys.argv[1]
    try:
        EXPECTED_CHUNKS = int(input("Enter Expected Chunks (e.g. 5): ").strip())
    except ValueError:
        print("❌ Error: Expected chunks must be an integer.")
        sys.exit(1)
else:
    LECTURE_ID = input("Enter Lecture ID: ").strip()
    try:
        EXPECTED_CHUNKS = int(input("Enter Expected Chunks (e.g. 5): ").strip())
    except ValueError:
        print("❌ Error: Expected chunks must be an integer.")
        sys.exit(1)

if not LECTURE_ID:
    print("❌ Error: Lecture ID cannot be empty.")
    sys.exit(1)

print(f"🔗 Connecting to Supabase: {SUPABASE_URL}")

# Common Headers
headers = {
    "apikey": SUPABASE_SECRET_KEY,
    "Authorization": f"Bearer {SUPABASE_SECRET_KEY}"
}

# 1. Fetch user_id from lectures table
print(f"🔍 Fetching user_id for Lecture: {LECTURE_ID}...")
select_url = f"{SUPABASE_URL}/rest/v1/lectures?id=eq.{LECTURE_ID}&select=user_id"
try:
    response = requests.get(select_url, headers=headers)
    response.raise_for_status()
    data = response.json()
    if not data:
        print(f"❌ Error: Lecture with ID {LECTURE_ID} not found in Supabase 'lectures' table.")
        sys.exit(1)
    USER_ID = data[0]["user_id"]
    print(f"✅ Found User ID: {USER_ID}")
except Exception as e:
    print(f"❌ Error querying lectures table: {e}")
    sys.exit(1)

# 2. Insert processing_jobs
print("📝 1. Creating parent job in 'processing_jobs'...")
job_data = {
    "lecture_id": LECTURE_ID,
    "user_id": USER_ID,
    "expected_chunks": EXPECTED_CHUNKS,
    "status": "PENDING"
}
post_job_url = f"{SUPABASE_URL}/rest/v1/processing_jobs"
post_headers = {
    **headers,
    "Prefer": "return=representation"
}

try:
    response = requests.post(post_job_url, headers=post_headers, json=job_data)
    response.raise_for_status()
    job_res = response.json()
    if not job_res:
        print("❌ Error: Failed to insert job (empty response).")
        sys.exit(1)
    job_id = job_res[0]["id"]
    print(f"✅ Parent job created! Job ID: {job_id}")
except Exception as e:
    print(f"❌ Error inserting processing_job: {e}")
    sys.exit(1)

# 3. Define DAG (tasks blueprint)
tasks_blueprint = [
    {"task_type": "CHECK_AND_ASSEMBLE", "dependencies": []},
    {"task_type": "CORE_EXTRACTION", "dependencies": ["CHECK_AND_ASSEMBLE"]},
    {"task_type": "ROLE_CLASSIFICATION", "dependencies": ["CORE_EXTRACTION"]},
    {"task_type": "ANNOUNCEMENT_GENERATION", "dependencies": ["ROLE_CLASSIFICATION"]},
    {"task_type": "TOPIC_MAPPING", "dependencies": ["ROLE_CLASSIFICATION"]},
    {"task_type": "REVIEW_CARD_GENERATION", "dependencies": ["TOPIC_MAPPING"]},
    {"task_type": "IMAGE_PROMPT_GENERATION", "dependencies": ["REVIEW_CARD_GENERATION"]},
    {"task_type": "IMAGE_RENDERING", "dependencies": ["IMAGE_PROMPT_GENERATION"]},
    {"task_type": "FUN_FACT_SEARCH", "dependencies": ["CORE_EXTRACTION"]},
    {"task_type": "FUN_FACTS_GENERATION", "dependencies": ["REVIEW_CARD_GENERATION", "FUN_FACT_SEARCH"]},
    {"task_type": "DETAIL_CONTENTS_GENERATION", "dependencies": ["REVIEW_CARD_GENERATION"]},
    {"task_type": "FINALIZE_JOB", "dependencies": [
        "ANNOUNCEMENT_GENERATION", 
        "IMAGE_RENDERING", 
        "FUN_FACTS_GENERATION", 
        "DETAIL_CONTENTS_GENERATION"
    ]}
]

# 4. Insert processing_tasks
print("📝 2. Registering child tasks in 'processing_tasks'...")
insert_data = [
    {
        "job_id": job_id,
        "task_type": t["task_type"],
        "dependencies": json.dumps(t["dependencies"]),
        "status": "PENDING"
    }
    for t in tasks_blueprint
]

post_tasks_url = f"{SUPABASE_URL}/rest/v1/processing_tasks"
try:
    response = requests.post(post_tasks_url, headers=headers, json=insert_data)
    response.raise_for_status()
    print("✅ All tasks successfully registered!")
    print(f"\n🎉 Manual trigger successful! The database triggers/webhooks will wake up the backend orchestrator.")
    print(f"👉 Track using Job ID: {job_id}")
except Exception as e:
    print(f"❌ Error inserting processing_tasks: {e}")
    sys.exit(1)
