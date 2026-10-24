#!/usr/bin/env python3
"""
Interactive / CLI Prompt Compression with LLMLingua-2
Usage:
    .venv/bin/python interactive_compress.py --text "your long text here..." --rate 0.5
    .venv/bin/python interactive_compress.py --file path/to/document.txt --rate 0.4
    .venv/bin/python interactive_compress.py --model bert --text "日本語の文章..." --rate 0.5
"""

import argparse
import sys
import time
from pathlib import Path

# Add lefture_backend to sys.path
project_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(project_root / "lefture_backend"))

from app.services.chat_attachments import estimate_tokens
from llmlingua import PromptCompressor

MODELS = {
    "xlm": "microsoft/llmlingua-2-xlm-roberta-large-meetingbank",
    "bert": "microsoft/llmlingua-2-bert-base-multilingual-cased-meetingbank",
}


def main():
    parser = argparse.ArgumentParser(description="LLMLingua-2 Text Compression Playground")
    parser.add_argument("--text", type=str, help="Text string to compress")
    parser.add_argument("--file", type=str, help="Path to text/markdown file to compress")
    parser.add_argument("--rate", type=float, default=0.5, help="Target retention rate (0.1 - 0.9, default 0.5)")
    parser.add_argument(
        "--model",
        type=str,
        choices=["xlm", "bert"],
        default="xlm",
        help="Model choice: 'xlm' (XLM-RoBERTa-large, best quality) or 'bert' (mBERT-cased, faster/lighter)",
    )
    parser.add_argument("--device", type=str, default="cpu", help="Device ('cpu' or 'mps' on Apple Silicon)")
    args = parser.parse_args()

    if not args.text and not args.file:
        print("Error: Please provide either --text or --file.")
        sys.exit(1)

    if args.file:
        filepath = Path(args.file)
        if not filepath.exists():
            print(f"Error: File not found at {filepath}")
            sys.exit(1)
        raw_text = filepath.read_text(encoding="utf-8")
    else:
        raw_text = args.text

    model_name = MODELS[args.model]
    print(f"Loading {args.model} ({model_name}) on device={args.device}...")
    t0 = time.perf_counter()
    compressor = PromptCompressor(
        model_name=model_name,
        device_map=args.device,
        use_llmlingua2=True,
    )
    print(f"Loaded in {time.perf_counter() - t0:.2f}s")

    orig_tokens = estimate_tokens(raw_text)
    print(f"\nOriginal: {len(raw_text)} chars, ~{orig_tokens} estimated tokens")
    print(f"Compressing at target rate: {args.rate} ...")

    t1 = time.perf_counter()
    result = compressor.compress_prompt(
        raw_text,
        rate=args.rate,
        force_tokens=["\n", "```", "{", "}", "(", ")", ";", ":", "def ", "class ", "if ", "for "],
        chunk_end_tokens=[".", "\n", "。", "！", "？"],
    )
    elapsed_ms = (time.perf_counter() - t1) * 1000

    compressed_text = result.get("compressed_prompt", "")
    comp_tokens = estimate_tokens(compressed_text)
    ratio = (comp_tokens / max(1, orig_tokens)) * 100

    print(f"\n--- Compression Result ({elapsed_ms:.1f}ms) ---")
    print(f"Compressed: {len(compressed_text)} chars, ~{comp_tokens} estimated tokens ({ratio:.1f}% of original)")
    print("-" * 50)
    print(compressed_text)
    print("-" * 50)


if __name__ == "__main__":
    main()
