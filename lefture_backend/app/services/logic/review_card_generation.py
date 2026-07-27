# app/services/logic/review_card_generation.py
import json
import time
import asyncio
from typing import Any, Dict, List

from app.core.r2_storage import storage_service
from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM
from app.services.helpers.helpers import TaskLogger, _load_prompt, _sid_to_int, _build_bilingual_gloss_instruction

class ReviewCardGenerationService:
    def __init__(self, llm: UnifiedLLM, logger: TaskLogger):
        self.llm = llm
        self.logger = logger
        self.model_alias = "gemini/gemini-2.5-flash"

    async def run_from_memory(
        self,
        role_classified_data: List[Dict[str, Any]],
        core_data: Dict[str, Any],
        mapping_result: Dict[str, Any],
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
        options_json = LLMOptions(output_type="json", temperature=0.3)
        
        all_review_results = []

        # 1. ACADEMIC なトピックだけを抽出
        academic_topics = [t for t in core_data.get("topics", []) if t.get("topic_type") == "ACADEMIC"]

        failed_topic_indices = []

        for topic in academic_topics:
            topic_idx = topic.get("idx")
            topic_title = topic.get("title")
            
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

            # 5. プロンプトの組み立て
            prompt_text = prompt_template.replace(
                "${COURSE_TOPIC_MAP}", json.dumps(mapping_result, ensure_ascii=False)
            ).replace(
                "${TRANSCRIPT_SEGMENT}", trimmed_transcript
            )

            messages = [
                Message(role="system", content=prompt_text),
                Message(role="user", content=f"Generate Review Cards for Topic: {topic_title}")
            ]

            # 6. LLM 呼び出し
            res = await self.llm.generate(
                model=self.model_alias,
                messages=messages,
                options=options_json
            )

            if not res.json_parse_error and res.output_json:
                result = res.output_json
                result["topic_idx"] = topic_idx # 紐付け用
                # ③ 成功したらR2にキャッシュ保存
                await asyncio.to_thread(storage_service.save_json_cache, cache_path, result)
                all_review_results.append(result)
            else:
                self.logger.log(
                    f"❌ Failed to generate review cards for Topic {topic_idx}: {topic_title}. "
                    f"JSON parse error: {res.json_parse_error}. "
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