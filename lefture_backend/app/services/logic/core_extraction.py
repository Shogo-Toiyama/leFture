# app/services/logic/core_extraction.py
import json
import time
from typing import Any, Dict

from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM
from app.services.helpers.helpers import _load_prompt, _strip_code_fence
from app.services.helpers.helpers import TaskLogger

class CoreExtractionService:
    def __init__(self, llm: UnifiedLLM, logger: TaskLogger):
        self.llm = llm
        self.logger = logger
        self.model_alias = "groq/openai/gpt-oss-120b"

    async def run_from_memory(self, transcript_data: list[dict]) -> Dict[str, Any]:
        self.logger.log(f"   [Logic] Starting Core Extraction with {self.model_alias}")
        
        prompt = _load_prompt("core_extraction_prompt.txt")
        options_json = LLMOptions(output_type="json", temperature=0.2)

        # データの整形 (<sid>: <text> のプレーンテキストを作成)
        formatted_lines = []
        for item in transcript_data:
            sid = item.get("sid")
            text = item.get("text", "").strip()
            if sid and text:
                formatted_lines.append(f"{sid}: {text}")
        
        formatted_transcript = "\n".join(formatted_lines)

        messages = [
            Message(role="system", content=prompt),
            Message(role="user", content=f"Here is the transcript data:\n{formatted_transcript}\n\nPlease extract the core metadata, topics, and fun fact idea as strictly requested in JSON.")
        ]

        self.logger.log(f"Waiting for response from LiteLLM...")
        
        # 💡 ネイティブAsync呼び出し！めちゃくちゃ綺麗！
        res = await self.llm.generate(
            model=self.model_alias,
            messages=messages,
            options=options_json
        )

        if res.json_parse_error:
            self.logger.log(f"❌ JSON parse failed. Raw output:\n{res.output_text}")
            raise ValueError(f"JSON parse failed: {res.json_parse_error}")

        self.logger.log(f"⏰ Core Extraction finished in {res.elapsed_seconds:.2f} seconds.")
        
        return res.output_json