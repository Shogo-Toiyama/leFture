import os
import json
import time
import base64
from pathlib import Path
from dotenv import load_dotenv
import litellm
import requests

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
review_cards_file = current_dir / 'review_cards_data.json'
core_extraction_file = current_dir / 'core_extraction_data.json'
prompt_file = current_dir / 'prompt.txt'

def format_image_generation_inputs():
    try:
        # Load mock inputs
        with open(review_cards_file, 'r', encoding='utf-8') as f:
            review_cards_results = json.load(f)
        
        with open(core_extraction_file, 'r', encoding='utf-8') as f:
            core_data = json.load(f)
            
        # Build academic titles dictionary
        academic_titles = {}
        for topic in core_data.get("topics", []):
            t_idx = topic.get("idx")
            t_title = topic.get("title")
            if t_idx is not None and t_title:
                academic_titles[t_idx] = t_title

        # Map inputs to the new prompt format
        minimized_topics = []
        for res in review_cards_results:
            topic_idx = res.get("topic_idx")
            academic_title = academic_titles.get(topic_idx, "Unknown Topic")

            # extract Hook
            hook_card = next((c for c in res.get("review_cards", []) if c.get("card_type") == "hook"), {})
            hook_text = ""
            for block in hook_card.get("content_blocks", []):
                if isinstance(block, dict) and block.get("type") in ["quote", "paragraph", "callout"] and block.get("text"):
                    hook_text = block["text"]
                    break

            # extract Summary
            summary = ""
            for mt in res.get("topic_evaluation", {}).get("micro_topics", []):
                if isinstance(mt, dict) and mt.get("summary"):
                    summary = mt["summary"]
                    break

            minimized_topics.append({
                "topic_idx": topic_idx,
                "title": academic_title,
                "hook_text": hook_text.strip(),
                "summary": summary.strip()
            })
            
        return minimized_topics
    except Exception as e:
        print(f"Error preparing input data: {e}")
        return None

