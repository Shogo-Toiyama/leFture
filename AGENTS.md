# Repository Guidelines & AI Assistant Instructions

> [!CAUTION]
> ### 🚨 STRICT RULE: ZERO HALLUCINATION & EVIDENCE-FIRST INVESTIGATION 🚨
> - **Zero Hallucination / No Guesswork**: NEVER guess or assume facts, metrics, costs, or system behaviors. If something is unknown or ambiguous, explicitly state: **"I do not know"** or **"Data is missing"**.
> - **Verify via Code, Database, or Experiments**: If there is any uncertainty, do not theorize—write scripts, query Supabase, inspect actual logs, or run experiments to verify the truth.
> - **Explicitly State Missing Information**: If data or information is insufficient to draw a definitive conclusion, explicitly clarify **what specific data is missing** and why it cannot be answered yet.
> - **Search for Latest Facts**: Always fetch live data via web search or local tools (Supabase / code inspection) before stating specs, pricing, or behaviors.

## Prompt Guidelines
- **Strictly English Only**: All prompt files (under `lefture_backend/app/services/prompts/` and across the codebase) and internal LLM instructions must be written purely in English. Never use Japanese or any other non-English language inside prompts under any circumstances.
- **Anti-Mirroring & Tone Match**: Avoid mirroring or echoing the student's opening words, informal greetings, or exclamations. Match their emotional warmth and casual peer level in their language without copying their literal catchphrases.

## Development & Prompt Engineering Workflow
- **Test Before Implementation**: When refining, fixing prompts, or adding new features/caching, do not directly modify production files without testing.
- **Dedicated Experiment Directory**: Always conduct experiments inside `contents_generation/test_codes/<new_folder>`. Create a dedicated directory and build the self-contained experiment environment there.
- **Production-Identical Environment**: All experiment environments must fetch real data, contexts, and parameters from Supabase and production backend code to mirror production execution as closely as possible.
- **Mandatory Dry-Run Before API Calls**: Always execute dry-runs (empty/mock calls or full validation without external token spends) to confirm that the script, parameters, prompt formatting, and schemas run without errors before making actual API calls.
- **Metrics & Reporting**: Explicitly report execution speed (latency/TTFT), token consumption, cost (including the cost of the test itself), tone of the response, or any other targeted metrics.
- **Persistent Result Artifacts**: Assign appropriate, timestamped names to test runs and save all execution results and summaries inside the experiment folder (`results/`).

## Experiment Results & Privacy
This repo is public, and experiment results are committed on purpose: they record what was tried, what changed and why. Raw inputs (`inputs/`, `cases/`, `patched/`) stay git-ignored.
- **Whose data may be committed**: only users listed in `tools/experiment_privacy/allowlist.json` (the developer and people who have consented). Add someone only when the developer says that person agreed.
- **Check before every commit that adds or changes experiment files**: run `python3 tools/experiment_privacy/check_results.py` (stdlib only, reads `lefture_backend/.env`). It resolves every UUID's owner in Supabase and flags data of anyone outside the allowlist. Do not commit while it reports `ACTION`.
- **IDs only** (user IDs, RevenueCat customers, IDs with no content next to them): run it with `--redact`. IDs become stable pseudonyms such as `redacted-user-1a2b3c4d`, so cross-references still match.
- **Content** (lecture text, chat messages, titles, topic names) of anyone outside the allowlist: never commit it, not even partly masked. Instead:
  1. Write a summary in the experiment's `results/` that keeps what matters: the change tried, the metrics (latency, tokens, cost, counts, scores) and the conclusion. Refer to that person's material only by a neutral label such as "user X, lecture 2".
  2. Move the raw file to the developer's private repo, and add its path to `.gitignore`.
  3. **Always tell the developer** which files were kept out and where the summary is.
- **Always mask**: secrets (API keys, JWTs, signed URLs) and personal emails. The checker flags them, but does not remove them.
- **Known limit**: the checker spots content through IDs and through titles or topic names. A file with only one matching title, or content that is copied without any title or ID, is reported as `note` at most. When results quote production data, read them before committing.
- **Minimal Changes**: Favor minimal, targeted additions or edits over wholesale rewrites to prevent regression.
- **Always Search the Web for Latest Information**: Whenever discussing AI models, API specifications, pricing, feature flags, or specific implementation details, always verify the latest information via web search before answering or implementing. Never rely on outdated memory or assumptions.

## UI Localization & Multi-lingual Guidelines
- **Strictly No Hardcoded UI Strings**: Whenever adding, editing, or displaying user-facing text in the UI (Flutter app or Webapp), never hardcode strings in widget or component files.
- **Use Localization Files**:
  - Flutter (`user_interface`): Always define and add translation keys in ARB / localization files (`user_interface/lib/l10n/app_en.arb`, `app_ja.arb`, etc.) and reference them via `l10n`.
  - Webapp (`webapp`): Always define and add translation keys in i18n JSON / message files (`webapp/src/locales/en.json`, `webapp/src/locales/ja.json`, etc.) and reference them via `t(...)`.
  - Always support both English and Japanese at minimum for every new user-facing label or status message.


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

## Code Knowledge Graph (graphify)
The repo has a graphify knowledge graph in `graphify-out/` (`graph.json`, `GRAPH_REPORT.md`, `graph.html`). Its scope is set in `.graphifyignore`. It covers `user_interface`, `lefture_backend`, `webapp`, `website`, `artifact_worker`, `email_worker` and `modal`. Generated code (`l10n/generated`, `*.g.dart`), platform shells, tests and images are excluded. When you run `/graphify` (full build or `--update`) in this repo, follow these rules on top of the skill's own steps:
- **Always pass `--directed`**, for full builds and for `--update`. Without it the graph is rebuilt undirected and loses caller→callee direction.
- **The Dart post-process is mandatory.** Run `$(cat graphify-out/.graphify_python) tools/graphify/postprocess_dart.py graphify-out/.graphify_extract.json` as a dry run first, then again with `--write`. It drops the `_` parameter nodes, which collide with file nodes and overwrite their labels. It also rewires Riverpod `xxxProvider` references to their definitions.
  - Full build: run it after Step 3 Part C (merge AST + semantic) and before Step 4 (build/cluster).
  - `--update`: run it on the **merged full graph**, after `build_merge` writes `.graphify_extract.json` and before Step 4. Never run it on the changed-files-only extraction, because provider definitions in unchanged files would be missing and nothing would resolve.
- **Treat `.dart`, `.tsx`, `.sql`, `.yaml` and `.json` as code in `--update`.** The skill's `code_only` list omits them. If only code files changed, take the Part B fast path. Do not dispatch semantic subagents for code-only changes.
- **Verify before reporting.** After the build, confirm that no node is labeled `_` or has an empty label, and that the post-process prints `provider_edges_still_dangling: 0`. Report both numbers.
- **Known limitation:** some `ref.read(xxxProvider.notifier)` uses are not captured as edges. For a complete list of a provider's users, confirm with `grep`.
