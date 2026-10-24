#!/usr/bin/env python3
"""
Comprehensive LLMLingua-2 Quality Evaluation Script
Analyzes:
1. Material 1: Web Article (Wikipedia TCP: Connection & Flow Control, ~15k chars)
2. Material 2: Homework PDF (CS118 HW2: Alyssa Byte-stuffing, CRC, Go-Back-N, 10k chars)
3. Material 3: Project 1 Spec (CS118 Project 1 Transport on UDP, 18k chars)

Evaluates:
- Chunk-by-chunk degradation distribution: Critical (最悪), Medium (中), Good (良)
- Specific element drop rates: Operators, Numbers, ASCII/Tables, Negations, Types/Code
- Identification of the Top 3 most dangerous/corrupted failure cases
"""

import os
import sys
import re
import json
import time
from pathlib import Path

# Add backend to path
project_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(project_root / "lefture_backend"))

from app.services.chat_attachments import estimate_tokens
from llmlingua import PromptCompressor

def mask_code_blocks(text: str):
    """Masks code blocks ```...``` with placeholders."""
    blocks = []
    def repl(m):
        idx = len(blocks)
        blocks.append(m.group(0))
        return f"__CODE_BLOCK_{idx}__"
    masked = re.sub(r"```[\s\S]*?```", repl, text)
    return masked, blocks

def unmask_code_blocks(text: str, blocks):
    for idx, block in enumerate(blocks):
        text = text.replace(f"__CODE_BLOCK_{idx}__", block)
    return text

def split_into_chunks(text: str):
    """Splits markdown into logical paragraphs, code blocks, or list blocks."""
    raw_chunks = [c.strip() for c in re.split(r"\n\s*\n", text) if c.strip()]
    return raw_chunks

def analyze_chunk_quality(orig_chunk: str, comp_chunk: str):
    """
    Classifies a chunk into 'critical', 'medium', or 'good'.
    Also identifies dropped operators, numbers, negations, etc.
    """
    is_code = orig_chunk.startswith("```") or "typedef struct" in orig_chunk or "bool syn =" in orig_chunk
    is_ascii_table = "+-+-+-+" in orig_chunk or "| :---" in orig_chunk

    # Numbers in original
    orig_nums = set(re.findall(r"\b\d+\b", orig_chunk))
    comp_nums = set(re.findall(r"\b\d+\b", comp_chunk))
    dropped_nums = orig_nums - comp_nums

    # Operators & symbols in original
    orig_ops = set(re.findall(r"(?:<<|>>|&|\||\^|==|<=|>=|!=|\+|-|\*)", orig_chunk))
    comp_ops = set(re.findall(r"(?:<<|>>|&|\||\^|==|<=|>=|!=|\+|-|\*)", comp_chunk))
    dropped_ops = orig_ops - comp_ops

    # Negations & condition words
    orig_neg = set(re.findall(r"\b(not|never|unless|except|cannot|must not|differ|neither|nor)\b", orig_chunk, re.I))
    comp_neg = set(re.findall(r"\b(not|never|unless|except|cannot|must not|differ|neither|nor)\b", comp_chunk, re.I))
    dropped_neg = {w.lower() for w in (orig_neg - comp_neg)}

    # Classification logic
    issues = []
    level = "good"

    if is_ascii_table:
        # ASCII / table destruction
        if "+-+-+-+" in orig_chunk and "+-+-+-+" not in comp_chunk:
            level = "critical"
            issues.append("ASCII packet diagram completely collapsed")
        elif "|" in orig_chunk and comp_chunk.count("|") < orig_chunk.count("|") // 2:
            level = "critical"
            issues.append("Markdown table structure destroyed")

    if is_code:
        # Code block syntax check
        bracket_diff = abs(orig_chunk.count("{") - comp_chunk.count("{")) + abs(orig_chunk.count("}") - comp_chunk.count("}"))
        if bracket_diff > 0 or len(dropped_ops) > 0 or "struct" in orig_chunk and "struct" not in comp_chunk:
            level = "critical"
            issues.append(f"Code syntax broken (dropped ops: {list(dropped_ops)}, bracket imbalance: {bracket_diff})")
    else:
        # Natural text checks
        if len(dropped_neg) > 0:
            level = "critical"
            issues.append(f"Critical negation/condition dropped: {list(dropped_neg)}")
        elif len(dropped_nums) > len(orig_nums) * 0.4 and len(dropped_nums) >= 2:
            level = "critical"
            issues.append(f"Significant numerical constants dropped: {list(dropped_nums)[:4]}")
        elif len(comp_chunk) < len(orig_chunk) * 0.3:
            level = "medium"
            issues.append("Over-pruned (more than 70% discarded)")
        elif len(dropped_nums) > 0:
            level = "medium"
            issues.append(f"Some numbers dropped: {list(dropped_nums)[:3]}")

    return {
        "level": level,
        "issues": issues,
        "orig_chars": len(orig_chunk),
        "comp_chars": len(comp_chunk),
        "orig_nums": list(orig_nums),
        "dropped_nums": list(dropped_nums),
        "orig_ops": list(orig_ops),
        "dropped_ops": list(dropped_ops),
        "orig_neg": list(orig_neg),
        "dropped_neg": list(dropped_neg),
        "orig_preview": orig_chunk[:160] + ("..." if len(orig_chunk) > 160 else ""),
        "comp_preview": comp_chunk[:160] + ("..." if len(comp_chunk) > 160 else "")
    }


