# app/services/logic/review_card_generation.py
import time
import asyncio
from typing import Any, Dict, List

from app.core.r2_storage import storage_service
from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM
from app.services.helpers.helpers import (
    TaskLogger,
    _load_prompt,
    _sid_to_int,
    _build_bilingual_gloss_instruction,
    _render_conditional_sections,
    _get_previous_lecture_topics,
)


def _keyword_strings(topic: Dict[str, Any]) -> List[str]:
    """topic['keywords']は{"keyword": str, "definition": str|None}のオブジェクトのリスト。
    ここではdefinitionは使わず、用語そのもの(keyword)だけをコンテキストとして拾う。"""
    return [kw["keyword"] for kw in (topic.get("keywords") or []) if isinstance(kw, dict) and kw.get("keyword")]


REVIEW_CARD_MODEL = "anthropic/claude-haiku-5-5"
# max_tokensは思考トークン込み。途中で切れるとJSONが壊れるので高めにとる
# (2026-11 移行実験 contents_generation/test_codes/haiku_migration_tone で最大でも約5千トークン)。
REVIEW_CARD_MAX_TOKENS = 32000
EXPECTED_CARD_SEQUENCE = ["hook", "core_why", "gotcha", "next_action"]

_STR = {"type": "string"}


def _block_schema(type_name: str, required: List[str], props: Dict[str, Any]) -> Dict[str, Any]:
    return {"type": "object", "additionalProperties": False, "required": ["type"] + required,
            "properties": {"type": {"type": "string", "enum": [type_name]}, **props}}


# 構造化出力(Anthropicのnative structured output)で出力の形を強制する。
# ブロックの種類ごとに必須フィールドを持たせる(全フィールド任意にすると空ブロックやカード欠落が出た)。
# カードの枚数・順番まではスキーマで縛れないので、生成後に _has_expected_cards で確認する。
REVIEW_CARD_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "required": ["topic_evaluation", "review_cards"],
    "properties": {
        "topic_evaluation": {
            "type": "object",
            "additionalProperties": False,
            "required": ["micro_topics", "card_mapping_strategy", "core_concept_identified"],
            "properties": {
                "micro_topics": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "additionalProperties": False,
                        "required": ["idx", "title", "summary", "start_sid", "end_sid"],
                        "properties": {"idx": {"type": "integer"}, "title": _STR, "summary": _STR,
                                       "start_sid": _STR, "end_sid": _STR},
                    },
                },
                "card_mapping_strategy": _STR,
                "core_concept_identified": _STR,
            },
        },
        "review_cards": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["card_type", "hero_emoji", "title", "content_blocks"],
                "properties": {
                    "card_type": {"type": "string", "enum": EXPECTED_CARD_SEQUENCE},
                    "hero_emoji": _STR,
                    "title": _STR,
                    "content_blocks": {
                        "type": "array",
                        "items": {
                            "anyOf": [
                                _block_schema("paragraph", ["text"], {"text": _STR}),
                                _block_schema("quote", ["text"], {"text": _STR}),
                                _block_schema("callout", ["alert_type", "text"], {
                                    "alert_type": {"type": "string", "enum": ["info", "warning", "error"]},
                                    "text": _STR,
                                }),
                                _block_schema("code", ["code_string"],
                                              {"code_string": _STR, "language": _STR, "explanation": _STR}),
                                _block_schema("list", ["items"], {"items": {"type": "array", "items": _STR}}),
                            ]
                        },
                    },
                },
            },
        },
    },
}


def _has_expected_cards(result: Dict[str, Any]) -> bool:
    cards = result.get("review_cards") or []
    return [c.get("card_type") for c in cards] == EXPECTED_CARD_SEQUENCE


def _format_topic_context(topic: Dict[str, Any]) -> str:
    title = topic.get("title", "")
    keywords = _keyword_strings(topic)
    keyword_str = ", ".join(keywords) if keywords else "N/A"
    return f"Title: {title}\nKey Terms: {keyword_str}"


def _format_lecture_topics(topics: List[Dict[str, Any]]) -> str:
    lines = []
    for t in topics:
        title = t.get("title", "")
        keywords = ", ".join(_keyword_strings(t))
        lines.append(f"- {title} (Key Terms: {keywords})" if keywords else f"- {title}")
    return "\n".join(lines)


