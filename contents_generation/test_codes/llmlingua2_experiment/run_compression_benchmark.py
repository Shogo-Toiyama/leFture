#!/usr/bin/env python3
"""
LLMLingua-2 Prompt Compression Benchmark
Evaluates compression ratio, latency, and retention of technical terms / code syntax.
"""

import os
import sys
import time
import json
from pathlib import Path

# Add lefture_backend to path for helper utilities
project_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(project_root / "lefture_backend"))

from app.services.chat_attachments import estimate_tokens
from llmlingua import PromptCompressor


def load_test_samples():
    samples = {}

    # Sample 1: CS118 Midterm Review Transcript (English, Technical / Conversational)
    transcript_path = project_root / "contents_generation/test_codes/cs118_midterm/midterm_review_transcript.txt"
    if transcript_path.exists():
        with open(transcript_path, "r", encoding="utf-8") as f:
            full_text = f.read()
        # Take the first ~3,000 characters (Q1-Q4 discussion on packet switching, dispersion, bit stuffing)
        samples["cs118_midterm_transcript"] = {
            "type": "english_lecture_transcript",
            "text": full_text[:3500],
            "key_terms": ["packet switching", "chromatic dispersion", "byte stuffing", "bit stuffing", "Nyquist limit", "100 megabit"]
        }

    # Sample 2: Technical Problem with Code (C Code, CRC, Bit Stuffing)
    samples["code_problem"] = {
        "type": "code_and_explanation",
        "text": """Question: CRC implementation in C.
The generator polynomial is 1001 (x^3 + 1). Here is the proposed C function:
```c
uint16_t compute_crc(const char *input, int len) {
    uint16_t crc = 0;
    for (int i = 0; i <= len + 3; i++) {
        crc = (crc << 1);
        if (i < len) {
            crc |= (input[i] == '1' ? 1 : 0);
        }
        if (crc & 0x10) { // Check leading bit (bit 4)
            crc ^= 0x09;  // XOR with generator 1001
        }
    }
    return crc & 0x07;
}
```
Explain the two potential bugs in this code related to loop bound padding and the leading bit mask.""",
        "key_terms": ["compute_crc", "uint16_t", "crc = (crc << 1)", "crc ^= 0x09", "1001", "padding"]
    }

    # Sample 3: Japanese Lecture Explanation (Network Layers & Congestion)
    samples["japanese_lecture"] = {
        "type": "japanese_technical_notes",
        "text": """【講義要約：通信路の容量とビット復元】
通信ネットワークは階層ごとの抽象化を通じてデータを運び、物理層ではビットを媒体に適した信号へ変換します。
通信速度は帯域幅、雑音、信号対雑音比（SNR）によって制約され、シャノン容量限界（Shannon Capacity Limit）がその理論的上限を示します。
一方、ビットの同期とクロック回復（Clock Recovery）は、受信側が信号から正しくビットを復元することを支えます。
サンプリング点が中央から50%以上ずれると隣接ビットを誤読するため、11ビット伝送では1ビットあたり最大4.5%（安全側2.5%）の時計ずれが限界となります。""",
        "key_terms": ["シャノン容量限界", "信号対雑音比", "クロック回復", "50%以上", "4.5%", "11ビット伝送"]
    }

    return samples


def run_benchmark():
    samples = load_test_samples()
    print(f"Loaded {len(samples)} test samples.")

    # Initialize LLMLingua-2
    # Model choices:
    # 1. "microsoft/llmlingua-2-xlm-roberta-large-meetingbank" (Default English/MeetingBank)
    # 2. "microsoft/llmlingua-2-bert-base-multilingual-cased-meetingbank" (Multilingual mBERT)
    model_name = "microsoft/llmlingua-2-xlm-roberta-large-meetingbank"
    print(f"\n📦 Loading LLMLingua-2 model: {model_name}...")
    t_start = time.perf_counter()
    compressor = PromptCompressor(
        model_name=model_name,
        device_map="cpu",
        use_llmlingua2=True,
    )
    load_time_sec = round(time.perf_counter() - t_start, 2)
    print(f"✅ Model loaded in {load_time_sec}s")

    test_rates = [0.6, 0.4] # 60% retention, 40% retention
    results = {
        "model_name": model_name,
        "load_time_sec": load_time_sec,
        "runs": []
    }

    print("\n" + "="*80)
    print(f"{'Sample':<25} | {'Rate':<5} | {'Orig Tok':<9} | {'Comp Tok':<9} | {'Ratio':<7} | {'Time (ms)':<9}")
    print("="*80)

    for name, data in samples.items():
        original_text = data["text"]
        orig_est_tokens = estimate_tokens(original_text)

        for rate in test_rates:
            t0 = time.perf_counter()
            # Compress prompt
            compressed = compressor.compress_prompt(
                original_text,
                rate=rate,
                force_tokens=["\n", "```", "{", "}", "(", ")", ";", ":"],
                chunk_end_tokens=[".", "\n", "。", "！", "？"]
            )
            elapsed_ms = round((time.perf_counter() - t0) * 1000, 1)

            comp_text = compressed.get("compressed_prompt", "")
            comp_est_tokens = estimate_tokens(comp_text)
            actual_ratio = round((comp_est_tokens / max(1, orig_est_tokens)) * 100, 1)

            # Check retention of key terms
            term_retention = {}
            for term in data.get("key_terms", []):
                term_retention[term] = term.lower() in comp_text.lower()

            retained_count = sum(1 for v in term_retention.values() if v)
            total_terms = len(term_retention)

            print(f"{name:<25} | {rate:<5} | {orig_est_tokens:<9} | {comp_est_tokens:<9} | {actual_ratio:<6}% | {elapsed_ms:<9}ms (Terms: {retained_count}/{total_terms})")

            results["runs"].append({
                "sample_name": name,
                "target_rate": rate,
                "original_chars": len(original_text),
                "compressed_chars": len(comp_text),
                "original_tokens_estimate": orig_est_tokens,
                "compressed_tokens_estimate": comp_est_tokens,
                "actual_retention_ratio_pct": actual_ratio,
                "latency_ms": elapsed_ms,
                "term_retention": term_retention,
                "compressed_preview": comp_text[:400] + ("..." if len(comp_text) > 400 else "")
            })

    output_path = project_root / "contents_generation/test_codes/llmlingua2_experiment/compression_benchmark_results.json"
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

    print("="*80)
    print(f"\n📊 Full results and previews saved to: {output_path}")


if __name__ == "__main__":
    run_benchmark()
