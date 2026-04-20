import os
import json
from groq import Groq
from pydantic import BaseModel, ConfigDict
from typing import List
from dotenv import load_dotenv

load_dotenv()

class Topic(BaseModel):
    model_config = ConfigDict(extra="forbid")
    idx: int
    title: str
    start_sid: str
    end_sid: str

class FunFactIdea(BaseModel):
    model_config = ConfigDict(extra="forbid")
    start_sid: str
    end_sid: str
    concept_focus: str
    exciting_angle: str

class LectureAnalysis(BaseModel):
    model_config = ConfigDict(extra="forbid")
    keywords: List[str]
    summary: str
    title: str
    topics: List[Topic]
    fun_fact_idea: FunFactIdea

# ファイル名の設定
input_file = 'transcript_data.json'
transcript_file = 'simple_transcript.txt'
output_file = 'core_extractions.json'

def simplify_transcript():
    try:
        # JSONファイルの読み込み
        with open(input_file, 'r', encoding='utf-8') as f_in:
            data = json.load(f_in)
        
        # テキストファイルへの書き出し
        with open(transcript_file, 'w', encoding='utf-8') as f_out:
            for item in data:
                # sidとtextを取得（万が一欠損していてもエラーにならないようにgetを使用）
                sid = item.get('sid', '')
                text = item.get('text', '')
                
                # 指定されたフォーマットで書き込み
                f_out.write(f"{sid}: {text}\n")
                
        print(f"大成功！無事に '{transcript_file}' が作成されました！")
        
    except FileNotFoundError:
        print(f"エラー: '{input_file}' が見つかりません。同じ階層にあるか確認してください！")
    except json.JSONDecodeError:
        print(f"エラー: '{input_file}' のJSONフォーマットが崩れているようです。")

def test_core_extraction():
    try:
        with open(transcript_file, 'r', encoding='utf-8') as f:
            transcript_text = f.read()
    except FileNotFoundError:
        print(f"エラー: {input_file} が見つかりません。先に抽出プログラムを実行してください！")
        return
    
    system_prompt = """You are an expert academic content analyzer and metadata extractor. 
Your objective is to read a complete university lecture transcript and extract highly structured metadata in a single pass. 

### <STUDENT_PROFILE>
The user consuming this output is a university student majoring in Computer Science, actively developing their own applications, and aiming for Software Engineer internships. They have a strong interest in AI, cloud technologies, and entrepreneurship (like bootstrapping a startup). 
*(Note: Use this profile ONLY to tailor the "fun_fact_idea" section).*
### </STUDENT_PROFILE>

### INPUT FORMAT
A plain text transcript where each line represents a sentence or utterance. 
The format is strict: `<sid>: <text>`

### TASK & CONSTRAINTS (Follow this exact sequence for your reasoning)

1. KEYWORDS (`keywords`):
- First, scan the text and extract 5 to 10 core academic concepts and fundamental technical terms that are essential for the student's exam preparation and deep understanding of the lecture.
- CRITICAL: Do NOT include analogies, anecdotal terms, or specific examples used for illustration, even if they are mentioned frequently. Focus strictly on the theoretical and architectural concepts.

2. SUMMARY (`summary`):
- Based on the key concepts, write exactly 2-3 sentences summarizing the overall lecture.

3. LECTURE TITLE (`title`):
- Condense the summary into a concise, highly specific title for the entire lecture (max 10 words).

4. TOPIC SEGMENTATION (`topics`):
- Now, understanding the full context, partition the transcript into 2 to 6 balanced, non-overlapping segments.
- Partition the transcript into 2 to 6 balanced, non-overlapping segments (topics).
- Target Count: NEVER exceed 6 topics unless the professor explicitly declares a higher number at the start.
- Boundary Detection: Look for rhetorical transitions ("Moving on to..."), sustained role+content shifts, or clear conceptual changes (e.g., theory -> application).
- Merge Policy: Combine tightly coupled parts (e.g., definition + immediate example). Do not split if the conceptual focus remains the same.
- Output the `start_sid` and `end_sid` matching the exact `<sid>` provided in the input.

5. FUN FACT IDEA (`fun_fact_idea`):
- Finally, review the <STUDENT_PROFILE> and find ONE specific concept from the topics that can be creatively connected to the student's interests.
- Goal: Generate an *idea* (not the full final text) that will make the student say, "Wow, this lecture connects to what I want to do!"
- `start_sid` & `end_sid`: Identify the exact segment where this concept is taught.
- `concept_focus`: The specific term/concept from the lecture.
- `exciting_angle`: 1-2 sentences explaining *how* to connect this concept to the student's interests (CS, App Dev, AI, Entrepreneurship) in a way that provides a new perspective or excites them about their future career/projects.

### OUTPUT FORMAT
You must return ONLY a valid, minified JSON object matching the exact structure below. Do not include markdown formatting (like ```json), explanations, or preamble.

{
  "keywords": ["<string>", "<string>"],
  "summary": "<string>",
  "title": "<string>",
  "topics": [
    {
      "idx": <int>,
      "title": "<string>",
      "start_sid": "<string>",
      "end_sid": "<string>"
    }
  ],
  "fun_fact_idea": {
    "start_sid": "<string>",
    "end_sid": "<string>",
    "concept_focus": "<string>",
    "exciting_angle": "<string>"
  }
}
"""
    
    client = Groq()
    completion = client.chat.completions.create(
        model="openai/gpt-oss-20b",
        messages=[
            {
                "role": "system",
                "content": system_prompt
            },
            {
                "role": "user",
                "content": f"Here is the transcript data:\n\n{transcript_text}"
            }
        ],
        response_format={
            "type": "json_schema",
            "json_schema": {
                "name": "lecture_analysis_schema",
                "strict": True,
                "schema": LectureAnalysis.model_json_schema()
            }
        }
    )
    result_json_str = completion.choices[0].message.content

    try:
        result_dict = json.loads(result_json_str)
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(result_dict, f, ensure_ascii=False, indent=2)

    except json.JSONDecodeError:
        txt_output_file = output_file.replace('.json', '.txt')
        with open(txt_output_file, 'w', encoding='utf-8') as f:
            f.write(result_json_str)
        print(f"JSONじゃなかったのでtxtとして保存しました: {txt_output_file}")

    print(f"大成功！分析結果が {output_file} に保存されました！")
    print("\n--- 出力プレビュー（一部） ---")
    print(f"タイトル: {result_dict.get('title')}")
    print(f"トピック数: {len(result_dict.get('topics', []))}個")

if __name__ == "__main__":
    # simplify_transcript()
    test_core_extraction()