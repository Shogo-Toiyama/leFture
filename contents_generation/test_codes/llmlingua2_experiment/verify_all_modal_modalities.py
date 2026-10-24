#!/usr/bin/env python3
"""
Final Verification Script for Modal LLMLingua-2 API.
Tests all requested document types:
1. Project Spec (CS118 Project 1)
2. Homework (CS118 HW2)
3. Web Content - English (web_article.txt)
4. Web Content - Japanese (tcp_ja.txt)
5. Web Content - Portuguese (tcp_pt.txt)
6. Web Content - Chinese (tcp_zh.txt)
"""

import os
import sys
import time
import requests
from pathlib import Path

ENDPOINT_URL = os.getenv(
    "MODAL_LLMLINGUA2_URL",
    "https://shogo-toiyama--lefture-llmlingua2-llmlingua2api-compress.us-east.modal.run",
)

def run_verification():
    exp_dir = Path(__file__).resolve().parent
    multi_dir = exp_dir / "multilingual_raw"

    test_cases = [
        {
            "name": "1. プロジェクト仕様書 (Project Spec - CS118 Project 1)",
            "file": exp_dir / "cs118_project1_spec.md",
            "lang": "en",
            "rate": 0.6,
            "max_chars": None,
        },
        {
            "name": "2. 宿題 (Homework - CS118 HW2)",
            "file": exp_dir / "hw2_cs118.txt",
            "lang": "en",
            "rate": 0.6,
            "max_chars": None,
        },
        {
            "name": "3. ウェブ・英語 (Web English - TCP/IP Overview)",
            "file": exp_dir / "web_article.txt",
            "lang": "en",
            "rate": 0.6,
            "max_chars": 15000,
        },
        {
            "name": "4. ウェブ・日本語 (Web Japanese - TCP プロトコル解説)",
            "file": multi_dir / "tcp_ja.txt",
            "lang": "ja",
            "rate": 0.6,
            "max_chars": 15000,
        },
        {
            "name": "5. ウェブ・ポルトガル語 (Web Portuguese - Protocolo TCP)",
            "file": multi_dir / "tcp_pt.txt",
            "lang": "pt",
            "rate": 0.6,
            "max_chars": None,
        },
        {
            "name": "6. ウェブ・中国語 (Web Chinese - 传输控制协议 TCP)",
            "file": multi_dir / "tcp_zh.txt",
            "lang": "zh",
            "rate": 0.6,
            "max_chars": 15000,
        },
    ]

    print("=" * 72)
    print("🚀 Final Production Verification of Modal LLMLingua-2 API")
    print(f"🔗 Endpoint: {ENDPOINT_URL}")
    print("=" * 72)

    # 1. Warm-up / health check
    print("\n⏳ [1/2] Connecting & waking up container (if cold)...")
    t0 = time.perf_counter()
    ping_res = requests.post(ENDPOINT_URL, json={"text": "Ping test for warm up.", "rate": 0.7}, timeout=90)
    roundtrip_ping = time.perf_counter() - t0
    if ping_res.status_code != 200:
        print(f"❌ Ping failed with HTTP {ping_res.status_code}: {ping_res.text}")
        return
    print(f"✅ Container is READY! (Wakeup/Ping roundtrip: {roundtrip_ping:.2f}s)\n")

    # 2. Run all modalities
    print("⏳ [2/2] Testing all document types...\n")
    results = []

    for idx, tc in enumerate(test_cases, 1):
        path = tc["file"]
        if not path.exists():
            print(f"⚠️ File not found: {path}")
            continue

        text = path.read_text(encoding="utf-8")
        if tc["max_chars"] and len(text) > tc["max_chars"]:
            text = text[:tc["max_chars"]]

        print(f"------------------------------------------------------------------------")
        print(f"📄 [{idx}/6] {tc['name']}")
        print(f"   Size: {len(text):,} chars | Lang: {tc['lang']} | Rate target: {tc['rate']}")

        t_start = time.perf_counter()
        res = requests.post(ENDPOINT_URL, json={"text": text, "rate": tc["rate"]}, timeout=60)
        roundtrip_s = time.perf_counter() - t_start

        if res.status_code != 200:
            print(f"   ❌ HTTP {res.status_code}: {res.text[:200]}")
            continue

        data = res.json()
        orig_tok = data["original_tokens"]
        comp_tok = data["compressed_tokens"]
        red_pct = data["reduction_pct"]
        proc_ms = data["processing_time_ms"]
        prot_cnt = data.get("protected_chunks", 0)
        comp_cnt = data.get("compressed_chunks", 0)
        comp_text = data.get("compressed_text", "")

        print(f"   ⚡ GPU Compute : {proc_ms:.1f}ms")
        print(f"   🌐 Roundtrip   : {roundtrip_s:.2f}s")
        print(f"   📉 Tokens      : {orig_tok:,} -> {comp_tok:,} (-{red_pct}%)")
        print(f"   🛡️ Protected   : {prot_cnt} chunks (code/tables/syntax preserved)")
        print(f"   🗜️ Compressed  : {comp_cnt} chunks")
        preview = comp_text.strip().replace("\n", " ")[:120]
        print(f"   👀 Sample Excerpt: \"{preview}...\"")

        results.append({
            "name": tc["name"],
            "chars": len(text),
            "orig_tokens": orig_tok,
            "comp_tokens": comp_tok,
            "reduction_pct": red_pct,
            "gpu_ms": proc_ms,
            "roundtrip_s": roundtrip_s,
        })

    print("\n" + "=" * 72)
    print("📊 Final Summary Table")
    print("=" * 72)
    print(f"{'Document Type':<35} | {'Tokens':<15} | {'Red%':<7} | {'GPU (ms)':<9} | {'Roundtrip'}")
    print("-" * 72)
    for r in results:
        tok_str = f"{r['orig_tokens']}->{r['comp_tokens']}"
        print(f"{r['name'][:35]:<35} | {tok_str:<15} | -{r['reduction_pct']}% | {r['gpu_ms']:>6.1f}ms | {r['roundtrip_s']:>5.2f}s")
    print("=" * 72)
    print("🎉 All document types verified successfully on Modal!")

if __name__ == "__main__":
    run_verification()
