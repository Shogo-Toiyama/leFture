#!/usr/bin/env python3
"""
Multilingual LLMLingua-2 Compression Benchmark
Evaluates Japanese (JA), Chinese (ZH), Portuguese (PT), and Russian (RU)
using real technical text from Wikipedia on Transmission Control Protocol (TCP).
"""

import sys
import os
import re
import json
import time
from pathlib import Path

# Add backend to path
project_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(project_root / "lefture_backend"))

import trafilatura
from app.services.chat_attachments import estimate_tokens
from llmlingua import PromptCompressor

URLS = {
    "ja": "https://ja.wikipedia.org/wiki/Transmission_Control_Protocol",
    "zh": "https://zh.wikipedia.org/wiki/%E4%BC%A0%E8%BE%93%E6%8E%A7%E5%88%B6%E5%8D%8F%E8%AE%AE",
    "pt": "https://pt.wikipedia.org/wiki/Transmission_Control_Protocol",
    "ru": "https://ru.wikipedia.org/wiki/Transmission_Control_Protocol",
}

KEY_TERMS = {
    "ja": [
        "3ウェイ・ハンドシェイク",
        "シーケンス番号",
        "輻輳制御",
        "チェックサム",
        "フロー制御",
        "スライディングウィンドウ",
        "再送"
    ],
    "zh": [
        "三次握手",
        "序列号",
        "拥塞控制",
        "校验和",
        "滑动窗口",
        "流量控制",
        "重传"
    ],
    "pt": [
        "aperto de mão",
        "sequência",
        "congestionamento",
        "checksum",
        "fluxo",
        "janela deslizante",
        "retransmissão"
    ],
    "ru": [
        "рукопожатие",
        "последовательности",
        "перегрузкой",
        "контрольная сумма",
        "потоком",
        "скользящ",
        "повторн"
    ]
}


def split_into_chunks(text: str):
    return [c.strip() for c in re.split(r"\n\s*\n", text) if c.strip()]


def should_protect_block(chunk: str) -> bool:
    if "```" in chunk:
        return True
    if "+-+-+-+" in chunk or "| :---" in chunk or chunk.count("|") >= 4:
        return True
    op_pattern = r"(?:<<|>>|&|\||\^|==|<=|>=|!=|typedef\s+struct|uint\d+_t)"
    if re.search(op_pattern, chunk):
        return True
    return False


def run_benchmark():
    exp_dir = Path(__file__).resolve().parent
    raw_dir = exp_dir / "multilingual_raw"
    raw_dir.mkdir(exist_ok=True)

    print("Loading LLMLingua-2 on CPU...")
    t0 = time.perf_counter()
    compressor = PromptCompressor(
        model_name="microsoft/llmlingua-2-xlm-roberta-large-meetingbank",
        device_map="cpu",
        use_llmlingua2=True,
    )
    print(f"Loaded in {time.perf_counter() - t0:.2f}s")

    results = {}

    for lang, url in URLS.items():
        print(f"\n========================================================")
        print(f"🌍 Fetching & Testing: {lang.upper()} ({url})")
        print(f"========================================================")

        raw_file = raw_dir / f"tcp_{lang}.txt"
        if raw_file.exists():
            full_text = raw_file.read_text(encoding="utf-8")
        else:
            downloaded = trafilatura.fetch_url(url)
            full_text = trafilatura.extract(downloaded, include_formatting=True) or ""
            raw_file.write_text(full_text, encoding="utf-8")

        # Take first ~8,000 chars (representative article section)
        sample_text = full_text[:8000]
        orig_tokens = estimate_tokens(sample_text)
        chunks = split_into_chunks(sample_text)
        print(f"Sample size: {len(sample_text)} chars, ~{orig_tokens} tokens, {len(chunks)} chunks")

        lang_result = {
            "lang": lang,
            "char_count": len(sample_text),
            "orig_tokens": orig_tokens,
            "rates": []
        }

        # Test Rate 0.7 (standard soft) and Rate 0.6 (max soft)
        for rate in [0.7, 0.6]:
            t_comp = time.perf_counter()
            processed_chunks = []

            for chunk in chunks:
                if should_protect_block(chunk):
                    processed_chunks.append(chunk)
                else:
                    c_res = compressor.compress_prompt(
                        chunk,
                        rate=rate,
                        force_tokens=["\n", "{", "}", "(", ")"],
                        force_reserve_digit=True,
                        chunk_end_tokens=[".", "\n", "。", "！", "？", "；", "…"]
                    )
                    processed_chunks.append(c_res.get("compressed_prompt", ""))

            elapsed_ms = (time.perf_counter() - t_comp) * 1000
            comp_text = "\n\n".join(processed_chunks)
            comp_tokens = estimate_tokens(comp_text)
            retention_pct = round((comp_tokens / max(1, orig_tokens)) * 100, 1)
            reduction_pct = round(100 - retention_pct, 1)

            # Check term retention
            terms = KEY_TERMS.get(lang, [])
            term_status = {}
            for term in terms:
                in_orig = term.lower() in sample_text.lower()
                in_comp = term.lower() in comp_text.lower()
                if in_orig:
                    term_status[term] = in_comp

            retained = sum(1 for v in term_status.values() if v)
            total = len(term_status)
            term_pct = round((retained / max(1, total)) * 100, 1)

            print(f"Rate: {rate} | {orig_tokens} -> {comp_tokens} tok ({reduction_pct}% reduced) | Terms: {retained}/{total} ({term_pct}%) | Time: {elapsed_ms:.1f}ms")

            lang_result["rates"].append({
                "rate": rate,
                "elapsed_ms": round(elapsed_ms, 1),
                "comp_chars": len(comp_text),
                "comp_tokens": comp_tokens,
                "reduction_pct": reduction_pct,
                "retention_pct": retention_pct,
                "term_retention": term_status,
                "term_retention_pct": term_pct,
                "compressed_preview": comp_text[:600]
            })

        results[lang] = lang_result

    out_file = exp_dir / "multilingual_compression_results.json"
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

    print(f"\n✅ Multilingual benchmark complete! Saved to: {out_file}")


if __name__ == "__main__":
    run_benchmark()
