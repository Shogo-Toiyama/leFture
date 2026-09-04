import os
import json
import time
import re
from pathlib import Path
from typing import Any, Dict, List
from dotenv import load_dotenv
import litellm

# ==========================================
# ⚙️ テスト設定 (ここを編集してテスト実行)
# ==========================================
# テストしたいトピック番号 (例: 1 や 2。すべてのトピックを回す場合は "ALL")
TARGET_TOPIC_IDX = 5

# 言語設定
LANGUAGE = "English"

# テスト対象モデル
TEST_MODELS = [
    "gemini/gemini-2.5-flash",
    # "gemini/gemini-3.5-flash-lite",
    # "openai/gpt-4o-mini",
    # "openai/gpt-5-mini",
    "openai/gpt-5.6-luna",
]

# 価格テーブル (USD per 1,000,000 tokens)
PRICING_PER_1M = {
    "gemini/gemini-2.5-flash": {"input": 0.30, "output": 2.50},
    "gemini/gemini-2.5-flash-lite": {"input": 0.10, "output": 0.40},
    "gemini/gemini-3.1-flash-lite": {"input": 0.25, "output": 1.50},
    "gemini/gemini-3.5-flash-lite": {"input": 0.25, "output": 1.50},
    "openai/gpt-4o": {"input": 2.50, "output": 10.00},
    "openai/gpt-4o-mini": {"input": 0.15, "output": 0.60},
    "openai/gpt-5-mini": {"input": 0.15, "output": 0.60},
    "openai/gpt-5.6-luna": {"input": 0.20, "output": 0.40},
}

# ==========================================
# ⚙️ 環境変数の読み込み & APIキー設定
# ==========================================
current_dir = Path(__file__).resolve().parent
load_dotenv()

# contents_generation/.env
parent_env = current_dir.parent.parent / ".env"
if parent_env.exists():
    load_dotenv(dotenv_path=parent_env)

# プロジェクトルートの .env
root_env = current_dir.parent.parent.parent / ".env"
if root_env.exists():
    load_dotenv(dotenv_path=root_env)

# OpenAI API Key 解決 (SHOGO_S_OPENAI_API_KEY をフォールバック)
openai_key = os.getenv("OPENAI_API_KEY") or os.getenv("SHOGO_S_OPENAI_API_KEY") or os.getenv("KAY_S_OPENAI_API_KEY")
if openai_key:
    os.environ["OPENAI_API_KEY"] = openai_key

# Together AI API Key 解決
together_key = os.getenv("TOGETHER_AI_API_KEY") or os.getenv("TOGETHERAI_API_KEY") or os.getenv("TOGETHER_API_KEY")
if together_key:
    os.environ["TOGETHER_AI_API_KEY"] = together_key
    os.environ["TOGETHERAI_API_KEY"] = together_key

litellm.drop_params = True

# ==========================================
# 🛠️ 本番互換ヘルパー関数
# ==========================================
def sid_to_int(sid: str) -> int:
    if not isinstance(sid, str):
        return -1
    digits = re.sub(r"\D", "", sid)
    return int(digits) if digits else -1

def render_conditional_sections(template: str, conditions: Dict[str, bool]) -> str:
    cond_block_re = re.compile(
        r"<!--IF:(?P<name>\w+)-->(?P<if_branch>.*?)(?:<!--ELSE-->(?P<else_branch>.*?))?<!--END_IF-->",
        re.DOTALL,
    )
    def _replace(m: re.Match) -> str:
        name = m.group("name")
        if_branch = m.group("if_branch") or ""
        else_branch = m.group("else_branch") or ""
        return if_branch if conditions.get(name, False) else else_branch

    return cond_block_re.sub(_replace, template)

def format_topic_context(topic: Dict[str, Any]) -> str:
    title = topic.get("title", "")
    keywords = topic.get("keywords") or []
    keyword_str = ", ".join(keywords) if keywords else "N/A"
    return f"Title: {title}\nKey Terms: {keyword_str}"

def format_lecture_topics(topics: List[Dict[str, Any]]) -> str:
    lines = []
    for t in topics:
        title = t.get("title", "")
        keywords = ", ".join(t.get("keywords") or [])
        lines.append(f"- {title} (Key Terms: {keywords})" if keywords else f"- {title}")
    return "\n".join(lines)

