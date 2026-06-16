# app/services/logic/core_extraction.py
import re
from typing import Any, Dict

from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM
from app.services.helpers.helpers import _load_prompt
from app.services.helpers.helpers import TaskLogger


class CoreExtractionService:
    def __init__(self, llm: UnifiedLLM, logger: TaskLogger):
        self.llm = llm
        self.logger = logger
        self.model_alias = "together_ai/openai/gpt-oss-120b"

    async def run_from_memory(self, transcript_data: list[dict]) -> Dict[str, Any]:
        self.logger.log(f"   [Logic] Starting Core Extraction with {self.model_alias}")

        prompt = _load_prompt("core_extraction_prompt.txt")
        options_json = LLMOptions(output_type="json", temperature=0.4, reasoning_effort="medium")

        # データの整形 (<sid>: <text> のプレーンテキストを作成)
        # 同時に、LLMが返したSIDを後で検証できるように、実在SID一覧も作る。
        formatted_lines: list[str] = []
        valid_sids: set[str] = set()
        sid_to_order: dict[str, int] = {}

        for item in transcript_data:
            sid = item.get("sid")
            text = item.get("text", "").strip()

            if not sid and not text:
                continue

            if not sid:
                raise ValueError(f"Transcript item is missing sid: {item}")

            if not isinstance(sid, str) or not re.fullmatch(r"s\d{6}", sid):
                raise ValueError(f"Invalid SID format in transcript_data: {sid}")

            if sid in valid_sids:
                raise ValueError(f"Duplicate SID in transcript_data: {sid}")

            if not text:
                # AssembleTranscriptService 側では基本的に text が入る想定だが、
                # 空文はLLMへ渡しても意味が薄いためスキップする。
                continue

            valid_sids.add(sid)
            sid_to_order[sid] = len(sid_to_order) + 1
            formatted_lines.append(f"{sid}: {text}")

        formatted_transcript = "\n".join(formatted_lines)

        if not formatted_transcript:
            raise ValueError("No valid transcript lines found for Core Extraction.")

        messages = [
            Message(role="system", content=prompt),
            Message(
                role="user",
                content=(
                    "Here is the transcript data:\n"
                    f"{formatted_transcript}\n\n"
                    "Please extract the core metadata, topics, and fun fact idea "
                    "as strictly requested in JSON."
                ),
            ),
        ]

        self.logger.log("Waiting for response from LiteLLM...")

        res = await self.llm.generate(
            model=self.model_alias,
            messages=messages,
            options=options_json,
        )

        if res.json_parse_error:
            self.logger.log(f"❌ JSON parse failed. Raw output:\n{res.output_text}")
            raise ValueError(f"JSON parse failed: {res.json_parse_error}")

        self.logger.log(f"⏰ Core Extraction finished in {res.elapsed_seconds:.2f} seconds.")

        normalized_output = self._validate_and_normalize_output(
            output=res.output_json,
            valid_sids=valid_sids,
            sid_to_order=sid_to_order,
        )

        return normalized_output

    def _validate_and_normalize_output(
        self,
        output: Dict[str, Any],
        valid_sids: set[str],
        sid_to_order: dict[str, int],
    ) -> Dict[str, Any]:
        """
        Validate the LLM output before saving it as core_extraction.

        This is intentionally strict because downstream tasks rely heavily on:
        - topics[].start_sid / end_sid
        - topics[].topic_type
        - fun_fact_idea.start_sid / end_sid

        If the LLM hallucinates a SID, we fail fast instead of silently producing
        missing blocks in later tasks.
        """
        if not isinstance(output, dict):
            raise ValueError("Core extraction output must be a JSON object.")

        required_top_level_keys = [
            "keywords",
            "summary",
            "title",
            "topics",
            "fun_fact_idea",
        ]
        missing_keys = [key for key in required_top_level_keys if key not in output]
        if missing_keys:
            raise ValueError(f"Core extraction output is missing keys: {missing_keys}")

        if not isinstance(output["keywords"], list):
            raise ValueError("Core extraction field 'keywords' must be a list.")

        if not all(isinstance(keyword, str) for keyword in output["keywords"]):
            raise ValueError("Core extraction field 'keywords' must contain only strings.")

        if not isinstance(output["summary"], str):
            raise ValueError("Core extraction field 'summary' must be a string.")

        if not isinstance(output["title"], str):
            raise ValueError("Core extraction field 'title' must be a string.")

        topics = output["topics"]
        if not isinstance(topics, list) or not topics:
            raise ValueError("Core extraction field 'topics' must be a non-empty list.")

        previous_end_order = 0

        for idx, topic in enumerate(topics, start=1):
            if not isinstance(topic, dict):
                raise ValueError(f"topics[{idx}] must be an object.")

            # idx は後続で混乱しないように、必ず1始まりの連番へ正規化する。
            topic["idx"] = idx

            title = topic.get("title")
            if not isinstance(title, str) or not title.strip():
                raise ValueError(f"topics[{idx}].title must be a non-empty string.")

            topic_type = topic.get("topic_type")
            if topic_type not in {"ACADEMIC", "LOGISTICS"}:
                raise ValueError(
                    f"topics[{idx}].topic_type must be 'ACADEMIC' or 'LOGISTICS'. "
                    f"Got: {topic_type}"
                )

            self._validate_sid_range(
                start_sid=topic.get("start_sid"),
                end_sid=topic.get("end_sid"),
                valid_sids=valid_sids,
                sid_to_order=sid_to_order,
                label=f"topics[{idx}]",
            )

            start_order = sid_to_order[topic["start_sid"]]
            end_order = sid_to_order[topic["end_sid"]]

            if start_order <= previous_end_order:
                raise ValueError(
                    f"topics[{idx}] overlaps with a previous topic or is out of order. "
                    f"start_sid={topic['start_sid']}, previous_end_order={previous_end_order}"
                )

            previous_end_order = end_order

        fun_fact_idea = output["fun_fact_idea"]
        if not isinstance(fun_fact_idea, dict):
            raise ValueError("Core extraction field 'fun_fact_idea' must be an object.")

        self._validate_sid_range(
            start_sid=fun_fact_idea.get("start_sid"),
            end_sid=fun_fact_idea.get("end_sid"),
            valid_sids=valid_sids,
            sid_to_order=sid_to_order,
            label="fun_fact_idea",
        )

        concept_focus = fun_fact_idea.get("concept_focus")
        if not isinstance(concept_focus, str) or not concept_focus.strip():
            raise ValueError("fun_fact_idea.concept_focus must be a non-empty string.")

        exciting_angle = fun_fact_idea.get("exciting_angle")
        if not isinstance(exciting_angle, str) or not exciting_angle.strip():
            raise ValueError("fun_fact_idea.exciting_angle must be a non-empty string.")

        needs_web_search = fun_fact_idea.get("needs_web_search")
        if not isinstance(needs_web_search, bool):
            raise ValueError("fun_fact_idea.needs_web_search must be a boolean.")

        search_queries = fun_fact_idea.get("search_queries")
        if not isinstance(search_queries, list):
            raise ValueError("fun_fact_idea.search_queries must be a list.")

        if not all(isinstance(query, str) for query in search_queries):
            raise ValueError("fun_fact_idea.search_queries must contain only strings.")

        search_reasoning = fun_fact_idea.get("search_reasoning")
        if not isinstance(search_reasoning, str):
            raise ValueError("fun_fact_idea.search_reasoning must be a string.")

        if needs_web_search:
            if not search_queries:
                raise ValueError(
                    "fun_fact_idea.search_queries must be non-empty when needs_web_search is true."
                )
            if not search_reasoning.strip():
                raise ValueError(
                    "fun_fact_idea.search_reasoning must be non-empty when needs_web_search is true."
                )
        else:
            # 後続処理を単純にするため、Web検索不要の場合は必ず空に正規化する。
            fun_fact_idea["search_queries"] = []
            fun_fact_idea["search_reasoning"] = ""

        return output

    def _validate_sid_range(
        self,
        start_sid: Any,
        end_sid: Any,
        valid_sids: set[str],
        sid_to_order: dict[str, int],
        label: str,
    ) -> None:
        if not isinstance(start_sid, str) or not isinstance(end_sid, str):
            raise ValueError(f"{label} must contain string start_sid and end_sid.")

        if start_sid not in valid_sids:
            raise ValueError(f"{label}.start_sid does not exist in transcript: {start_sid}")

        if end_sid not in valid_sids:
            raise ValueError(f"{label}.end_sid does not exist in transcript: {end_sid}")

        if sid_to_order[start_sid] > sid_to_order[end_sid]:
            raise ValueError(
                f"{label} has invalid SID range: start_sid={start_sid}, end_sid={end_sid}"
            )