def _format_previous_lecture_topics(topics: List[Dict[str, Any]]) -> str:
    lines = []
    for t in topics:
        title = t.get("topic_title", "")
        summary = t.get("summary", "")
        lines.append(f"- {title}: {summary}" if summary else f"- {title}")
    return "\n".join(lines)


class ReviewCardGenerationService:
    def __init__(self, llm: UnifiedLLM, logger: TaskLogger):
        self.llm = llm
        self.logger = logger
        self.model_alias = REVIEW_CARD_MODEL

    async def run_from_memory(
        self,
        role_classified_data: List[Dict[str, Any]],
        core_data: Dict[str, Any],
        uid: str,
        lecture_id: str,
        content_language: str = "English",
        transcript_language: str = "English",
        is_bilingual: bool = False,
    ) -> List[Dict[str, Any]]:

        self.logger.log(f"   [Logic] Starting Review Card Generation with {self.model_alias}")

        prompt_template = _load_prompt("review_cards_generation_prompt.txt")
        prompt_template = prompt_template.replace(
            "${LANGUAGE_INSTRUCTIONS}",
            _build_bilingual_gloss_instruction(content_language, transcript_language, is_bilingual),
        )
        # Haiku 5.5はtemperature等のサンプリング設定に非対応(litellm.drop_paramsで捨てられる)ので指定しない
        options_json = LLMOptions(
            output_type="json",
            reasoning_effort="low",
            max_tokens=REVIEW_CARD_MAX_TOKENS,
            json_schema=REVIEW_CARD_SCHEMA,
        )
        
        all_review_results = []

        # 1. ACADEMIC なトピックだけを抽出
        academic_topics = [t for t in core_data.get("topics", []) if t.get("topic_type") == "ACADEMIC"]
        last_position = len(academic_topics) - 1

        failed_topic_indices = []

        for position, topic in enumerate(academic_topics):
            topic_idx = topic.get("idx")
            topic_title = topic.get("title")
            is_final_topic = position == last_position
            is_first_topic = position == 0
            
            # ① R2キャッシュ確認 (リトライ時はここでスキップ)
            cache_path = f"{uid}/{lecture_id}/pipeline_cache/review_cards_topic_{topic_idx}.json"
            cached = await asyncio.to_thread(storage_service.load_json_cache, cache_path)
            if cached is not None:
                self.logger.log(f"   [Cache] Topic {topic_idx}: loaded from R2 cache, skipping LLM.")
                all_review_results.append(cached)
                continue

            start_sid = topic.get("start_sid")
            end_sid = topic.get("end_sid")

            # 2. このトピックの範囲の文を抽出
            start_num = _sid_to_int(start_sid) if isinstance(start_sid, str) else None
            end_num = _sid_to_int(end_sid) if isinstance(end_sid, str) else None
            if start_num is None or end_num is None:
                continue

            segment_sentences = []
            for s in role_classified_data:
                sid_num = _sid_to_int(s.get("sid"))
                if sid_num is not None and start_num <= sid_num <= end_num:
                    segment_sentences.append(s)

            if not segment_sentences:
                empty_res = {"topic_idx": topic_idx, "review_cards": []}
                await asyncio.to_thread(storage_service.save_json_cache, cache_path, empty_res)
                all_review_results.append(empty_res)
                continue

            # 3. 💡 修正版: 一文ごとの確率 (all_probabilities) でフィルタリング！
            trimmed_lines = []
            for s in segment_sentences:
                probs = s.get("all_probabilities")
                
                # Role Classification で直接 "LOGISTICS" にされた等、確率データが無い場合のフォールバック
                if not probs:
                    if s.get("role") in ["CONTENT", "INTERACTION"]:
                        trimmed_lines.append(f"{s['sid']}: {s['text']}")
                    continue
                
                content_prob = probs.get("CONTENT", 0.0)
                interaction_prob = probs.get("INTERACTION", 0.0)
                
                # 条件: CONTENTが10%以上、または INTERACTIONが50%以上
                if content_prob >= 0.10 or interaction_prob >= 0.50:
                    trimmed_lines.append(f"{s['sid']}: {s['text']}")

            # 有効な文章が1つも残らなかったらこのトピックはスキップ
            if not trimmed_lines:
                self.logger.log(f"   [Logic] Skipping Topic {topic_idx} (No valid sentences passed the probability filter)")
                empty_res = {"topic_idx": topic_idx, "review_cards": []}
                await asyncio.to_thread(storage_service.save_json_cache, cache_path, empty_res)
                all_review_results.append(empty_res)
                continue

            trimmed_transcript = "\n".join(trimmed_lines)

            self.logger.log(f"   [Logic] Generating cards for Topic {topic_idx}: {topic_title} ({len(trimmed_lines)} valid sentences)")

            # 5. 「最終トピックかどうか」「最初のトピックかどうか」はLLMに推測させず、ここで確定させる
            if is_final_topic:
                next_topic_context_text = "This is the final topic of today's lecture. There is no next topic."
                lecture_topics_text = _format_lecture_topics(academic_topics)
            else:
                next_topic_context_text = _format_topic_context(academic_topics[position + 1])
                lecture_topics_text = ""

            if is_first_topic:
                prev_topics = await asyncio.to_thread(_get_previous_lecture_topics, lecture_id)
            else:
                prev_topics = []
            show_previous_lecture_hook = bool(prev_topics)
            previous_lecture_context_text = (
                _format_previous_lecture_topics(prev_topics) if show_previous_lecture_hook else ""
            )

            # 6. プロンプトの組み立て (無関係な分岐の指示文を先に間引く)
            prompt_text = _render_conditional_sections(
                prompt_template,
                {"FINAL_TOPIC": is_final_topic, "FIRST_TOPIC": show_previous_lecture_hook},
            )
            current_keywords = _keyword_strings(topic)
            current_keywords_text = "\n".join(f"- {k}" for k in current_keywords) if current_keywords else "N/A"
            prompt_text = (
                prompt_text
                .replace("${CURRENT_TOPIC_KEYWORDS}", current_keywords_text)
                .replace("${NEXT_TOPIC_CONTEXT}", next_topic_context_text)
                .replace("${LECTURE_TOPICS}", lecture_topics_text)
                .replace("${PREVIOUS_LECTURE_CONTEXT}", previous_lecture_context_text)
                .replace("${TRANSCRIPT_SEGMENT}", trimmed_transcript)
            )

            messages = [
                Message(role="system", content=prompt_text),
                # 末尾で出力言語を再掲する。システムプロンプト(例・文字起こし)がほぼ英語のため、
                # これが無いと英語→日本語の講義でカード全体が英語になることがあった(移行実験で 9回中6回 → 8回中0回)。
                Message(role="user", content=(
                    f"Generate Review Cards for Topic: {topic_title}\n\n"
                    f"Write every card title and every text field in {content_language}."
                )),
            ]

            # 7. LLM 呼び出し
            res = await self.llm.generate(
                model=self.model_alias,
                messages=messages,
                options=options_json
            )

            if not res.json_parse_error and res.output_json and _has_expected_cards(res.output_json):
                result = res.output_json
                result["topic_idx"] = topic_idx # 紐付け用
                # ③ 成功したらR2にキャッシュ保存
                await asyncio.to_thread(storage_service.save_json_cache, cache_path, result)
                all_review_results.append(result)
            else:
                self.logger.log(
                    f"❌ Failed to generate review cards for Topic {topic_idx}: {topic_title}. "
                    f"JSON parse error: {res.json_parse_error}. "
                    f"Finish reason: {res.finish_reason}. "
                    f"Card sequence: {[c.get('card_type') for c in (res.output_json or {}).get('review_cards') or []]}. "
                    f"Output text snippet: {res.output_text[:500] if res.output_text else 'None'}"
                )
                failed_topic_indices.append(topic_idx)

        # ④ 失敗があれば例外を送出する
        if failed_topic_indices:
            raise ValueError(
                f"Review Card generation failed for {len(failed_topic_indices)} topic(s): "
                f"indices={failed_topic_indices}. "
                f"Successfully cached {len(all_review_results)} topic(s). "
                f"Retry will skip cached topics."
            )

        return all_review_results