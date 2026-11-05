# Haiku 5.5 v1 / v1b / v1c — 2026-11-05

Common: anthropic/claude-haiku-5-5, reasoning_effort=low, max_tokens=32000, 6 lectures, R2 cache disabled, no DB writes.

Prompt changes (prompts/v1, English only):
- Review Cards: VOICE section (talk to reader, emotion, slow down on hard part, ask-then-answer; techniques optional),
  key terms strongly recommended, length numbers doubled (paragraph 2-3 -> 4-6 sentences, core_why 2-3 -> 4-6 blocks,
  summary/closing/tease 1-2 -> 2-4 sentences, callback 1 -> up to 2), self-study heading in own words / output language,
  self-study items must be cited, stock phrases removed from examples.
- Deep Notes: friendly patient tutor persona, use lecture's own examples actively, use lists more.
- Fun Facts: "do not hold back your emotions".
Code-side patches (emulated in run_experiment.py; to be moved into ReviewCardGenerationService):
- ${CURRENT_TOPIC_KEYWORDS} filled with current topic keywords
- user message ends with "Write every card title and every text field in {lang}."
- v1: loose json_schema (all block fields optional) | v1b: no schema | v1c: strict anyOf schema per block type

| metric (Review Cards, 27 topics) | v0 | v1 | v1b | v1c | Gemini |
|---|---|---|---|---|---|
| chars | 37682 | 31338 | 46943 | 42035 | 43366 |
| ！ | 50 | 53 | 85 | 79 | 198 |
| ？ | 33 | 36 | 35 | 31 | 72 |
| key terms used /128 | 39 | 56 | 86 | 70 | 50 |
| topics w/ missing cards | 0 | 4 | 0 | 0 | 0 |
| empty blocks | 0 | 57 | 0 | 0 | - |
| English titles in ja output | 16 | 0 | 0 | 0 | 0 |
| stock self-study headings | 21 | 0 | 0 | 0 | 10 |
| self-study items cited | 35/75 | 52/52 | 76/76 | 66/68 | 64/68 |
| RC cost | $0.080 | $0.067 | $0.088 | $0.081 | - |

Deep Notes v0 -> v1: bullets 148 -> 287, numbered 27 -> 59, '？' 0 -> 8, chars 88k -> 100k.
Experiment spend so far: ~$0.58 (v0 0.161, probe 0.076, smoke tests 0.010, v1 0.160, v1b 0.088, v1c 0.081).
