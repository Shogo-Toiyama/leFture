import re
from collections import defaultdict
from nltk.tokenize import sent_tokenize

from app.services.helpers.helpers import _load_prompt, TaskLogger
from app.services.helpers.llm_unified import UnifiedLLM, Message, LLMOptions

class SentenceReviewService:
    def __init__(self, llm: UnifiedLLM, logger: TaskLogger):
        self.llm = llm
        self.logger = logger
        # LiteLLM 経由で呼び出すモデル
        self.model_alias = "together_ai/openai/gpt-oss-120b"

    async def run_from_memory(self, chunks_to_review: list, previous_chunk: dict = None, course_title: str = "", keywords_list: str = "") -> list:
        self.logger.log(f"🧠 [Sentence Review] Starting review for {len(chunks_to_review)} chunks...")

        # 💡 Helper to convert relative timestamps in chunks to absolute if they are not already absolute
        def make_chunks_absolute(chunks: list) -> list:
            absolute_chunks = []
            for chunk in chunks:
                if chunk.get("status") == "REVIEWED":
                    # Already absolute
                    absolute_chunks.append(chunk)
                    continue
                c_start = chunk.get("start_time", 0.0)
                new_chunk = chunk.copy()
                new_segs = []
                for seg in chunk.get("segments", []):
                    new_seg = seg.copy()
                    new_seg["start"] = seg["start"] + c_start
                    new_seg["end"] = seg["end"] + c_start
                    new_segs.append(new_seg)
                new_chunk["segments"] = new_segs
                absolute_chunks.append(new_chunk)
            return absolute_chunks

        orig_map = {}
        target_xml = ""
        
        # 前回のチャンク
        if previous_chunk and previous_chunk.get("segments"):
            prev_start_time = previous_chunk.get("start_time")
            if prev_start_time is None:
                raise ValueError(f"CRITICAL: prev_chunk (index={previous_chunk.get('chunk_index')}) is missing start_time. Cannot calculate absolute timestamps.")
            last_segs = previous_chunk["segments"][-3:]
            is_absolute = previous_chunk.get("status") == "REVIEWED"
            for seg in last_segs:
                sid = seg["sid"]
                seg_start = seg["start"]
                seg_end = seg["end"]
                if not is_absolute:
                    seg_start += prev_start_time
                    seg_end += prev_start_time
                orig_map[sid] = {
                    "text": seg["text"],
                    "start": seg_start,
                    "end": seg_end,
                    "chunk_index": previous_chunk.get("chunk_index"),
                    "confidence": seg.get("confidence", 0.99)
                }
                target_xml += f"<{sid}>{seg['text']}</{sid}>"

        # 今回のチャンク
        for chunk in chunks_to_review:
            chunk_start_time = chunk.get("start_time")
            if chunk_start_time is None:
                raise ValueError(f"CRITICAL: chunk (index={chunk.get('chunk_index')}) is missing start_time. Cannot calculate absolute timestamps.")
            is_absolute = chunk.get("status") == "REVIEWED"
            for seg in chunk.get("segments", []):
                sid = seg["sid"]
                seg_start = seg["start"]
                seg_end = seg["end"]
                if not is_absolute:
                    seg_start += chunk_start_time
                    seg_end += chunk_start_time
                orig_map[sid] = {
                    "text": seg["text"],
                    "start": seg_start,
                    "end": seg_end,
                    "chunk_index": chunk.get("chunk_index"),
                    "confidence": seg.get("confidence", 0.99)
                }
                target_xml += f"<{sid}>{seg['text']}</{sid}>"

        # 前回と今回のチャンクの時間境界を記録
        chunk_boundaries = []
        if previous_chunk and previous_chunk.get("start_time") is not None:
            chunk_boundaries.append({
                "chunk_index": previous_chunk["chunk_index"],
                "start_time": previous_chunk["start_time"]
            })
        for chunk in chunks_to_review:
            if chunk.get("start_time") is not None:
                chunk_boundaries.append({
                    "chunk_index": chunk["chunk_index"],
                    "start_time": chunk["start_time"]
                })
        
        # start_timeでソート
        chunk_boundaries.sort(key=lambda x: x["start_time"])

        def get_assigned_chunk_index(seg_abs_start: float, orig_idx: int) -> int:
            if not chunk_boundaries:
                return orig_idx
            # 一番近い過去のチャンクインデックスを探す
            assigned_idx = chunk_boundaries[0]["chunk_index"]
            for boundary in chunk_boundaries:
                if seg_abs_start >= boundary["start_time"]:
                    assigned_idx = boundary["chunk_index"]
                else:
                    break
            return assigned_idx

        # プロンプト生成
        prompt_template = _load_prompt("sentence_review_prompt.txt")
        prompt = prompt_template.format(
            course_title=course_title,
            keywords_list=keywords_list,
            target_xml_text=target_xml
        )

        self.logger.log(f"   [LLM] Calling LiteLLM API ({self.model_alias})...")
        
        messages = [Message(role="user", content=prompt)]
        options = LLMOptions(temperature=0.4, max_completion_tokens=4000, reasoning_effort="low")
        
        # 💡 UnifiedLLM を使って非同期実行！
        try:
            res = await self.llm.generate(model=self.model_alias, messages=messages, options=options)
            llm_output = res.output_text
        except Exception as e:
            self.logger.log(f"⚠️ [Sentence Review] LLM call failed: {e}")
            self.logger.log(f"   [Fallback] Reverting to original Whisper transcripts for this batch due to API error.")
            return make_chunks_absolute(chunks_to_review)

        # パース処理 (元のロジックのまま)
        matches = re.findall(r'<s(\d{6})>(.*?)</s\1>', llm_output, re.DOTALL)
        parsed_dict = {f"s{sid}": text.strip() for sid, text in matches}

        # --- Fallback Mechanism ---
        total_orig = len(orig_map)
        parsed_count = len(parsed_dict)
        success_rate = parsed_count / total_orig if total_orig > 0 else 1.0

        if total_orig > 0 and success_rate < 0.3:
            snippet = llm_output[-500:] if len(llm_output) > 500 else llm_output
            self.logger.log(f"⚠️ [Sentence Review] PARSING FAILURE! Success rate: {success_rate:.1%} ({parsed_count}/{total_orig}). Output may be truncated.")
            self.logger.log(f"   [LLM Output Snippet]: {snippet}")
            self.logger.log(f"   [Fallback] Reverting to original Whisper transcripts for this batch.")
            return make_chunks_absolute(chunks_to_review)

        merged_segments = []
        last_non_empty_seg = None

        for sid in orig_map.keys():
            text = parsed_dict.get(sid, "")
            orig_seg = orig_map[sid]

            if text:
                new_seg = {
                    "text": text,
                    "start": orig_seg["start"],
                    "end": orig_seg["end"],
                    "chunk_index": orig_seg["chunk_index"],
                    "confidence": orig_seg["confidence"]
                }
                
                if not merged_segments and orig_seg["start"] > orig_map[list(orig_map.keys())[0]]["start"]:
                    new_seg["start"] = orig_map[list(orig_map.keys())[0]]["start"]

                merged_segments.append(new_seg)
                last_non_empty_seg = new_seg
            else:
                if last_non_empty_seg is not None:
                    last_non_empty_seg["end"] = max(last_non_empty_seg["end"], orig_seg["end"])

        # NLTK分割
        final_segments = []
        for seg in merged_segments:
            sentences = sent_tokenize(seg["text"])
            sentences = [s.strip() for s in sentences if s.strip()]

            if not sentences:
                continue

            if len(sentences) == 1:
                seg["chunk_index"] = get_assigned_chunk_index(seg["start"], seg["chunk_index"])
                final_segments.append(seg)
            else:
                total_chars = sum(len(s) for s in sentences)
                total_duration = seg["end"] - seg["start"]
                
                curr_start = seg["start"]
                for s in sentences:
                    ratio = len(s) / total_chars if total_chars > 0 else 0
                    dur = total_duration * ratio
                    
                    final_segments.append({
                        "text": s,
                        "start": round(curr_start, 3),
                        "end": round(curr_start + dur, 3),
                        "chunk_index": get_assigned_chunk_index(curr_start, seg["chunk_index"]),
                        "confidence": seg["confidence"]
                    })
                    curr_start += dur

        updated_chunks_dict = defaultdict(lambda: {"segments": [], "text": ""})
        counters = defaultdict(int)

        for chunk in chunks_to_review:
            c_idx = chunk["chunk_index"]
            updated_chunks_dict[c_idx] = chunk.copy()
            updated_chunks_dict[c_idx]["segments"] = []
            updated_chunks_dict[c_idx]["text"] = ""

        for seg in final_segments:
            c_idx = seg["chunk_index"]
            counters[c_idx] += 1
            seg["sid"] = f"s{c_idx:03d}{counters[c_idx]:03d}"
            
            updated_chunks_dict[c_idx]["segments"].append(seg)
            updated_chunks_dict[c_idx]["text"] += seg["text"] + " "

        result_chunks = []
        for c_idx in sorted(updated_chunks_dict.keys()):
            updated_chunks_dict[c_idx]["text"] = updated_chunks_dict[c_idx]["text"].strip()
            updated_chunks_dict[c_idx]["chunk_index"] = c_idx
            result_chunks.append(updated_chunks_dict[c_idx])

        self.logger.log(f"✅ [Sentence Review] Review completed perfectly.")
        return result_chunks