# Repository Guidelines & AI Assistant Instructions

## Prompt Guidelines
- **Strictly English Only**: All prompt files (under `lefture_backend/app/services/prompts/` and across the codebase) and internal LLM instructions must be written purely in English. Never use Japanese or any other non-English language inside prompts under any circumstances.
- **Anti-Mirroring & Tone Match**: Avoid mirroring or echoing the student's opening words, informal greetings, or exclamations. Match their emotional warmth and casual peer level in their language without copying their literal catchphrases.

## Development & Prompt Engineering Workflow
- **Test Before Implementation**: When refining or fixing prompts, do not directly modify production files without testing. Always run a comparative test (testing both the current prompt and the candidate prompt across multiple runs against real/sample student turns) to observe any tone or formatting drift before finalizing changes. Report results of cost, speed, tone of the response, or any other targetted metrics as well as the cost of the test itself.
- **Minimal Changes**: Favor minimal, targeted prompt additions or edits over wholesale rewrites to prevent regression in other tone aspects.
- **Always Search the Web for Latest Information**: Whenever discussing AI models, API specifications, pricing, feature flags, or specific implementation details, always verify the latest information via web search before answering or implementing. Never rely on outdated memory or assumptions.

## Chat Inspection & System Observability Guide
When instructed to inspect chat contents, user sessions, or retrieval/navigator behavior, use the project virtualenv (`.venv/bin/python`) with `lefture_backend/.env` loaded to query Supabase directly.

### 1. Supabase Database Tables & Structure
- **`chat_threads`**:
  - `id`: Thread UUID
  - `user_id`: User ID
  - `title`: Thread title (auto-generated or user-updated)
  - `mode`: 'learning' or chat mode
  - `context_lecture_id`: Set if the chat originated from a specific lecture, NULL for cross-course chats
  - `last_message_at`, `created_at`, `metadata`
- **`chat_messages`** (Contains full execution trace):
  - `id`: Message UUID
  - `thread_id`: Foreign key to `chat_threads.id`
  - `role`: `'user'` | `'assistant'`
  - `content`: Generated response text
  - `status`: `'complete'` | `'streaming'` | `'stopped'` | `'error'` | `'blocked'`
  - `router`: JSONB containing routing decision (`intent`, `needs_retrieval`, `needs_reasoning`, `reply_language`, `thread_title`, etc.)
  - `usage`: JSONB with full runtime diagnostics:
    - `usage.navigator`: The complete trace of the search/retrieval agent (`chat_navigator.py`).
      - `goal`: High-level goals set for material retrieval
      - `stop_reason`: Reason for ending loop (`enough_now`, `nothing_needed`, `lap_limit`, etc.)
      - `laps`: Array of lap steps (Lap 1 to max 4). Each lap contains:
        - `lap`: Lap index (1-based)
        - `status`: `'need_more'` | `'enough_now'` | `'nothing_needed'`
        - `reasoning`: The navigator's internal reasoning behind the decision
        - `missing`: Specific missing pieces of information identified
        - `requests`: Operations requested (`open`, `search`, `by_date`, etc.) with handle targets (`C{n}`: course, `L{n}`: lecture, `A{n}`: attachment, `S{n}`: section/topic)
        - `done`: Executed operations
        - `timing`: Milliseconds and token consumption
    - `usage.materials`: Array of materials actually injected into the answer prompt (`[{"key": "...", "handle": "..."}]`)
    - `usage.timings`: Breakdown of execution latencies
  - `citations`: JSONB array of citations used in the answer
  - `context`: JSONB metadata (e.g. `opened` references)
- **`chat_attachments`**:
  - `id`: Attachment UUID (referenced in chat as `⟦att:<id>⟧` or `A1`)
  - `thread_id`, `message_id`, `user_id`, `status` (`'ready'`, `'draft'`, `'failed'`, `'blocked'`)
  - `title`, `file_type`, `file_url`, `content_text`, `summary`, `table_of_contents`, `metadata`
- **Course & Lecture Domain Tables**:
  - **`courses`**: `id`, `user_id`, `course_title`, `summary`, `metadata`
  - **`lectures`**: `id`, `course_id`, `user_id`, `title`, `title_generated`, `lecture_datetime`, `summary`, `audio_path`, `sort_order`
  - **`lecture_topics`**: `id`, `lecture_id`, `index`, `topic_title`, `summary`, `topic_type`
  - **`keywords`**: `id`, `lecture_id`, `topic_number`, `keyword`, `definition`
  - **`deep_notes`**: `id`, `lecture_id`, `topic_number`, `note_contents`

### 2. Cloudflare R2 Storage Structure
Storage service (`app.core.r2_storage.R2StorageService`) manages audio and pipeline artifact files under bucket `R2_BUCKET_NAME`:
- Path format: `{uid}/{lecture_id}/...`
  - Audio: `{uid}/{lecture_id}/master_audio.m4a`, `audio_chunks/chunk_{seq}.m4a`
  - Pipeline logs & intermediate results: `{uid}/{lecture_id}/pipeline_logs/{task_type}.json`
    - `transcript.json`: Full Whisper / assembled transcript
    - `core_extraction.json`: Extracted core lecture facts and claims
    - `role_classification.json`: Utterance and role breakdowns
    - `topic_mapping.json`: Structured topics and segments
    - `deep_notes.json`: Deep notes generated per topic
    - `announcements.json`: Class announcements and administrative details
  - Images / Slides: `{uid}/{lecture_id}/{file_name}`

### 3. Quick Inspection Script Pattern
To inspect any chat thread or navigator behavior, execute via `.venv/bin/python`:
```python
import os, json
from dotenv import load_dotenv
load_dotenv('lefture_backend/.env')
from supabase import create_client

client = create_client(os.environ['SUPABASE_URL'], os.environ['SUPABASE_SECRET_KEY'])

# 1. Find recent threads
threads = client.table('chat_threads').select('id, title, last_message_at').order('last_message_at', desc=True).limit(5).execute()

# 2. Inspect messages and navigator trace for a thread
messages = client.table('chat_messages').select('id, role, content, status, router, usage, citations').eq('thread_id', thread_id).order('created_at').execute()
for m in messages.data:
    nav = m.get('usage', {}).get('navigator')
    # nav['laps'] contains each step's decision, requests, missing info, and reasoning
```
