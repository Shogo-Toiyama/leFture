import os
import json
import time
from pathlib import Path
from dotenv import load_dotenv
import litellm

# Load environment variables
current_dir = Path(__file__).resolve().parent

# Load local .env first
load_dotenv()

# Load contents_generation/.env if exists
parent_env = current_dir.parent.parent / ".env"
if parent_env.exists():
    print(f"Loading environment from: {parent_env}")
    load_dotenv(dotenv_path=parent_env)

# Verify API Keys
gemini_key = os.getenv("GEMINI_API_KEY")
together_key = os.getenv("TOGETHER_AI_API_KEY") or os.getenv("TOGETHERAI_API_KEY") or os.getenv("TOGETHER_API_KEY")
print(f"GEMINI_API_KEY: {'Found' if gemini_key else 'Not Found'}")
print(f"TOGETHER_AI_API_KEY / TOGETHERAI_API_KEY: {'Found' if together_key else 'Not Found'}")

# Ensure Together API key is set for LiteLLM
if together_key:
    os.environ["TOGETHER_AI_API_KEY"] = together_key
    os.environ["TOGETHERAI_API_KEY"] = together_key

# Drop unsupported params
litellm.drop_params = True

# File paths
input_file = current_dir / 'transcript_data.json'
prompt_file = current_dir / 'prompt.txt'

def format_transcript_from_json():
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        lines = []
        for item in data:
            sid = item.get('sid', '')
            text = item.get('text', '')
            if sid:
                lines.append(f"{sid}: {text}")
        
        return "\n".join(lines)
    except FileNotFoundError:
        print(f"Error: '{input_file}' not found.")
        return None
    except json.JSONDecodeError:
        print(f"Error: Failed to parse '{input_file}' as JSON.")
        return None

def test_core_extraction():
    # Read prompt
    try:
        with open(prompt_file, 'r', encoding='utf-8') as f:
            system_prompt = f.read().strip()
    except FileNotFoundError:
        print(f"Error: '{prompt_file}' not found.")
        return

    # Format transcript
    transcript_text = format_transcript_from_json()
    if not transcript_text:
        print("Error: No transcript text available.")
        return

    # Models to test
    models = [
        "together_ai/openai/gpt-oss-120b",
        # "gemini/gemini-2.5-flash-lite",
        # "gemini/gemini-2.5-flash"
    ]

    # Model Pricing per 1,000,000 tokens (Standard pricing)
    PRICING_PER_1M = {
        "together_ai/openai/gpt-oss-120b": {"input": 0.15, "output": 0.60},
        "together_ai/openai/gpt-oss-20b": {"input": 0.05, "output": 0.20},
        "gemini/gemini-2.5-flash-lite": {"input": 0.10, "output": 0.40},
        "gemini/gemini-2.5-flash": {"input": 0.30, "output": 2.50}
    }

    total_cost = 0.0
    total_time = 0.0

    for model in models:
        print(f"\n==================================================")
        print(f"🤖 Starting extraction for model: {model}")
        print(f"==================================================")
        
        messages = [
            {
                "role": "system",
                "content": system_prompt
            },
            {
                "role": "user",
                "content": f"Here is the transcript data:\n\n{transcript_text}"
            }
        ]

        kwargs = {
            "model": model,
            "messages": messages,
            "temperature": 0.4,
            "response_format": {"type": "json_object"}
        }

        # Handle reasoning effort for GPT-OSS models
        if "gpt-oss" in model:
            kwargs["reasoning_effort"] = "medium"

        start_time = time.perf_counter()
        try:
            response = litellm.completion(**kwargs)
            elapsed_time = time.perf_counter() - start_time
            result_json_str = response.choices[0].message.content or ""
            
            # Extract tokens
            usage = getattr(response, 'usage', None)
            in_tokens = getattr(usage, 'prompt_tokens', 0) if usage else 0
            out_tokens = getattr(usage, 'completion_tokens', 0) if usage else 0
            total_tokens = getattr(usage, 'total_tokens', 0) if usage else 0
            
            # Estimate cost
            price = PRICING_PER_1M.get(model, {"input": 0.0, "output": 0.0})
            cost = (in_tokens / 1_000_000.0) * price["input"] + (out_tokens / 1_000_000.0) * price["output"]
            
            total_cost += cost
            total_time += elapsed_time

            print(f"⏱️ Done in {elapsed_time:.2f} seconds.")
            print(f"📊 Token usage - Input: {in_tokens}, Output: {out_tokens}, Total: {total_tokens}")
            print(f"💰 Estimated Cost: ${cost:.6f}")

            # Define output filename based on model name
            model_safe_name = model.split('/')[-1]
            output_file_json = current_dir / f"core_extractions_{model_safe_name}.json"
            output_file_txt = current_dir / f"core_extractions_{model_safe_name}.txt"

            try:
                result_dict = json.loads(result_json_str)
                with open(output_file_json, 'w', encoding='utf-8') as f:
                    json.dump(result_dict, f, ensure_ascii=False, indent=2)
                print(f"✅ Saved JSON to: {output_file_json.name}")
                print(f"📝 Title: {result_dict.get('title')}")
                print(f"📚 Topics extracted: {len(result_dict.get('topics', []))}")
            except json.JSONDecodeError:
                with open(output_file_txt, 'w', encoding='utf-8') as f:
                    f.write(result_json_str)
                print(f"⚠️ Response is not valid JSON. Saved raw text to: {output_file_txt.name}")
                print("Raw response preview:")
                print(result_json_str[:300])

        except Exception as e:
            elapsed_time = time.perf_counter() - start_time
            print(f"❌ Failed model {model} after {elapsed_time:.2f}s: {e}")

    print(f"\n==================================================")
    print(f"🏁 Execution Summary")
    print(f"==================================================")
    print(f"⏱️ Total Time: {total_time:.2f} seconds")
    print(f"💰 Total Cost: ${total_cost:.6f}")

if __name__ == "__main__":
    test_core_extraction()