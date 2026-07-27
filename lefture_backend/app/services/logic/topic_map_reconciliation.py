# app/services/logic/topic_map_reconciliation.py
import json
import time
from typing import Any, Dict, List

from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM
from app.services.helpers.helpers import TaskLogger, _load_prompt, _build_language_instruction

class TopicMapReconciliationService:
    """
    TopicMappingServiceとは別の役割: Lectureの削除・移動で壊れたTopic Mapを
    まとめて修復する（除去済みトピックの後始末＋pending_additionsの統合）。
    通常の追加フローとはプロンプトを分け、こちらはノード削除の権限を一切持たず、
    渡されたpending_additions以外のノードを新規作成することもできない。
    """
    def __init__(self, llm: UnifiedLLM, logger: TaskLogger):
        self.llm = llm
        self.logger = logger
        self.model_alias = "together_ai/openai/gpt-oss-120b"

    async def run_from_memory(
        self,
        current_graph: Dict[str, Any],
        removed_topics: List[Dict[str, Any]],
        pending_additions: List[Dict[str, Any]],
        content_language: str = "English",
    ) -> Dict[str, Any]:
        self.logger.log(f"   [Logic] Starting Topic Map Reconciliation with {self.model_alias}")
        start_time = time.perf_counter()

        prompt = _load_prompt("topic_map_reconciliation_prompt.txt")
        options_json = LLMOptions(output_type="json", temperature=0.3, reasoning_effort="medium")

        prompt_text = prompt.replace(
            "${CURRENT_GRAPH_JSON}",
            json.dumps(current_graph, ensure_ascii=False)
        ).replace(
            "${REMOVED_TOPICS_JSON}",
            json.dumps(removed_topics, ensure_ascii=False)
        ).replace(
            "${PENDING_ADDITIONS_JSON}",
            json.dumps(pending_additions, ensure_ascii=False)
        ).replace(
            "${LANGUAGE_INSTRUCTIONS}", _build_language_instruction(content_language)
        )

        messages = [
            Message(role="system", content=prompt_text),
            Message(role="user", content="Repair the graph given the removed topics, and integrate the pending additions. Generate the graph_mutations JSON.")
        ]

        self.logger.log("Waiting for response from LiteLLM (Topic Map Reconciliation)...")

        res = await self.llm.generate(
            model=self.model_alias,
            messages=messages,
            options=options_json
        )

        if res.json_parse_error:
            self.logger.log(f"❌ JSON parse failed for Topic Map Reconciliation. Raw output:\n{res.output_text}")
            raise ValueError(f"Topic Map Reconciliation JSON parse failed: {res.json_parse_error}")

        output = res.output_json
        if not output or not isinstance(output, dict) or "graph_mutations" not in output:
            self.logger.log(f"❌ Received structurally invalid JSON for Topic Map Reconciliation (missing 'graph_mutations'). Raw output: {res.output_text[:500] if res.output_text else 'None'}")
            raise ValueError(f"Topic Map Reconciliation JSON is valid but missing 'graph_mutations' key. Got: {type(output)}")

        elapsed = time.perf_counter() - start_time
        self.logger.log(f"⏰ Topic Map Reconciliation finished in {elapsed:.2f} seconds.")

        return output
