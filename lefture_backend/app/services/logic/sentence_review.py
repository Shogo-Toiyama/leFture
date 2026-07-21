import re
from collections import defaultdict
from difflib import SequenceMatcher
from nltk.tokenize import sent_tokenize, word_tokenize

from app.services.helpers.helpers import _load_prompt, TaskLogger
from app.services.helpers.llm_unified import UnifiedLLM, Message, LLMOptions


def _estimate_word_timestamps(text: str, start: float, end: float) -> list:
    """元のWhisperセグメントテキストの各単語に、区間内で等間隔と仮定した推定タイムスタンプを振る。

    セグメント内は無音(Pause)が少ない連続発話という前提のもとでの近似。
    ここで得た (word, start, end) は以後書き換えられない不変の基準点として扱う。
    """
    words = word_tokenize(text)
    n = len(words)
    if n == 0:
        return []
    duration = max(end - start, 0.0)
    per_word = duration / n
    return [(w, start + i * per_word, start + (i + 1) * per_word) for i, w in enumerate(words)]


def _align_clean_tokens_to_time(orig_words: list, clean_tokens: list) -> list:
    """元の単語(タイムスタンプ付き)と整形後の単語列を単語単位でアラインメントし、
    整形後の各単語に対応する時刻区間を推定する。

    一致区間(equal)は元の推定タイムスタンプをそのまま採用する「アンカー」として扱い、
    置換/挿入(replace/insert)区間だけ、前後のアンカー時刻の間でトークン数按分する。
    これにより、誤差は書き換えられた局所区間内に閉じ込められ、セグメント全体には波及しない。
    """
    orig_tokens = [w for w, _, _ in orig_words]
    sm = SequenceMatcher(None, orig_tokens, clean_tokens, autojunk=False)

    clean_times = [None] * len(clean_tokens)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            for k in range(i2 - i1):
                clean_times[j1 + k] = (orig_words[i1 + k][1], orig_words[i1 + k][2])
        elif tag in ("replace", "insert"):
            if j2 == j1:
                continue
            before = orig_words[i1 - 1][2] if i1 > 0 else (orig_words[0][1] if orig_words else 0.0)
            after = orig_words[i2][1] if i2 < len(orig_words) else (orig_words[-1][2] if orig_words else before)
            if after < before:
                after = before
            span = after - before
            count = j2 - j1
            per_token = span / count if count > 0 else 0.0
            for k in range(count):
                clean_times[j1 + k] = (before + k * per_token, before + (k + 1) * per_token)
        # "delete" は整形後に対応する単語がないので何もしない

    # 稀に一致区間が全く見つからない(全置換)場合、None が残る。前後の値で穴埋めする。
    for idx in range(len(clean_times)):
        if clean_times[idx] is None:
            prev_end = clean_times[idx - 1][1] if idx > 0 and clean_times[idx - 1] else (
                orig_words[0][1] if orig_words else 0.0
            )
            clean_times[idx] = (prev_end, prev_end)

    return clean_times


def _sentence_time_ranges(clean_text: str, clean_tokens: list, clean_times: list) -> list:
    """整形後テキストを文分割し、各文が消費するトークン範囲から開始/終了時刻を求める。"""
    sentences = [s.strip() for s in sent_tokenize(clean_text) if s.strip()]
    results = []
    idx = 0
    prev_end = clean_times[0][0] if clean_times else 0.0
    for s in sentences:
        s_token_count = len(word_tokenize(s))
        if s_token_count == 0:
            continue
        window = clean_times[idx: idx + s_token_count]
        idx += s_token_count
        if window:
            s_start = window[0][0]
            s_end = window[-1][1]
        else:
            s_start = s_end = prev_end
        if s_start < prev_end:
            s_start = prev_end
        if s_end < s_start:
            s_end = s_start
        results.append((s, s_start, s_end))
        prev_end = s_end
    return results