def evaluate_material(compressor, name: str, text: str, rates=[0.6, 0.4], test_protection=False):
    print(f"\n========================================================")
    print(f"🔬 Evaluating: {name} ({len(text)} chars, ~{estimate_tokens(text)} tokens)")
    print(f"========================================================")

    material_results = {
        "material_name": name,
        "char_count": len(text),
        "token_estimate": estimate_tokens(text),
        "experiments": []
    }

    chunks = split_into_chunks(text)
    print(f"Total semantic chunks: {len(chunks)}")

    modes = [("raw", False)]
    if test_protection:
        modes.append(("protected_code", True))

    for mode_name, protect in modes:
        for rate in rates:
            print(f"\n--- Mode: {mode_name} | Rate: {rate} ---")
            t0 = time.perf_counter()

            if protect:
                masked_text, code_blocks = mask_code_blocks(text)
                compressed = compressor.compress_prompt(
                    masked_text,
                    rate=rate,
                    force_tokens=["\n", "{", "}", "__CODE_BLOCK_"],
                    chunk_end_tokens=[".", "\n", "。", "！", "？"]
                )
                comp_text = unmask_code_blocks(compressed.get("compressed_prompt", ""), code_blocks)
            else:
                compressed = compressor.compress_prompt(
                    text,
                    rate=rate,
                    force_tokens=["\n", "```", "{", "}", "(", ")", ";", ":"],
                    chunk_end_tokens=[".", "\n", "。", "！", "？"]
                )
                comp_text = compressed.get("compressed_prompt", "")

            elapsed_ms = round((time.perf_counter() - t0) * 1000, 1)
            comp_tokens = estimate_tokens(comp_text)
            actual_ratio = round((comp_tokens / max(1, estimate_tokens(text))) * 100, 1)

            # Analyze chunk by chunk
            comp_chunks = split_into_chunks(comp_text)
            
            # Match chunks sequentially (or by compression ratio)
            # To get accurate per-chunk analysis, compress each chunk individually or evaluate matched chunks
            chunk_evals = []
            for i, chunk in enumerate(chunks):
                # Compress chunk directly with same compressor to see exact chunk degradation
                if protect:
                    m_chunk, c_blocks = mask_code_blocks(chunk)
                    c_res = compressor.compress_prompt(m_chunk, rate=rate, force_tokens=["\n", "{", "}", "__CODE_BLOCK_"])
                    c_text = unmask_code_blocks(c_res.get("compressed_prompt", ""), c_blocks)
                else:
                    c_res = compressor.compress_prompt(chunk, rate=rate, force_tokens=["\n", "```", "{", "}"])
                    c_text = c_res.get("compressed_prompt", "")
                
                eval_res = analyze_chunk_quality(chunk, c_text)
                eval_res["chunk_index"] = i
                chunk_evals.append(eval_res)

            total = len(chunk_evals)
            counts = {
                "critical": sum(1 for e in chunk_evals if e["level"] == "critical"),
                "medium": sum(1 for e in chunk_evals if e["level"] == "medium"),
                "good": sum(1 for e in chunk_evals if e["level"] == "good"),
            }
            pcts = {
                "critical": round((counts["critical"] / total) * 100, 1),
                "medium": round((counts["medium"] / total) * 100, 1),
                "good": round((counts["good"] / total) * 100, 1),
            }

            # Dropped elements aggregations
            all_orig_ops = sum(len(e["orig_ops"]) for e in chunk_evals)
            all_dropped_ops = sum(len(e["dropped_ops"]) for e in chunk_evals)
            all_orig_nums = sum(len(e["orig_nums"]) for e in chunk_evals)
            all_dropped_nums = sum(len(e["dropped_nums"]) for e in chunk_evals)
            all_orig_neg = sum(len(e["orig_neg"]) for e in chunk_evals)
            all_dropped_neg = sum(len(e["dropped_neg"]) for e in chunk_evals)

            print(f"Elapsed: {elapsed_ms}ms | Actual Token Ratio: {actual_ratio}%")
            print(f"Distribution: Critical(最悪)={pcts['critical']}% | Medium(中)={pcts['medium']}% | Good(良)={pcts['good']}%")
            print(f"Dropped: Operators={all_dropped_ops}/{all_orig_ops} | Numbers={all_dropped_nums}/{all_orig_nums} | Negations={all_dropped_neg}/{all_orig_neg}")

            material_results["experiments"].append({
                "mode": mode_name,
                "target_rate": rate,
                "actual_token_ratio_pct": actual_ratio,
                "latency_ms": elapsed_ms,
                "distribution_pct": pcts,
                "distribution_counts": counts,
                "element_drop_stats": {
                    "operators": {"orig": all_orig_ops, "dropped": all_dropped_ops, "pct": round((all_dropped_ops/max(1,all_orig_ops))*100, 1)},
                    "numbers": {"orig": all_orig_nums, "dropped": all_dropped_nums, "pct": round((all_dropped_nums/max(1,all_orig_nums))*100, 1)},
                    "negations": {"orig": all_orig_neg, "dropped": all_dropped_neg, "pct": round((all_dropped_neg/max(1,all_orig_neg))*100, 1)},
                },
                "chunk_evaluations": chunk_evals,
                "full_compressed_text": comp_text
            })

    return material_results


