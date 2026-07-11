import os
import json
import time
from pathlib import Path
from dotenv import load_dotenv
import litellm

# 1. 環境変数の読み込み
current_dir = Path(__file__).resolve().parent
load_dotenv()

# プロジェクトルートの.envもロード
parent_env = current_dir.parent.parent / ".env"
if parent_env.exists():
    print(f"Loading env from parent: {parent_env}")
    load_dotenv(dotenv_path=parent_env)

# APIキーの検証
print("=== API Keys Status ===")
print(f"GEMINI_API_KEY: {'Found' if os.getenv('GEMINI_API_KEY') else 'Not Found'}")
print(f"TOGETHER_AI_API_KEY: {'Found' if os.getenv('TOGETHER_AI_API_KEY') or os.getenv('TOGETHERAI_API_KEY') else 'Not Found'}")

# Together API key の明示的な設定
together_key = os.getenv("TOGETHER_AI_API_KEY") or os.getenv("TOGETHERAI_API_KEY")
if together_key:
    os.environ["TOGETHER_AI_API_KEY"] = together_key
    os.environ["TOGETHERAI_API_KEY"] = together_key

litellm.drop_params = True

# 2. テストデータの読み込み
input_json_path = current_dir / "input_announcement_generation.json"
prompt_path = current_dir / "announcement_extraction_prompt.txt"

if not input_json_path.exists():
    # パス調整（親ディレクトリなど）
    input_json_path = current_dir / "input_announcement_generation.json"

if not prompt_path.exists():
    # フォールバックパス
    prompt_path = current_dir.parent.parent / "lefture_backend" / "app" / "services" / "prompts" / "announcement_extraction_prompt.txt"

print("\n=== File Paths ===")
print(f"Input file: {input_json_path} (Exists: {input_json_path.exists()})")
print(f"Prompt file: {prompt_path} (Exists: {prompt_path.exists()})")

if not input_json_path.exists() or not prompt_path.exists():
    print("Error: Missing input or prompt file. Please configure paths correctly.")
    exit(1)

with open(input_json_path, "r", encoding="utf-8") as f:
    input_data = json.load(f)
formatted_transcript = input_data.get("formatted_transcript", "")

with open(prompt_path, "r", encoding="utf-8") as f:
    prompt_template = f.read()

prompt_text = prompt_template.replace("${TRANSCRIPT_INPUT}", formatted_transcript)

# 3. テスト対象モデルの定義
# さまざまなプロバイダーとモデルで比較テストを行います
TEST_MODELS = [
    # "together_ai/openai/gpt-oss-20b"
    # "together_ai/openai/gpt-oss-120b",
    "gemini/gemini-2.5-flash-lite"
]

def test_model(model_name: str):
    print(f"\nTesting model: {model_name}...")
    
    messages = [
        {"role": "system", "content": prompt_text},
        {"role": "user", "content": "Please extract the actionable announcements as requested in JSON."}
    ]
    
    kwargs = {
        "model": model_name,
        "messages": messages,
        "temperature": 0.3,
    }
    
    # gpt-oss 以外のモデルでは JSON モードを明示的に指定
    if "gpt-oss" not in model_name:
        kwargs["response_format"] = {"type": "json_object"}
    else:
        # GPT-OSS系は reasoning_effort を指定する傾向があるため合わせる
        kwargs["reasoning_effort"] = "low"
        
    start_time = time.perf_counter()
    try:
        response = litellm.completion(**kwargs)
        elapsed = time.perf_counter() - start_time
        output_text = response.choices[0].message.content or ""
        
        # パース試行
        parsed = None
        parse_err = None
        
        # GPT-OSSの場合は helpers.py と同様にクリーンアップ抽出を模倣
        cleaned_text = output_text.strip()
        if "gpt-oss" in model_name and cleaned_text.startswith('{"final'):
            # 簡易パースクリーンアップ
            colon_idx = cleaned_text.find(':')
            if colon_idx != -1:
                inner_idx = -1
                for idx in range(colon_idx + 1, len(cleaned_text)):
                    if cleaned_text[idx] in ('{', '['):
                        inner_idx = idx
                        break
                if inner_idx != -1:
                    last_idx = cleaned_text.rfind('}')
                    if last_idx > inner_idx:
                        cleaned_text = cleaned_text[inner_idx:last_idx]
        
        try:
            parsed = json.loads(cleaned_text) if cleaned_text else None
        except Exception as e:
            parse_err = str(e)
            
        print(f"  [SUCCESS] Elapsed: {elapsed:.2f}s")
        print(f"  Raw text length: {len(output_text)}")
        print(f"  Raw text preview: {repr(output_text[:200])}")
        print(f"  Parsed JSON type: {type(parsed)}")
        if isinstance(parsed, dict):
            print(f"  Keys in JSON: {list(parsed.keys())}")
            if "announcements" in parsed:
                print(f"  Announcements count: {len(parsed['announcements'])}")
            else:
                print("  [WARNING] 'announcements' key is MISSING!")
            
            # Save output JSON to file
            output_file = current_dir / f"{model_name.replace('/', '_')}_output.json"
            with open(output_file, "w", encoding="utf-8") as out_f:
                json.dump(parsed, out_f, indent=2, ensure_ascii=False)
            print(f"  [SAVED] Saved JSON to: {output_file}")
        else:
            print(f"  [WARNING] Parsed JSON is not a dictionary! Got: {parsed}")
        if parse_err:
            print(f"  [ERROR] JSON Parse Error: {parse_err}")
            
    except Exception as e:
        elapsed = time.perf_counter() - start_time
        print(f"  [FAILED] Elapsed: {elapsed:.2f}s, Error: {e}")

if __name__ == "__main__":
    print(f"Transcript Length: {len(formatted_transcript)} characters")
    print(f"Prompt Template Length: {len(prompt_template)} characters")
    
    for model in TEST_MODELS:
        test_model(model)
    print("\nScript prepared successfully. Run this script in your environment using:")
    print("python3 contents_generation/test_codes/test_announcement_models.py")