def clean_and_parse_json(raw_text: str):
    text = raw_text.strip()
    try:
        return json.loads(text)
    except Exception:
        pass

    match = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", text)
    if match:
        try:
            return json.loads(match.group(1).strip())
        except Exception:
            pass

    start_bracket = -1
    start_char = ''
    for idx, c in enumerate(text):
        if c in ('{', '['):
            start_bracket = idx
            start_char = c
            break

    end_char = '}' if start_char == '{' else ']'
    end_bracket = text.rfind(end_char)

    if start_bracket != -1 and end_bracket != -1 and end_bracket > start_bracket:
        try:
            return json.loads(text[start_bracket:end_bracket + 1])
        except Exception:
            pass

    return None

# ==========================================
# 🚀 メイン実行ロジック
# ==========================================
def test_review_card_generation():
    # 1. テンプレートの読み込み
    template_path = current_dir / "prompt_template.txt"
    if not template_path.exists():
        template_path = current_dir / "prompt.txt"
    if not template_path.exists():
        print(f"❌ Error: Prompt template file not found.")
        return
    template = template_path.read_text(encoding="utf-8")

    # 2. core_data.json の読み込み
    core_data_path = current_dir / "core_data.json"
    if not core_data_path.exists():
        print(f"❌ Error: '{core_data_path.name}' not found. Please place it in this directory.")
        return
    with open(core_data_path, "r", encoding="utf-8") as f:
        core_data = json.load(f)

    # 3. transcript_data.json の読み込み
    transcript_path = current_dir / "transcript_data.json"
    if not transcript_path.exists():
        transcript_path = current_dir / "transcript.json"
    if not transcript_path.exists():
        print(f"❌ Error: Neither 'transcript_data.json' nor 'transcript.json' found in this directory.")
        print(f"   Please place your lecture transcript JSON file here.")
        return
    with open(transcript_path, "r", encoding="utf-8") as f:
        transcript_data = json.load(f)

    # 4. ACADEMIC トピックの抽出
    academic_topics = [t for t in core_data.get("topics", []) if t.get("topic_type") == "ACADEMIC"]
    if not academic_topics:
        print("❌ Error: No ACADEMIC topics found in core_data.json.")
        return

    # テスト対象トピックの絞り込み
    if TARGET_TOPIC_IDX == "ALL":
        target_topics = academic_topics
    else:
        target_topics = [t for t in academic_topics if t.get("idx") == TARGET_TOPIC_IDX]
        if not target_topics:
            print(f"❌ Error: Topic with idx={TARGET_TOPIC_IDX} not found among ACADEMIC topics.")
            return

    output_dir = current_dir / "output"
    output_dir.mkdir(parents=True, exist_ok=True)

    total_cost = 0.0
    total_time = 0.0

    print(f"\n==================================================")
    print(f"🃏 Starting Review Cards Evaluation")
    print(f"📁 Core Data: {core_data_path.name} ({len(academic_topics)} academic topics)")
    print(f"📄 Transcript: {transcript_path.name} ({len(transcript_data)} utterances)")
    print(f"🎯 Target Topics: {[t.get('idx') for t in target_topics]}")
    print(f"🤖 Models: {len(TEST_MODELS)}")
    print(f"==================================================")

    last_position = len(academic_topics) - 1

    for topic in target_topics:
        topic_idx = topic.get("idx")
        topic_title = topic.get("title", "")
        start_sid = topic.get("start_sid", "")
        end_sid = topic.get("end_sid", "")
        
        position = next((i for i, t in enumerate(academic_topics) if t.get("idx") == topic_idx), 0)
        is_final_topic = (position == last_position)

        start_num = sid_to_int(start_sid)
        end_num = sid_to_int(end_sid)

        # トランスクリプト切り出し (本番同等のフィルタリング)
        trimmed_lines = []
        for item in transcript_data:
            sid = item.get("sid", "")
            sid_num = sid_to_int(sid)
            text = item.get("text", "")

            if start_num <= sid_num <= end_num:
                # Role Classification確率データがある場合のフィルタ
                probs = item.get("all_probabilities")
                if probs:
                    c_prob = probs.get("CONTENT", 0.0)
                    i_prob = probs.get("INTERACTION", 0.0)
                    if c_prob < 0.10 and i_prob < 0.50:
                        continue
                elif item.get("role") and item.get("role") not in ["CONTENT", "INTERACTION"]:
                    continue

                trimmed_lines.append(f"{sid}: {text}")

        if not trimmed_lines:
            print(f"⚠️ Warning: No valid sentences found for Topic {topic_idx} ({start_sid} - {end_sid}). Skipping.")
            continue

        trimmed_transcript = "\n".join(trimmed_lines)

        # プロンプトプレースホルダーの構築
        if is_final_topic:
            next_topic_context_text = "This is the final topic of today's lecture. There is no next topic."
            lecture_topics_text = format_lecture_topics(academic_topics)
        else:
            next_topic_context_text = format_topic_context(academic_topics[position + 1])
            lecture_topics_text = ""

        # 言語指示
        lang_instr = f"All generated content must be written in natural, clear, and engaging {LANGUAGE}."

        # プロンプトの組み立て
        prompt_text = render_conditional_sections(
            template,
            {"FINAL_TOPIC": is_final_topic, "FIRST_TOPIC": False}
        )
        prompt_text = (
            prompt_text
            .replace("${LANGUAGE_INSTRUCTIONS}", lang_instr)
            .replace("${NEXT_TOPIC_CONTEXT}", next_topic_context_text)
            .replace("${LECTURE_TOPICS}", lecture_topics_text)
            .replace("${PREVIOUS_LECTURE_CONTEXT}", "")
            .replace("${TRANSCRIPT_SEGMENT}", trimmed_transcript)
        )

        print(f"\n--------------------------------------------------")
        print(f"📌 Topic {topic_idx}: {topic_title} ({len(trimmed_lines)} lines, {start_sid}〜{end_sid})")
        print(f"--------------------------------------------------")

        messages = [
            {"role": "system", "content": prompt_text},
            {"role": "user", "content": f"Generate Review Cards for Topic: {topic_title}"}
        ]

        for model in TEST_MODELS:
            print(f"\n==================================================")
            print(f"🤖 Testing model: {model}")
            print(f"==================================================")

            kwargs = {
                "model": model,
                "messages": messages,
                "temperature": 0.3,
            }

            # 推論系モデル（gpt-5.6, o1, o3系）はカスタムtemperature非対応のため除外
            if any(k in model for k in ["gpt-5.6", "o1", "o3", "o4"]):
                kwargs.pop("temperature", None)

            if "gpt-oss" in model:
                kwargs["reasoning_effort"] = "medium"
            else:
                kwargs["response_format"] = {"type": "json_object"}

            start_time = time.perf_counter()
            try:
                response = litellm.completion(**kwargs)
                elapsed_time = time.perf_counter() - start_time
                raw_output = response.choices[0].message.content or ""

                usage = getattr(response, "usage", None)
                in_tokens = getattr(usage, "prompt_tokens", 0) if usage else 0
                out_tokens = getattr(usage, "completion_tokens", 0) if usage else 0
                tokens_total = getattr(usage, "total_tokens", 0) if usage else 0

                price = PRICING_PER_1M.get(model, {"input": 0.0, "output": 0.0})
                cost = (in_tokens / 1_000_000.0) * price["input"] + (out_tokens / 1_000_000.0) * price["output"]

                total_cost += cost
                total_time += elapsed_time

                # コンソール表示 (プレビューなし)
                print(f"⏱️ Done in {elapsed_time:.2f} seconds.")
                print(f"📊 Token usage - Input: {in_tokens:,}, Output: {out_tokens:,}, Total: {tokens_total:,}")
                print(f"💰 Estimated Cost: ${cost:.6f}")

                model_safe_name = model.replace("/", "_").replace(":", "_")
                parsed_json = clean_and_parse_json(raw_output)

                if parsed_json is not None:
                    output_file = output_dir / f"review_cards_topic_{topic_idx}_{model_safe_name}.json"
                    with open(output_file, "w", encoding="utf-8") as f:
                        json.dump(parsed_json, f, ensure_ascii=False, indent=2)
                    print(f"💾 Saved JSON to: {output_file.relative_to(current_dir)}")
                else:
                    output_file = output_dir / f"review_cards_topic_{topic_idx}_{model_safe_name}.txt"
                    with open(output_file, "w", encoding="utf-8") as f:
                        f.write(raw_output)
                    print(f"⚠️ Could not parse as JSON. Saved raw text to: {output_file.relative_to(current_dir)}")

            except Exception as e:
                elapsed_time = time.perf_counter() - start_time
                print(f"❌ Failed model {model} after {elapsed_time:.2f}s: {e}")

    print(f"\n==================================================")
    print(f"🏁 Execution Summary")
    print(f"==================================================")
    print(f"⏱️ Total Time: {total_time:.2f} seconds")
    print(f"💰 Total Cost: ${total_cost:.6f}")

if __name__ == "__main__":
    test_review_card_generation()