def main():
    exp_dir = Path(__file__).resolve().parent
    
    # Load materials
    # 1. Project 1 Spec
    p1_path = exp_dir / "cs118_project1_spec.md"
    p1_text = p1_path.read_text(encoding="utf-8")

    # 2. Homework 2
    hw2_path = exp_dir / "hw2_cs118.txt"
    hw2_text = hw2_path.read_text(encoding="utf-8")

    # 3. Web article (Take first 16,000 chars of Wikipedia TCP article)
    web_path = exp_dir / "web_article.txt"
    web_text = web_path.read_text(encoding="utf-8")[:16000]

    print("Loading LLMLingua-2 model on CPU...")
    t_load = time.perf_counter()
    compressor = PromptCompressor(
        model_name="microsoft/llmlingua-2-xlm-roberta-large-meetingbank",
        device_map="cpu",
        use_llmlingua2=True,
    )
    print(f"Loaded in {time.perf_counter() - t_load:.2f}s")

    all_results = {}
    
    # Material 3: Project 1 Spec (Test with and without code protection)
    all_results["project1_spec"] = evaluate_material(
        compressor, "CS118 Project 1 Spec", p1_text, rates=[0.6, 0.4], test_protection=True
    )

    # Material 2: Homework 2
    all_results["homework2"] = evaluate_material(
        compressor, "CS118 Homework 2 PDF", hw2_text, rates=[0.6, 0.4], test_protection=False
    )

    # Material 1: Web Article
    all_results["web_article"] = evaluate_material(
        compressor, "Wikipedia TCP Technical Article", web_text, rates=[0.6, 0.4], test_protection=False
    )

    output_file = exp_dir / "detailed_quality_evaluation.json"
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(all_results, f, ensure_ascii=False, indent=2)

    print(f"\n All evaluation data saved to: {output_file}")


if __name__ == "__main__":
    main()