def test_image_generation():
    # -------------------------------------------------------------------------
    # ⚙️ EXECUTION MODE CONFIGURATION
    # -------------------------------------------------------------------------
    # "BOTH"        - Generate prompts using LLM and render images using Cloudflare
    # "PROMPT_ONLY" - Generate prompts using LLM only (saves image_prompts_*.json)
    # "IMAGE_ONLY"  - Skip LLM prompt generation, load from existing JSON, and render images
    EXECUTION_MODE = "BOTH"  # Change to "BOTH", "PROMPT_ONLY", or "IMAGE_ONLY"
    # -------------------------------------------------------------------------

    # Read prompt
    try:
        with open(prompt_file, 'r', encoding='utf-8') as f:
            system_prompt = f.read().strip()
    except FileNotFoundError:
        print(f"Error: '{prompt_file}' not found.")
        return

    # Prepare inputs
    minimized_topics = format_image_generation_inputs()
    if not minimized_topics:
        print("Error: No input data prepared.")
        return

    # Models to test
    models = [
        "together_ai/Prism-ML/Ternary-Bonsai-27B",
        "gemini/gemini-2.5-flash-lite",
        "gemini/gemini-3.1-flash-lite"
    ]

    # Model Pricing per 1,000,000 tokens
    PRICING_PER_1M = {
        "together_ai/Prism-ML/Ternary-Bonsai-27B": {"input": 0.05, "output": 0.20},  # 暫定（gpt-oss-20b同額）
        "together_ai/openai/gpt-oss-20b": {"input": 0.05, "output": 0.20},
        "gemini/gemini-2.5-flash-lite": {"input": 0.10, "output": 0.40},
        "gemini/gemini-2.5-flash": {"input": 0.30, "output": 2.50},
        "gemini/gemini-3.1-flash-lite": {"input": 0.25, "output": 1.50}
    }

    total_cost = 0.0
    total_time = 0.0
    total_flux_cost = 0.0

    for model in models:
        model_safe_name = model.split('/')[-1]
        output_file_json = current_dir / f"image_prompts_{model_safe_name}.json"
        output_file_txt = current_dir / f"image_prompts_{model_safe_name}.txt"
        
        result_dict = None

        if EXECUTION_MODE in ["BOTH", "PROMPT_ONLY"]:
            print(f"\n==================================================")
            print(f"🤖 Starting image prompt generation for model: {model} ({EXECUTION_MODE} mode)")
            print(f"==================================================")
            
            messages = [
                {
                    "role": "system",
                    "content": system_prompt
                },
                {
                    "role": "user",
                    "content": f"Generate visual prompts for these topics:\n{json.dumps(minimized_topics, ensure_ascii=False)}"
                }
            ]

            kwargs = {
                "model": model,
                "messages": messages,
                "temperature": 0.5,
                "response_format": {"type": "json_object"}
            }

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

                try:
                    result_dict = json.loads(result_json_str)
                    with open(output_file_json, 'w', encoding='utf-8') as f:
                        json.dump(result_dict, f, ensure_ascii=False, indent=2)
                    print(f"✅ Saved JSON to: {output_file_json.name}")
                except json.JSONDecodeError:
                    with open(output_file_txt, 'w', encoding='utf-8') as f:
                        f.write(result_json_str)
                    print(f"⚠️ Response is not valid JSON. Saved raw text to: {output_file_txt.name}")

            except Exception as e:
                elapsed_time = time.perf_counter() - start_time
                print(f"❌ Failed model {model} after {elapsed_time:.2f}s: {e}")
                continue
        else:
            # IMAGE_ONLY mode
            print(f"\n==================================================")
            print(f"📂 Loading existing prompts for model: {model} (IMAGE_ONLY mode)")
            print(f"==================================================")
            if output_file_json.exists():
                try:
                    with open(output_file_json, 'r', encoding='utf-8') as f:
                        result_dict = json.load(f)
                    print(f"✅ Loaded JSON from: {output_file_json.name}")
                except Exception as e:
                    print(f"❌ Failed to load existing JSON: {e}")
            else:
                print(f"❌ Error: '{output_file_json.name}' does not exist. Please run with 'BOTH' or 'PROMPT_ONLY' first.")

        # Print preview and run image rendering
        if result_dict:
            # Print preview of World Building and Scene descriptions
            wb = result_dict.get("global_art_direction") or result_dict.get("world_building", {})
            world_setting = wb.get("world_setting") or wb.get("art_medium", "N/A")
            print(f"🌍 World Setting: {world_setting}")
            print(f"🎨 Style Suffix: {wb.get('flux_style_suffix')}")
            
            prompts_list = result_dict.get("image_prompts", [])
            for p in prompts_list:
                print(f" - Topic {p.get('topic_idx')}: {p.get('flux_scene_description')[:100]}...")
            
            if EXECUTION_MODE in ["BOTH", "IMAGE_ONLY"]:
                # Try rendering images via Cloudflare if credentials are available
                cf_account = os.getenv("CLOUDFLARE_ACCOUNT_ID")
                cf_token = os.getenv("CLOUDFLARE_API_KEY")
                w = 512
                h = 512
                if cf_account and cf_token:
                    print(f"\n🎨 Cloudflare credentials found! Rendering images using @cf/black-forest-labs/flux-2-klein-4b...")
                    for p in prompts_list:
                        topic_idx = p.get("topic_idx")
                        scene_desc = p.get("flux_scene_description", "")
                        style_suffix = wb.get("flux_style_suffix", "")
                        combined_prompt = f"{scene_desc}, {style_suffix}".strip().strip(",")
                        
                        print(f" 🖼️ Generating image for Topic {topic_idx} using prompt: '{combined_prompt[:80]}...'")
                        url = f"https://api.cloudflare.com/client/v4/accounts/{cf_account}/ai/run/@cf/black-forest-labs/flux-2-klein-4b"
                        try:
                            if "flux-2" in url or "klein" in url:
                                headers = {
                                    "Authorization": f"Bearer {cf_token}"
                                }
                                files = {
                                    "prompt": (None, combined_prompt),
                                    "width": (None, str(w)),
                                    "height": (None, str(h))
                                }
                                cf_res = requests.post(url, headers=headers, files=files, timeout=60)
                            else:
                                headers = {
                                    "Authorization": f"Bearer {cf_token}",
                                    "Content-Type": "application/json"
                                }
                                payload = {
                                    "prompt": combined_prompt,
                                    "width": w,
                                    "height": h,
                                    "num_steps": 4
                                }
                                cf_res = requests.post(url, headers=headers, json=payload, timeout=60)
                            if cf_res.ok:
                                content_type = cf_res.headers.get("Content-Type", "")
                                image_bytes = None
                                if "application/json" in content_type:
                                    data = cf_res.json()
                                    if data.get("success"):
                                        image_bytes = base64.b64decode(data["result"]["image"])
                                    else:
                                        print(f"   ❌ Cloudflare API Error: {data}")
                                elif "image/" in content_type:
                                    image_bytes = cf_res.content
                                
                                if image_bytes:
                                    # Calculate flux tiles and cost (width 384, height 672)
                                    tiles = ((w + 511) // 512) * ((h + 511) // 512)
                                    flux_cost = tiles * 0.000287
                                    total_flux_cost += flux_cost

                                    out_img_path = current_dir / f"image_topic_{topic_idx}_{model_safe_name}.jpg"
                                    with open(out_img_path, "wb") as img_f:
                                        img_f.write(image_bytes)
                                    print(f"   ✅ Saved image to: {out_img_path.name} (Estimated Flux Cost: ${flux_cost:.6f})")
                            else:
                                print(f"   ❌ Cloudflare response error ({cf_res.status_code}): {cf_res.text}")
                        except Exception as img_err:
                            print(f"   ❌ Failed to render image for Topic {topic_idx}: {img_err}")
                else:
                    print("\n⚠️ Cloudflare credentials (CLOUDFLARE_ACCOUNT_ID / CLOUDFLARE_API_KEY) not found. Skipping image rendering.")
            else:
                print("\nℹ️ PROMPT_ONLY mode selected. Skipping Cloudflare image rendering.")

    print(f"\n==================================================")
    print(f"🏁 Execution Summary")
    print(f"==================================================")
    print(f"⏱️ Total Time: {total_time:.2f} seconds")
    print(f"💰 LLM Cost: ${total_cost:.6f}")
    print(f"🎨 Flux Cost: ${total_flux_cost:.6f}")
    print(f"💵 Combined Total Cost: ${(total_cost + total_flux_cost):.6f}")

if __name__ == "__main__":
    test_image_generation()
