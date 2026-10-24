#!/usr/bin/env python3
"""
Comparative Experiment: Lightweight mBERT (700MB) vs Large XLM-RoBERTa (2.2GB).
Runs across:
1. CS118 Project 1 Spec (Code, Rules, Specifications)
2. CS118 Homework 2 (PDF text, questions, negations)
3. English Web Article (Wikipedia TCP)
4. Japanese Web Article (Wikipedia TCP ja)

Measures:
- Latency (CPU elapsed ms)
- Reduction % (Rate 0.7)
- Quality Distribution (Critical / Medium / Good)
- Keyword & Negation retention
"""

import re
import json
import time
import sys
from pathlib import Path

# Add backend to path
project_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(project_root / "lefture_backend"))

from app.services.chat_attachments import estimate_tokens
from llmlingua import PromptCompressor


def split_into_chunks(text: str):
    return [c.strip() for c in re.split(r"\n\s*\n", text) if c.strip()]


def should_protect_block(chunk: str) -> bool:
    if "```" in chunk:
        return True
    if "+-+-+-+" in chunk or "| :---" in chunk or chunk.count("|") >= 4:
        return True
    op_pattern = r"(?:<<|>>|&|\||\^|==|<=|>=|!=|#define|typedef\s+struct|uint\d+_t|recvfrom|sendto|ntohl|htonl|\bMSS\b)"
    if re.search(op_pattern, chunk):
        return True
    if chunk.count("`") >= 4:
        return True
    return False


FORCE_TOKENS = ["\n", "not", "don't", "doesn't", "cannot", "never", "unless", "except"]


def run_evaluation_on_text(compressor, name: str, text: str, rate: float = 0.7, keywords: list[str] = None):
    chunks = split_into_chunks(text)
    total_chunks = len(chunks)
    protected_chunks = sum(1 for c in chunks if should_protect_block(c))
    compressible_chunks = total_chunks - protected_chunks

    t0 = time.perf_counter()
    processed_chunks = []
    critical_count = 0
    medium_count = 0
    good_count = 0
    issues = []

    for idx, chunk in enumerate(chunks):
        if should_protect_block(chunk):
            processed_chunks.append(chunk)
            good_count += 1
        else:
            c_res = compressor.compress_prompt(
                chunk,
                rate=rate,
                force_tokens=FORCE_TOKENS,
                force_reserve_digit=True,
                chunk_end_tokens=[".", "\n", "。", "！", "？"]
            )
            comp_chunk = c_res.get("compressed_prompt", chunk)
            processed_chunks.append(comp_chunk)

            # Check negations
            orig_neg = set(re.findall(r"\b(not|never|unless|except|cannot|must not)\b", chunk, re.I))
            comp_neg = set(re.findall(r"\b(not|never|unless|except|cannot|must not)\b", comp_chunk, re.I))
            dropped_neg = {w.lower() for w in (orig_neg - comp_neg)}

            orig_nums = set(re.findall(r"\b\d+\b", chunk))
            comp_nums = set(re.findall(r"\b\d+\b", comp_chunk))
            dropped_nums = orig_nums - comp_nums

            if len(dropped_neg) > 0:
                critical_count += 1
                issues.append(f"Chunk {idx}: Negation dropped ({dropped_neg}) -> {comp_chunk[:80]}...")
            elif len(dropped_nums) > 0 and len(comp_nums) == 0:
                medium_count += 1
            else:
                good_count += 1

    elapsed_ms = (time.perf_counter() - t0) * 1000
    compressed_text = "\n\n".join(processed_chunks)
    orig_tok = estimate_tokens(text)
    comp_tok = estimate_tokens(compressed_text)
    reduction_pct = round((1.0 - (comp_tok / max(1, orig_tok))) * 100, 1)

    # Check keywords if provided
    kw_retained = 0
    kw_total = len(keywords) if keywords else 0
    if keywords:
        for kw in keywords:
            if kw in compressed_text:
                kw_retained += 1

    return {
        "material": name,
        "elapsed_ms": round(elapsed_ms, 1),
        "orig_tokens": orig_tok,
        "comp_tokens": comp_tok,
        "reduction_pct": reduction_pct,
        "total_chunks": total_chunks,
        "protected_chunks": protected_chunks,
        "critical_pct": round((critical_count / total_chunks) * 100, 1),
        "medium_pct": round((medium_count / total_chunks) * 100, 1),
        "good_pct": round((good_count / total_chunks) * 100, 1),
        "critical_count": critical_count,
        "keyword_retained": f"{kw_retained}/{kw_total}" if keywords else "N/A",
        "sample_preview": compressed_text[:300],
        "issues": issues[:3]
    }