def _stt_fallback_chunks(chunks: list) -> list:
    """LLMレビューが信頼できない場合に、生Whisperデータをそのまま採用したチャンク群を作る。"""
    absolute_chunks = []
    for chunk in chunks:
        segs = chunk.get("segments_reviewed")
        is_absolute = True
        if segs is None:
            segs = chunk.get("segments_stt") or []
            is_absolute = False

        c_start = chunk.get("start_time", 0.0)
        new_chunk = chunk.copy()
        new_segs = []
        for seg in segs:
            new_seg = seg.copy()
            if not is_absolute:
                new_seg["start"] = seg["start"] + c_start
                new_seg["end"] = seg["end"] + c_start
            new_segs.append(new_seg)
        new_chunk["segments"] = new_segs
        if not new_chunk.get("text"):
            new_chunk["text"] = chunk.get("text_reviewed") or chunk.get("text_stt") or ""
        absolute_chunks.append(new_chunk)
    return absolute_chunks


def _is_reviewed_result_suspiciously_empty(original_chunk: dict, result_chunk: dict) -> bool:
    """STTには中身があったのに、レビュー結果が空になっている（LLMの誤判定が疑われる）かを判定する。"""
    had_content = bool(original_chunk.get("text_stt")) or bool(original_chunk.get("segments_stt"))
    is_empty_result = not (result_chunk or {}).get("text") and not (result_chunk or {}).get("segments")
    return had_content and is_empty_result


