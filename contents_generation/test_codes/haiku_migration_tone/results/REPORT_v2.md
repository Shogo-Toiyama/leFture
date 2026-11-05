# Haiku 5.5 v2 — 2026-11-05 (6 targeted calls, $0.0156)

Base: v1 prompts + strict json_schema (same code patches as v1c). Run with --only (all prompts built as in production; only selected topics call the API).
Targets: RC a028aad6:2 (en->ja), de2d74b0:3 (ja->ja); DN 666b2c9d:4, :6 (code examples); FF ed333ded, a028aad6.

Prompt changes from v1:
- RC: removed brevity wording (bite-sized, "Short, Fun, Solid", ruthless/mobile constraint, quick mobile glance, "brief" in examples); VOICE: at least one emotional lift per card, not stingy with "!", "be generous, not terse".
- DN: plain gentle wording (short sentences, explain terms on first use, friendly です/ます); self-contained notes (show code/formula instead of describing examples); invented illustrations allowed, new concepts not.
- FF: closing must show real-world impact of the concept; never mention the next lecture.

| same topic | before | v2 |
|---|---|---|
| RC a028aad6:2 chars / ！ | 1214 / 4 (v1c) | 1428 / 7 |
| RC de2d74b0:3 chars / ！ | 1363 / 4 (v1c) | 1686 / 5 |
| DN 666b2c9d:4 code blocks | 3 (v1) | 6 |
| DN 666b2c9d:6 code blocks | 1 (v1) | 8 |
| FF closing mentions next lecture | 2/2 (v1) | 0/2 |
Remaining: one prose-only example (squareX/squareY) still in DN topic 6.

## v3 (Deep Notes only, 2 calls, $0.011)
Strengthened No Meta-Language with explicit bans + poly before/after examples; removed instructor-centric wording.
Meta mentions (講義/授業/instructor...) 666b2c9d:4 13 -> 1, :6 1 -> 0. Code blocks 6 -> 7, 8 -> 9.