def main():
    exp_dir = Path(__file__).resolve().parent

    # Materials
    p1_text = (exp_dir / "cs118_project1_spec.md").read_text(encoding="utf-8")
    hw2_text = (exp_dir / "hw2_cs118.txt").read_text(encoding="utf-8")
    web_en_text = (exp_dir / "web_article.txt").read_text(encoding="utf-8")[:16000]
    
    ja_path = exp_dir / "multilingual_raw" / "tcp_ja.txt"
    ja_text = ja_path.read_text(encoding="utf-8")[:10000] if ja_path.exists() else ""

    ja_keywords = ["シーケンス番号", "チェックサム", "フロー制御", "スリーウェイ・ハンドシェイク", "輻輳"]

    models = [
        {
            "id": "microsoft/llmlingua-2-bert-base-multilingual-cased-meetingbank",
            "name": "Lightweight mBERT (700MB)",
            "short": "mBERT-700MB"
        },
        {
            "id": "microsoft/llmlingua-2-xlm-roberta-large-meetingbank",
            "name": "Large XLM-RoBERTa (2.2GB)",
            "short": "XLM-R-2.2GB"
        }
    ]

    all_comparison = {}

    for m_info in models:
        model_id = m_info["id"]
        model_name = m_info["name"]
        print(f"\n========================================================")
        print(f"📦 Loading Model: {model_name}")
        print(f"   HuggingFace ID: {model_id}")
        print(f"========================================================")
        
        t_load = time.perf_counter()
        compressor = PromptCompressor(
            model_name=model_id,
            device_map="cpu",
            use_llmlingua2=True,
        )
        load_time_s = time.perf_counter() - t_load
        print(f"✅ Loaded in {load_time_s:.2f}s\n")

        results = {
            "load_time_s": round(load_time_s, 2),
            "evals": []
        }

        # 1. Project 1 Spec
        print(f"Running P1 Spec on {m_info['short']}...")
        r_p1 = run_evaluation_on_text(compressor, "CS118 Project 1 Spec", p1_text, rate=0.7)
        results["evals"].append(r_p1)

        # 2. Homework 2
        print(f"Running HW2 on {m_info['short']}...")
        r_hw2 = run_evaluation_on_text(compressor, "CS118 Homework 2 PDF", hw2_text, rate=0.7)
        results["evals"].append(r_hw2)

        # 3. Web English
        print(f"Running Web Article (EN) on {m_info['short']}...")
        r_en = run_evaluation_on_text(compressor, "Wikipedia TCP (EN)", web_en_text, rate=0.7)
        results["evals"].append(r_en)

        # 4. Web Japanese
        if ja_text:
            print(f"Running Web Article (JA) on {m_info['short']}...")
            r_ja = run_evaluation_on_text(compressor, "Wikipedia TCP (JA)", ja_text, rate=0.7, keywords=ja_keywords)
            results["evals"].append(r_ja)

        all_comparison[m_info["short"]] = results

    # Save results
    out_file = exp_dir / "mbert_vs_xlmr_comparison.json"
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(all_comparison, f, ensure_ascii=False, indent=2)

    print("\n\n========================================================")
    print("📊 COMPARISON SUMMARY (Rate = 0.7)")
    print("========================================================")
    print(f"{'Material':<24} | {'Metric':<14} | {'mBERT (700MB)':<18} | {'XLM-R (2.2GB)':<18}")
    print("-" * 80)

    for i in range(len(all_comparison["mBERT-700MB"]["evals"])):
        e_mbert = all_comparison["mBERT-700MB"]["evals"][i]
        e_xlmr = all_comparison["XLM-R-2.2GB"]["evals"][i]
        mat = e_mbert["material"]

        print(f"{mat:<24} | Reduction %    | {e_mbert['reduction_pct']:>5.1f}%             | {e_xlmr['reduction_pct']:>5.1f}%")
        print(f"{'':<24} | Critical Drop  | {e_mbert['critical_pct']:>5.1f}% ({e_mbert['critical_count']}件)       | {e_xlmr['critical_pct']:>5.1f}% ({e_xlmr['critical_count']}件)")
        print(f"{'':<24} | Good Quality   | {e_mbert['good_pct']:>5.1f}%             | {e_xlmr['good_pct']:>5.1f}%")
        print(f"{'':<24} | Latency (CPU)  | {e_mbert['elapsed_ms']:>6.1f}ms           | {e_xlmr['elapsed_ms']:>6.1f}ms")
        if e_mbert['keyword_retained'] != "N/A":
            print(f"{'':<24} | Keywords       | {e_mbert['keyword_retained']:>10}             | {e_xlmr['keyword_retained']:>10}")
        print("-" * 80)

    print(f"\nModel Load Time (CPU):")
    print(f"  - mBERT (700MB) : {all_comparison['mBERT-700MB']['load_time_s']}s")
    print(f"  - XLM-R (2.2GB) : {all_comparison['XLM-R-2.2GB']['load_time_s']}s")
    print(f"\nFull details saved to: {out_file}")


if __name__ == "__main__":
    main()
