# app/services/logic/topic_mapping.py
import json
import time
from typing import Any, Dict

from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM
from app.services.helpers.helpers import TaskLogger, _load_prompt, _strip_code_fence

class TopicMappingService:
    def __init__(self, llm: UnifiedLLM, logger: TaskLogger):
        self.llm = llm
        self.logger = logger
        self.model_alias = "together_ai/openai/gpt-oss-120b"

    async def run_from_memory(self, current_graph: Dict[str, Any], todays_topics: Dict[str, Any]) -> Dict[str, Any]:
        self.logger.log(f"   [Logic] Starting Topic Mapping with {self.model_alias}")
        start_time = time.perf_counter()
        
        # 1. プロンプトの読み込み
        prompt = _load_prompt("topic_mapping_prompt.txt")
        options_json = LLMOptions(output_type="json", temperature=0.3, reasoning_effort="medium")

        # 2. プロンプト内の変数をJSON文字列に置換
        # ※ インデントを無しにしてトークンを節約しつつ、構造を伝える
        prompt_text = prompt.replace(
            "${CURRENT_GRAPH_JSON}", 
            json.dumps(current_graph, ensure_ascii=False)
        ).replace(
            "${TODAYS_MACRO_TOPICS_JSON}", 
            json.dumps(todays_topics, ensure_ascii=False)
        )

        messages = [
            Message(role="system", content=prompt_text),
            Message(role="user", content="Based on today's topics and the current state, generate the graph_mutations JSON.")
        ]

        self.logger.log(f"Waiting for response from LiteLLM (Topic Mapping)...")
        
        # 3. 非同期でLLMを呼び出し
        res = await self.llm.generate(
            model=self.model_alias,
            messages=messages,
            options=options_json
        )

        if res.json_parse_error:
            self.logger.log(f"❌ JSON parse failed for Topic Mapping. Raw output:\n{res.output_text}")
            raise ValueError(f"Topic Mapping JSON parse failed: {res.json_parse_error}")

        elapsed = time.perf_counter() - start_time
        self.logger.log(f"⏰ Topic Mapping finished in {elapsed:.2f} seconds.")
        
        return res.output_json