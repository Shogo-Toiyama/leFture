# Gemini 4 Hydrogen swap, round 1 (2026-11-23)

Model `gemini/gemini-4-hydrogen`, reasoning_effort low, one call per feature, production prompts and production Service code.
Pricing checked on the official page 2026-11-23: $1.50 in / $7.50 out per 1M tokens (thinking billed as output), cache read $0.075.
Spend: Hydrogen round 1 $0.1197 + Haiku same-condition re-run $0.0068 = $0.1265 of $0.50 (guard cap $0.45).

## Correction (same day)
The first version of this report compared against the earlier Haiku experiment (RC v4, DN v3, FF v2) and a different chat turn's latency.
Production prompts today differ from DN v3 (3 lines) and FF v2 (17 lines), so those comparisons were not like for like, and the quality claims
("DN code examples 7 -> 2", "RC shorter", "chat slower than production 0.4-0.9 s") were wrong. `haiku_baseline.py` re-ran Haiku 5.5 with the
same input, today's production prompts and production Service (results/*_haiku_baseline). The chat baseline is the production Haiku answer to the same turn
(2026-11-19). Numbers below are the corrected ones.

| feature (same input) | Hydrogen: sec / in / out / cost | Haiku: sec / in / out / cost | cost ratio |
|---|---|---|---|
| Review Cards, a028aad6 topic 2 | 16.9 / 10,082 / 2,802 / $0.0361 | 10.1 / 13,294 / 1,908 / $0.0025 | 14.3x |
| Deep Notes, 666b2c9d topic 4 | 23.8 / 11,478 / 4,449 / $0.0506 | 20.5 / 14,098 / 4,377 / $0.0036 | 14.1x |
| Fun Fact, ed333ded | 10.8 / 2,414 / 1,256 / $0.0130 | 3.8 / 3,909 / 543 / $0.0007 | 19.7x |
| Chat, normal turn (TTFT / total) | 3.56 s / 7.7 s, 7,006 / 1,019, $0.0184 | 3.04 s / 6.4 s, 9,814 / 1,136, $0.0023 (answer role, incl. 1h cache write of 7,757 tokens) | ~7.9x |

No errors, no truncation, no JSON parse errors on either side. The production RC schema was accepted by Hydrogen.

Quality (n=1 per feature, same conditions):
- RC: both 4 cards, 3 "!" and 1 code block; Hydrogen 1,136 chars vs Haiku 911. No meaningful difference.
- DN: Hydrogen 2,896 chars / 2 code blocks / 0 meta-language words; Haiku 3,326 / 1 / 5 ("講義の例では" etc.).
- FF: same topic and structure; Haiku writes "授業で学んだ" and ends with a mention of the next class (forbidden by the prompt); Hydrogen has neither.
- Chat: Hydrogen 1,192 chars / 10 "!" / opens with praise / "takuma" without san; Haiku 911 chars / 2 "!" / answers directly / "san".
  Haiku's closing invites the student to try something, which the prompt tells it to avoid.

Findings for production:
- cache_control must not be attached for non-Anthropic models (Hydrogen has implicit caching only). The experiment strips it.
- Chat credits are billed as 1.5x cost (CHAT_CREDIT_MARKUP), so revenue follows cost; but credits per turn rise from ~1.5 to ~8.7 for this turn (the 2x in an old llm_unified.py comment is stale).
- PRICE_MATRIX has no Hydrogen entry; the experiment adds it in-process only.

Dry-run (before round 1): models.get OK; litellm sends thinkingConfig {thinkingLevel: low, includeThoughts: true}; exact count_tokens inputs.
Raw outputs: `*_run_round1/raw.json`, `*_haiku_baseline/raw.json` (lectures and the chat turn belong to allowlisted users).


Correction 2: the chat Haiku baseline was first written as ~$0.0016 (11.9x). The production record shows the answer role cost $0.0023 (cache write included); `chargeable_usd` $0.0031 also includes the router. Ratio is ~7.9x. See cost_analysis.py for lecture economics.