class SentenceReviewService:
    def __init__(self, llm: UnifiedLLM, logger: TaskLogger):
        self.llm = llm
        self.logger = logger
        # LiteLLM 経由で呼び出すモデル
        self.model_alias = "gemini/gemini-2.5-flash-lite"

    async def run_with_retry(self, chunks_to_review: list, previous_chunk: dict = None, course_title: str = "", keywords_list: str = "") -> list:
        """
        通常のレビューを1回実行し、STTには中身があったのにレビュー結果が空になっている
        チャンク（LLMが重複/幻聴と誤判定して丸ごと空タグにしたと疑われるケース）があれば、
        バッチ全体をtemperatureを上げて1回だけリトライする。リトライ後もまだ空のチャンクだけ、
        個別に生Whisperデータへフォールバックする（リトライで直った他のチャンクの結果は破棄しない）。
        """
        attempt = await self.run_from_memory(chunks_to_review, previous_chunk, course_title, keywords_list, temperature=0.4)

        orig_by_index = {c["chunk_index"]: c for c in chunks_to_review}
        result_by_index = {rc["chunk_index"]: rc for rc in attempt}

        suspicious = [
            idx for idx, orig in orig_by_index.items()
            if _is_reviewed_result_suspiciously_empty(orig, result_by_index.get(idx))
        ]

        if suspicious:
            self.logger.log(f"⚠️ [Sentence Review] Chunk(s) {suspicious} came back empty despite non-empty STT. Retrying batch with higher temperature...")
            attempt = await self.run_from_memory(chunks_to_review, previous_chunk, course_title, keywords_list, temperature=0.7)
            result_by_index = {rc["chunk_index"]: rc for rc in attempt}

            still_suspicious = [
                idx for idx in suspicious
                if _is_reviewed_result_suspiciously_empty(orig_by_index[idx], result_by_index.get(idx))
            ]
            if still_suspicious:
                self.logger.log(f"⚠️ [Sentence Review] Chunk(s) {still_suspicious} still empty after retry. Falling back to raw STT for these chunks only.")
                for idx in still_suspicious:
                    result_by_index[idx] = _stt_fallback_chunks([orig_by_index[idx]])[0]

            attempt = sorted(result_by_index.values(), key=lambda c: c["chunk_index"])

        return attempt

    async def run_from_memory(self, chunks_to_review: list, previous_chunk: dict = None, course_title: str = "", keywords_list: str = "", temperature: float = 0.4) -> list:
        self.logger.log(f"🧠 [Sentence Review] Starting review for {len(chunks_to_review)} chunks...")

        orig_map = {}
        target_xml = ""
        
        # 前回のチャンク
        if previous_chunk:
            prev_segs = previous_chunk.get("segments_reviewed")
            is_absolute = True
            if prev_segs is None:
                prev_segs = previous_chunk.get("segments_stt") or []
                is_absolute = False

            if prev_segs:
                prev_start_time = previous_chunk.get("start_time")
                if prev_start_time is None:
                    raise ValueError(f"CRITICAL: prev_chunk (index={previous_chunk.get('chunk_index')}) is missing start_time. Cannot calculate absolute timestamps.")
                last_segs = prev_segs[-3:]
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
            
            cur_segs = chunk.get("segments_reviewed")
            is_absolute = True
            if cur_segs is None:
                cur_segs = chunk.get("segments_stt") or []
                is_absolute = False

            for seg in cur_segs:
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
        options = LLMOptions(temperature=temperature, max_completion_tokens=4000, reasoning_effort="low")

        # 💡 UnifiedLLM を使って非同期実行！
        try:
            res = await self.llm.generate(model=self.model_alias, messages=messages, options=options)
            llm_output = res.output_text
        except Exception as e:
            self.logger.log(f"⚠️ [Sentence Review] LLM call failed: {e}")
            self.logger.log(f"   [Fallback] Reverting to original Whisper transcripts for this batch due to API error.")
            return _stt_fallback_chunks(chunks_to_review)

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
            return _stt_fallback_chunks(chunks_to_review)

        # 元セグメントのタイムスタンプは書き換えず、まず単語単位の推定時刻を振っておく。
        # これがバッチをまたいでも変化しない「不変の基準点」になる。
        orig_words_by_sid = {
            sid: _estimate_word_timestamps(seg["text"], seg["start"], seg["end"])
            for sid, seg in orig_map.items()
        }

        # 空タグ(マージ/削除)は直前の非空タグのグループに吸収する。
        # このとき、元単語の推定タイムスタンプ列も丸ごと連結して保持する(区間を潰さない)。
        groups = []
        current_group = None
        leading_empty_words = []  # 最初の非空タグより前に来た空タグの取りこぼし防止

        for sid in orig_map.keys():
            text = parsed_dict.get(sid, "")
            orig_seg = orig_map[sid]

            if text:
                current_group = {
                    "text": text,
                    "orig_words": leading_empty_words + list(orig_words_by_sid[sid]),
                    "chunk_index": orig_seg["chunk_index"],
                    "confidence": orig_seg["confidence"],
                }
                leading_empty_words = []
                groups.append(current_group)
            else:
                if current_group is not None:
                    current_group["orig_words"].extend(orig_words_by_sid[sid])
                else:
                    leading_empty_words.extend(orig_words_by_sid[sid])

        # 単語アラインメントで整形後テキストに時刻を復元し、文単位に分割する。
        final_segments = []
        for group in groups:
            clean_tokens = word_tokenize(group["text"])
            if not clean_tokens or not group["orig_words"]:
                continue

            clean_times = _align_clean_tokens_to_time(group["orig_words"], clean_tokens)

            for sentence_text, s_start, s_end in _sentence_time_ranges(group["text"], clean_tokens, clean_times):
                final_segments.append({
                    "text": sentence_text,
                    "start": round(s_start, 3),
                    "end": round(s_end, 3),
                    "chunk_index": get_assigned_chunk_index(s_start, group["chunk_index"]),
                    "confidence": group["confidence"],
                })

        updated_chunks_dict = defaultdict(lambda: {"segments": [], "text": ""})
        counters = defaultdict(int)

        # 1. chunks_to_review の初期化
        for chunk in chunks_to_review:
            c_idx = chunk["chunk_index"]
            updated_chunks_dict[c_idx] = chunk.copy()
            updated_chunks_dict[c_idx]["segments"] = []
            updated_chunks_dict[c_idx]["text"] = ""

        # 2. previous_chunk の未編集セグメント（前半部分）の退避と初期化
        if previous_chunk:
            prev_segs = previous_chunk.get("segments_reviewed")
            is_absolute = True
            if prev_segs is None:
                prev_segs = previous_chunk.get("segments_stt") or []
                is_absolute = False

            prev_idx = previous_chunk["chunk_index"]
            prev_start_time = previous_chunk.get("start_time") or 0.0
            
            # 後半3つ以外のセグメント（編集対象外の過去データ）を取り出す
            earlier_segs = []
            for seg in prev_segs[:-3]:
                new_seg = seg.copy()
                if not is_absolute:
                    new_seg["start"] += prev_start_time
                    new_seg["end"] += prev_start_time
                earlier_segs.append(new_seg)

            # previous_chunk 用の初期データをセット
            updated_chunks_dict[prev_idx] = previous_chunk.copy()
            updated_chunks_dict[prev_idx]["segments"] = earlier_segs
            updated_chunks_dict[prev_idx]["text"] = " ".join(s["text"] for s in earlier_segs) + " " if earlier_segs else ""
            counters[prev_idx] = len(earlier_segs)

        # 3. レビュー結果の割り当て
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