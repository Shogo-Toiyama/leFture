# app/services/logic/announcement_generation.py
from typing import Any, Dict

from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM
from app.services.helpers.helpers import TaskLogger, _load_prompt

class AnnouncementGenerationService:
    def __init__(self, llm: UnifiedLLM, logger: TaskLogger):
        self.llm = llm
        self.logger = logger
        self.model_alias = "together_ai/openai/gpt-oss-20b"

    async def run_from_memory(self, formatted_transcript: str) -> Dict[str, Any]:
        self.logger.log(f"   [Logic] Starting Announcement Generation with {self.model_alias}")
        
        # もし入力データが空なら、無駄なAPI呼び出しをせずに空の配列を返す
        if not formatted_transcript.strip():
            self.logger.log("   [Logic] No logistics data found. Skipping LLM call.")
            return {"announcements": []}

        prompt = _load_prompt("announcement_extraction_prompt.txt")
        options_json = LLMOptions(output_type="json", temperature=0.3, reasoning_effort="low")

        # プロンプト内の変数を実際のテキストに置換
        prompt_text = prompt.replace("${TRANSCRIPT_INPUT}", formatted_transcript)

        messages = [
            Message(role="system", content=prompt_text),
            Message(role="user", content="Please extract the actionable announcements as requested in JSON.")
        ]

        self.logger.log(f"Waiting for response from LiteLLM...")
        
        # ネイティブAsync呼び出し
        res = await self.llm.generate(
            model=self.model_alias,
            messages=messages,
            options=options_json
        )

        if res.json_parse_error:
            self.logger.log(f"❌ JSON parse failed. Raw output:\n{res.output_text}")
            raise ValueError(f"JSON parse failed: {res.json_parse_error}")

        self.logger.log(f"⏰ Announcement Generation finished in {res.elapsed_seconds:.2f} seconds.")
        
        return res.output_json