# app/services/logic/fun_fact_brainstorming.py
from typing import Any, Dict

from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM
from app.services.helpers.helpers import _load_prompt
from app.services.helpers.helpers import TaskLogger


class FunFactBrainstormingService:
    def __init__(self, llm: UnifiedLLM, logger: TaskLogger):
        self.llm = llm
        self.logger = logger
        self.model_alias = "gemini/gemini-3.1-flash-lite"

    async def run_from_memory(
        self,
        student_profile: str,
        topic_title: str,
        concept_focus: str,
        course_title: str,
        concept_intro_line: str,
    ) -> Dict[str, Any]:
        self.logger.log(f"   [Logic] Starting Fun Fact Brainstorming with {self.model_alias}")

        prompt = _load_prompt("fun_fact_brainstorming_prompt.txt")
        prompt = prompt.replace("${STUDENT_PROFILE}", student_profile)
        prompt = prompt.replace("${TOPIC_TITLE}", topic_title)
        prompt = prompt.replace("${CONCEPT_FOCUS}", concept_focus)
        prompt = prompt.replace("${COURSE_TITLE}", course_title)
        prompt = prompt.replace("${CONCEPT_INTRO_LINE}", concept_intro_line)

        options_json = LLMOptions(output_type="json", temperature=0.8)

        messages = [
            Message(role="system", content=prompt),
            Message(
                role="user",
                content="Find the single best raw fun fact idea, following the schema strictly.",
            ),
        ]

        res = await self.llm.generate(
            model=self.model_alias,
            messages=messages,
            options=options_json,
        )

        if res.json_parse_error:
            self.logger.log(f"❌ Fun Fact Brainstorming JSON parse failed. Raw output:\n{res.output_text}")
            raise ValueError(f"Fun Fact Brainstorming JSON parse failed: {res.json_parse_error}")

        self.logger.log(f"⏰ Fun Fact Brainstorming finished in {res.elapsed_seconds:.2f} seconds.")

        return self._validate_and_normalize_output(res.output_json)

    def _validate_and_normalize_output(self, output: Dict[str, Any]) -> Dict[str, Any]:
        if not isinstance(output, dict):
            raise ValueError("Fun Fact Brainstorming output must be a JSON object.")

        required_keys = [
            "seed_fun_fact_idea",
            "named_instance",
            "concrete_detail",
            "domain",
            "needs_web_search",
            "search_queries",
            "search_reasoning",
        ]
        missing_keys = [key for key in required_keys if key not in output]
        if missing_keys:
            raise ValueError(f"Fun Fact Brainstorming output is missing keys: {missing_keys}")

        for key in ("seed_fun_fact_idea", "named_instance", "concrete_detail", "domain"):
            value = output.get(key)
            if not isinstance(value, str) or not value.strip():
                raise ValueError(f"Fun Fact Brainstorming field '{key}' must be a non-empty string.")

        needs_web_search = output.get("needs_web_search")
        if not isinstance(needs_web_search, bool):
            raise ValueError("Fun Fact Brainstorming field 'needs_web_search' must be a boolean.")

        search_queries = output.get("search_queries")
        if not isinstance(search_queries, list) or not all(isinstance(q, str) for q in search_queries):
            raise ValueError("Fun Fact Brainstorming field 'search_queries' must be a list of strings.")

        search_reasoning = output.get("search_reasoning")
        if not isinstance(search_reasoning, str):
            raise ValueError("Fun Fact Brainstorming field 'search_reasoning' must be a string.")

        if needs_web_search:
            if not search_queries:
                raise ValueError(
                    "Fun Fact Brainstorming field 'search_queries' must be non-empty when "
                    "needs_web_search is true."
                )
            if not search_reasoning.strip():
                raise ValueError(
                    "Fun Fact Brainstorming field 'search_reasoning' must be non-empty when "
                    "needs_web_search is true."
                )
        else:
            # 後続処理を単純にするため、Web検索不要の場合は必ず空に正規化する。
            output["search_queries"] = []
            output["search_reasoning"] = ""

        return output
