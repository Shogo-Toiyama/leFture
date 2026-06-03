import sys
from pathlib import Path
from dotenv import load_dotenv

# Ensure we can import from contents_generation
current_dir = Path(__file__).resolve().parent
sys.path.append(str(current_dir.parents[1]))

from contents_generation.scripts.llm.llm_unified import UnifiedLLM, LLMOptions, Message, CostCollector

def main():
    # Load dotenv from the contents_generation folder
    env_path = current_dir.parent / ".env"
    print(f"Loading env from: {env_path}")
    load_dotenv(dotenv_path=env_path)

    print("Initializing UnifiedLLM with provider='deepseek'...")
    try:
        llm = UnifiedLLM(provider="deepseek")
    except Exception as e:
        print(f"Failed to initialize client: {e}")
        return

    print("Testing TEXT generation...")
    messages = [
        Message(role="system", content="You are a helpful assistant."),
        Message(role="user", content="Say 'Hello, deepseek-v4-flash is working!' in Japanese.")
    ]
    options = LLMOptions(temperature=0.2, output_type="text")
    
    try:
        res = llm.generate(model="v4_flash", messages=messages, options=options)
        print("\n--- Response ---")
        print(res.output_text)
        print("----------------")
        print(f"Prompt Tokens: {res.usage.input_tokens}")
        print(f"Completion Tokens: {res.usage.output_tokens}")
        print(f"Reasoning Tokens: {res.usage.reasoning_tokens}")
        print(f"Total Tokens: {res.usage.total_tokens}")
        print(f"Estimated Cost: ${res.estimated_cost_usd:.6f}")
    except Exception as e:
        print(f"Error during text generation: {e}")

    print("\nTesting JSON generation...")
    messages = [
        Message(role="system", content="You are a helpful assistant. Output JSON only."),
        Message(role="user", content="List three colors in a JSON object with a key named 'colors' as an array of strings.")
    ]
    options = LLMOptions(temperature=0.2, output_type="json")
    
    try:
        res = llm.generate(model="v4_flash", messages=messages, options=options)
        print("\n--- Response (JSON) ---")
        print(res.output_json)
        print("----------------")
        print(f"Prompt Tokens: {res.usage.input_tokens}")
        print(f"Completion Tokens: {res.usage.output_tokens}")
        print(f"Reasoning Tokens: {res.usage.reasoning_tokens}")
        print(f"Total Tokens: {res.usage.total_tokens}")
        print(f"Estimated Cost: ${res.estimated_cost_usd:.6f}")
    except Exception as e:
        print(f"Error during JSON generation: {e}")

if __name__ == "__main__":
    main()
