import os
import json
from dotenv import load_dotenv

load_dotenv('lefture_backend/.env')
from supabase import create_client

client = create_client(os.environ['SUPABASE_URL'], os.environ['SUPABASE_SECRET_KEY'])

# 1. Thread A: DHCP (6a3080e4-3eb0-4c0a-af46-f77cdd6ad769)
# 2. Thread B: CS118 async sampling (ba9a18c9-6fec-42ac-9fcc-416554d574cb)

thread_ids = [
    '6a3080e4-3eb0-4c0a-af46-f77cdd6ad769',
    'ba9a18c9-6fec-42ac-9fcc-416554d574cb'
]

cases_data = {}

for tid in thread_ids:
    t_info = client.table('chat_threads').select('*').eq('id', tid).single().execute()
    msgs = client.table('chat_messages').select('*').eq('thread_id', tid).order('created_at').execute()
    cases_data[tid] = {
        'thread': t_info.data,
        'messages': msgs.data
    }

out_path = 'contents_generation/test_codes/prompt_caching_test/cases/raw_cases.json'
with open(out_path, 'w') as fp:
    json.dump(cases_data, fp, ensure_ascii=False, indent=2)

print(f"Extracted {len(cases_data)} threads into {out_path}")
for tid, d in cases_data.items():
    print(f"Thread {tid}: {len(d['messages'])} messages (Title: {d['thread'].get('title')})")
