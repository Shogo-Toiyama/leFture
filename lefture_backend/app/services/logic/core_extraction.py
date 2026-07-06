# app/services/logic/core_extraction.py
import json
import re
from typing import Any, Dict

from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM
from app.services.helpers.helpers import _load_prompt
from app.services.helpers.helpers import TaskLogger
from app.services.helpers.helpers import _sid_to_int, _int_to_sid

# 重なりを自動補正してよい上限（文数）。これを超える場合は「軽微なズレ」とは
# 言えないため補正を諦め、リトライに任せる。
# 40文（＝前後20文ずつ）としているのは、後続のカード/ノート生成（例:
# topic_details_generation.py の BUFFER=20）がtopicの前後20文をコンテキストとして
# LLMに渡す設計のため。重なりが40文以内であれば中間で分割しても、前後20文の
# コンテキストを合わせれば元の重なっていた範囲を過不足なくカバーできる。
MAX_AUTO_CORRECTABLE_OVERLAP_SIDS = 40


class CoreExtractionService:
    def __init__(self, llm: UnifiedLLM, logger: TaskLogger):
        self.llm = llm
        self.logger = logger
        self.model_alias = "gemini/gemini-3.1-flash-lite"

    async def run_from_memory(self, transcript_data: list[dict], student_profile: str) -> Dict[str, Any]:
        self.logger.log(f"   [Logic] Starting Core Extraction with {self.model_alias}")

        prompt = _load_prompt("core_extraction_prompt.txt")
        prompt = prompt.replace("${STUDENT_PROFILE}", student_profile)
        options_json = LLMOptions(output_type="json", temperature=0.4)

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

        try:
            normalized_output = self._validate_and_normalize_output(
                output=res.output_json,
                valid_sids=valid_sids,
                sid_to_order=sid_to_order,
            )
        except Exception as e:
            # バリデーション失敗時、生のLLM出力はどこにも残らずそのまま消えていた。
            # 後で見返せるようログに残す（TaskLoggerはタスク失敗時にR2へ保存される）。
            # ※ ここで保存されるのはこのログだけで、下流タスクが実際に読む
            # core_extraction.json（save_json_log呼び出し）はバリデーション成功後
            # にしか書き込まれないため、壊れた出力を誤って後続処理が読む心配はない。
            self.logger.log(f"❌ Core extraction output failed validation: {e}")
            self.logger.log(
                "📄 Raw (invalid) LLM output for debugging:\n"
                f"{json.dumps(res.output_json, ensure_ascii=False, indent=2)}"
            )
            raise

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
            "summary",
            "title",
            "topics",
            "fun_fact_idea",
        ]
        missing_keys = [key for key in required_top_level_keys if key not in output]
        if missing_keys:
            raise ValueError(f"Core extraction output is missing keys: {missing_keys}")

        if not isinstance(output["summary"], str):
            raise ValueError("Core extraction field 'summary' must be a string.")

        if not isinstance(output["title"], str):
            raise ValueError("Core extraction field 'title' must be a string.")

        topics = output["topics"]
        if not isinstance(topics, list) or not topics:
            raise ValueError("Core extraction field 'topics' must be a non-empty list.")

        # 1. 各topicの基本フィールドを検証する（重なり順序のチェックはまだしない）。
        order_to_sid = {order: sid for sid, order in sid_to_order.items()}
        topics_with_order: list[tuple[int, int, dict]] = []

        for idx, topic in enumerate(topics, start=1):
            if not isinstance(topic, dict):
                raise ValueError(f"topics[{idx}] must be an object.")

            title = topic.get("title")
            if not isinstance(title, str) or not title.strip():
                raise ValueError(f"topics[{idx}].title must be a non-empty string.")

            topic_type = topic.get("topic_type")
            if topic_type not in {"ACADEMIC", "LOGISTICS"}:
                raise ValueError(
                    f"topics[{idx}].topic_type must be 'ACADEMIC' or 'LOGISTICS'. "
                    f"Got: {topic_type}"
                )

            # keywords のバリデーション
            keywords = topic.get("keywords")
            if keywords is not None:
                if not isinstance(keywords, list):
                    raise ValueError(f"topics[{idx}].keywords must be a list.")
                if not all(isinstance(kw, str) for kw in keywords):
                    raise ValueError(f"topics[{idx}].keywords must contain only strings.")
            else:
                topic["keywords"] = []

            topic["start_sid"], topic["end_sid"] = self._validate_sid_range(
                start_sid=topic.get("start_sid"),
                end_sid=topic.get("end_sid"),
                valid_sids=valid_sids,
                sid_to_order=sid_to_order,
                label=f"topics[{idx}]",
            )

            start_order = sid_to_order[topic["start_sid"]]
            end_order = sid_to_order[topic["end_sid"]]

            topics_with_order.append((start_order, end_order, topic))

        # 2. LLMが順序をシャッフルして返すことがあるため、start_orderで安定ソートする。
        # これ自体は意味を変えない機械的な並べ替え。
        topics_with_order.sort(key=lambda t: t[0])

        # 3. 重なり・連続性を検証しつつ、軽微なズレは自動補正する。
        # 「軽微」の基準: 重なっている長さが MAX_AUTO_CORRECTABLE_OVERLAP_SIDS (40文)
        # 以下であること。補正方法は「重なりの中間で分割」— 前のtopicの終わりを
        # 削るのではなく押し出すのでもなく、重なった区間を両者で半分ずつ分け合う。
        # これを超える重なりや、分割してもどちらかの範囲が消えてしまう場合は、
        # 意味の取り違えである可能性が高いため補正を諦めてリトライに任せる。
        previous_end_order = 0
        previous_start_order = 0
        previous_topic: dict | None = None
        normalized_topics: list[dict] = []

        for start_order, end_order, topic in topics_with_order:
            if previous_topic is not None and start_order <= previous_end_order:
                overlap_start = start_order
                overlap_end = previous_end_order
                overlap_length = overlap_end - overlap_start + 1

                if overlap_length > MAX_AUTO_CORRECTABLE_OVERLAP_SIDS:
                    raise ValueError(
                        f"topic '{topic.get('title')}' overlaps too much with the previous "
                        f"topic to auto-correct (overlap={overlap_length} SIDs, "
                        f"max_auto_correctable={MAX_AUTO_CORRECTABLE_OVERLAP_SIDS} SIDs): "
                        f"start_sid={topic['start_sid']}, end_sid={topic['end_sid']}"
                    )

                mid_order = (overlap_start + overlap_end) // 2
                new_previous_end_order = mid_order
                new_start_order = mid_order + 1

                if new_start_order > end_order or new_previous_end_order < previous_start_order:
                    raise ValueError(
                        f"topic '{topic.get('title')}' overlap could not be split safely "
                        f"(topic too short after split): start_sid={topic['start_sid']}"
                    )

                self.logger.log(
                    f"⚠️ Auto-corrected overlap between '{previous_topic.get('title')}' and "
                    f"'{topic.get('title')}' by splitting at the midpoint "
                    f"(previous end_sid -> {order_to_sid[new_previous_end_order]}, "
                    f"current start_sid -> {order_to_sid[new_start_order]})"
                )

                previous_topic["end_sid"] = order_to_sid[new_previous_end_order]
                previous_end_order = new_previous_end_order

                topic["start_sid"] = order_to_sid[new_start_order]
                start_order = new_start_order

            topic["idx"] = len(normalized_topics) + 1
            normalized_topics.append(topic)
            previous_end_order = end_order
            previous_start_order = start_order
            previous_topic = topic

        output["topics"] = normalized_topics

        fun_fact_idea = output["fun_fact_idea"]
        if not isinstance(fun_fact_idea, dict):
            raise ValueError("Core extraction field 'fun_fact_idea' must be an object.")

        fun_fact_idea["start_sid"], fun_fact_idea["end_sid"] = self._validate_sid_range(
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
    ) -> tuple[str, str]:
        if not isinstance(start_sid, str) or not isinstance(end_sid, str):
            raise ValueError(f"{label} must contain string start_sid and end_sid.")

        start_sid = self._normalize_sid_or_raise(start_sid, valid_sids, label=f"{label}.start_sid")
        end_sid = self._normalize_sid_or_raise(end_sid, valid_sids, label=f"{label}.end_sid")

        if sid_to_order[start_sid] > sid_to_order[end_sid]:
            raise ValueError(
                f"{label} has invalid SID range: start_sid={start_sid}, end_sid={end_sid}"
            )

        return start_sid, end_sid

    def _normalize_sid_or_raise(self, raw_sid: str, valid_sids: set[str], label: str) -> str:
        """
        LLMが返したSIDが軽微なフォーマット崩れ（sプレフィックス無し・大文字S・
        ゼロ埋め桁数の過不足）であれば正規形に補正する。補正後も実在しない、
        または数値として解釈できない場合はハルシネーションとみなし例外を送出する。
        """
        if raw_sid in valid_sids:
            return raw_sid

        n = _sid_to_int(raw_sid)
        if n is not None:
            candidate = _int_to_sid(n)
            if candidate in valid_sids:
                self.logger.log(
                    f"⚠️ Auto-corrected malformed SID format: '{raw_sid}' -> '{candidate}' ({label})"
                )
                return candidate

        raise ValueError(f"{label} does not exist in transcript: {raw_sid}")