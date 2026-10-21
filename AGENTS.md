# Repository Guidelines & AI Assistant Instructions

## Prompt Guidelines
- **Strictly English Only**: All prompt files (under `lefture_backend/app/services/prompts/` and across the codebase) and internal LLM instructions must be written purely in English. Never use Japanese or any other non-English language inside prompts under any circumstances.
- **Anti-Mirroring & Tone Match**: Avoid mirroring or echoing the student's opening words, informal greetings, or exclamations. Match their emotional warmth and casual peer level in their language without copying their literal catchphrases.

## Development & Prompt Engineering Workflow
- **Test Before Implementation**: When refining or fixing prompts, do not directly modify production files without testing. Always run a comparative test (testing both the current prompt and the candidate prompt across multiple runs against real/sample student turns) to observe any tone or formatting drift before finalizing changes.
- **Minimal Changes**: Favor minimal, targeted prompt additions or edits over wholesale rewrites to prevent regression in other tone aspects.
