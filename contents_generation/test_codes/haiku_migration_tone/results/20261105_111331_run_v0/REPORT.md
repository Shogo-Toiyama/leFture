# Haiku 5.5 v0 (production prompts) — 2026-11-05

- Model: anthropic/claude-haiku-5-5, reasoning_effort=low (adaptive thinking), max_tokens=32000
- Prompts: production (v0), 6 lectures (4 en->ja, 1 ja->ja, 1 en->en), 60 LLM calls
- R2 pipeline_cache read/write disabled; no DB writes
- Wall time: 174.9 s (concurrency 6) | longest single call: 24.7 s (deep notes)
- Token cost: $0.1614 total (Haiku). Dry-run token counting used the free count_tokens endpoint ($0).
- Truncation (finish_reason=length): 0 | JSON parse errors: 0 | placeholder leaks: 0 | bad card order: 0

## Surface metrics vs existing Gemini 2.5 Flash output (reference only; Gemini output used older prompts)
| task | model | chars | ！ | ？ | (English gloss) |
|---|---|---|---|---|---|
| review_cards | Haiku v0 | 37703 | 50 | 33 | 64 |
| review_cards | Gemini | 43387 | 198 | 72 | 200 |
| deep_notes | Haiku v0 | 88307 | 10 | 0 | 182 |
| deep_notes | Gemini | 65120 | 6 | 27 | 162 |
| fun_facts | Haiku v0 | 4057 | 2 | 6 | 1 |
| fun_facts | Gemini | 4172 | 0 | 4 | 6 |

Viewer: viewer.html (published privately as https://claude.ai/artifact/981br65PuQ7h54fFM69jhw)
