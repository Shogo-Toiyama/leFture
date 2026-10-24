#!/usr/bin/env python3
"""
Test Soft Compression (Rates 0.8, 0.7, 0.6) with Code/Operator Block Protection.
Tests across CS118 Project 1 Spec, CS118 Homework 2, and Web Article.
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
    """
    Determines if a block should be 100% protected (untouched):
    - Fenced code blocks (```)
    - Markdown tables (| :--- |) or ASCII diagrams (+-+-+)
    - Lines with programming operators (&, >>, <<, ^, ==, <=, >=, !=)
    - C language / system constructs (#define, typedef struct, uint32_t, recvfrom, etc.)
    - Heavy inline code (> 4 backticks)
    """
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


def evaluate_soft_compression(compressor, name: str, text: str, rates=[0.8, 0.7, 0.6]):
    print(f"\n========================================================")
    print(f"🔬 Soft Compression Test: {name}")
    print(f"   Original Size: {len(text)} chars, ~{estimate_tokens(text)} tokens")
    print(f"========================================================")

    chunks = split_into_chunks(text)
    total_chunks = len(chunks)
    protected_count = sum(1 for c in chunks if should_protect_block(c))
    compressible_count = total_chunks - protected_count

    print(f"Total chunks: {total_chunks}")
    print(f"  - Protected (Code/Operator/Table): {protected_count} ({protected_count/total_chunks*100:.1f}%)")
    print(f"  - Compressible (Natural Language): {compressible_count} ({compressible_count/total_chunks*100:.1f}%)")

    results = {
        "material_name": name,
        "total_chunks": total_chunks,
        "protected_chunks": protected_count,
        "compressible_chunks": compressible_count,
        "original_tokens": estimate_tokens(text),
        "rates": []
    }

    # Negation words to protect in natural text
    force_tokens = ["\n", "not", "don't", "doesn't", "cannot", "never", "unless", "except"]

    for rate in rates:
        t0 = time.perf_counter()
        processed_chunks = []
        chunk_issues = []

        critical_count = 0
        medium_count = 0
        good_count = 0

        for idx, chunk in enumerate(chunks):
            if should_protect_block(chunk):
                # 100% UNTOUCHED
                processed_chunks.append(chunk)
                good_count += 1
            else:
                # Natural language text: compress with soft rate
                c_res = compressor.compress_prompt(
                    chunk,
                    rate=rate,
                    force_tokens=force_tokens,
                    force_reserve_digit=True,
                    chunk_end_tokens=[".", "\n", "。", "！", "？"]
                )
                comp_chunk = c_res.get("compressed_prompt", "")
                processed_chunks.append(comp_chunk)

                # Check quality of compressed natural text
                orig_neg = set(re.findall(r"\b(not|never|unless|except|cannot|must not)\b", chunk, re.I))
                comp_neg = set(re.findall(r"\b(not|never|unless|except|cannot|must not)\b", comp_chunk, re.I))
                dropped_neg = {w.lower() for w in (orig_neg - comp_neg)}

                orig_nums = set(re.findall(r"\b\d+\b", chunk))
                comp_nums = set(re.findall(r"\b\d+\b", comp_chunk))
                dropped_nums = orig_nums - comp_nums

                if len(dropped_neg) > 0:
                    critical_count += 1
                    chunk_issues.append({
                        "idx": idx,
                        "type": "negation_dropped",
                        "orig": chunk,
                        "comp": comp_chunk
                    })
                elif len(dropped_nums) > 0 and len(comp_nums) == 0:
                    medium_count += 1
                else:
                    good_count += 1

        elapsed_ms = (time.perf_counter() - t0) * 1000
        full_compressed_text = "\n\n".join(processed_chunks)
        comp_tokens = estimate_tokens(full_compressed_text)
        overall_retention = (comp_tokens / max(1, estimate_tokens(text))) * 100
        reduction_pct = 100 - overall_retention

        crit_pct = (critical_count / total_chunks) * 100
        med_pct = (medium_count / total_chunks) * 100
        good_pct = (good_count / total_chunks) * 100

        print(f"\n--- Target Rate: {rate} ---")
        print(f"Elapsed: {elapsed_ms:.1f}ms")
        print(f"Overall Result: {estimate_tokens(text)} tok -> {comp_tokens} tok ({overall_retention:.1f}% remaining, {reduction_pct:.1f}% reduced)")
        print(f"Distribution: Critical(破損)={crit_pct:.1f}% | Medium(劣化)={med_pct:.1f}% | Good(良好)={good_pct:.1f}%")
        print(f"Critical Chunk Count: {critical_count} / {total_chunks}")

        results["rates"].append({
            "target_rate": rate,
            "overall_retention_pct": round(overall_retention, 1),
            "reduction_pct": round(reduction_pct, 1),
            "compressed_tokens": comp_tokens,
            "elapsed_ms": round(elapsed_ms, 1),
            "distribution_pct": {
                "critical": round(crit_pct, 1),
                "medium": round(med_pct, 1),
                "good": round(good_pct, 1)
            },
            "critical_count": critical_count,
            "chunk_issues": chunk_issues[:3],
            "compressed_preview": full_compressed_text[:500]
        })

    return results


def main():
    exp_dir = Path(__file__).resolve().parent

    print("Loading LLMLingua-2 on CPU...")
    compressor = PromptCompressor(
        model_name="microsoft/llmlingua-2-xlm-roberta-large-meetingbank",
        device_map="cpu",
        use_llmlingua2=True,
    )

    all_results = {}

    # 1. CS118 Project 1 Spec
    p1_path = exp_dir / "cs118_project1_spec.md"
    p1_text = p1_path.read_text(encoding="utf-8")
    all_results["project1_spec"] = evaluate_soft_compression(compressor, "CS118 Project 1 Spec", p1_text)

    # 2. CS118 Homework 2 PDF
    hw2_path = exp_dir / "hw2_cs118.txt"
    hw2_text = hw2_path.read_text(encoding="utf-8")
    all_results["homework2"] = evaluate_soft_compression(compressor, "CS118 Homework 2 PDF", hw2_text)

    # 3. Wikipedia TCP Web Article
    web_path = exp_dir / "web_article.txt"
    web_text = web_path.read_text(encoding="utf-8")[:16000]
    all_results["web_article"] = evaluate_soft_compression(compressor, "Wikipedia TCP Web Article", web_text)

    output_path = exp_dir / "soft_compression_results.json"
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(all_results, f, ensure_ascii=False, indent=2)

    print(f"\n✅ All soft compression results saved to: {output_path}")


if __name__ == "__main__":
    main()
