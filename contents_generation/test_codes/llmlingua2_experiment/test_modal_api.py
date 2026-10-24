#!/usr/bin/env python3
"""
Test script for deployed Modal LLMLingua-2 API.
Compares different batch sizes on actual Modal T4 GPU:
- batch_size = 16
- batch_size = 32 (default)
- batch_size = 64
- batch_size = 1 (sequential)

Also tests Coldstart after auto-scaledown (2s).

Usage:
    python test_modal_api.py <MODAL_ENDPOINT_URL>
"""

import sys
import os
import time
import requests
from pathlib import Path

DEFAULT_URL = os.getenv("MODAL_LLMLINGUA2_URL", "")

def test_endpoint(api_url: str):
    exp_dir = Path(__file__).resolve().parent
    spec_path = exp_dir / "cs118_project1_spec.md"
    
    if spec_path.exists():
        sample_text = spec_path.read_text(encoding="utf-8")
        data_name = "CS118 Project 1 Spec"
    else:
        sample_text = (
            "# Socket Programming Project\n\n"
            "In this project, you will implement a reliable data transfer protocol over UDP.\n\n"
            "```c\nuint8_t flag;\nbool syn = flag & 1;\n```\n\n"
            "The packet structure must follow the specification strictly. Do not use TCP."
        )
        data_name = "Sample Spec"

    print("================================================================")
    print("🚀 Modal LLMLingua-2 API Benchmark & GPU Batch-Size Test")
    print(f"🔗 Endpoint: {api_url}")
    print(f"📄 Test Material: {data_name} ({len(sample_text)} chars)")
    print("================================================================\n")

    # -------------------------------------------------------------
    # 1. Initial Wake-up / Container warm check
    # -------------------------------------------------------------
    print("1️⃣ [Wake-up Ping] Waking up container...")
    t0 = time.time()
    try:
        init_res = requests.post(api_url, json={"text": sample_text, "rate": 0.7, "batch_size": 32}, timeout=120)
        t1 = time.time()
    except Exception as e:
        print(f"❌ Connection error: {e}")
        return

    if init_res.status_code != 200:
        print(f"❌ HTTP {init_res.status_code}: {init_res.text}")
        return

    init_data = init_res.json()
    print(f"   ✅ Container is warm! (Roundtrip: {t1 - t0:.2f}s | Server compute: {init_data.get('processing_time_ms', 0):.1f}ms)\n")

    # -------------------------------------------------------------
    # 2. Compare Batch Sizes on Warm T4 GPU
    # -------------------------------------------------------------
    print("2️⃣ [GPU Batch Benchmark] Measuring GPU compute across batch sizes...")
    test_batches = [16, 32, 64, 1]
    batch_results = []

    for b_size in test_batches:
        payload = {
            "text": sample_text,
            "rate": 0.7,
            "batch_size": b_size
        }
        t_start = time.time()
        res = requests.post(api_url, json=payload, timeout=60)
        roundtrip_s = time.time() - t_start

        if res.status_code == 200:
            d = res.json()
            gpu_ms = d.get("processing_time_ms", 0.0)
            red_pct = d.get("reduction_pct", 0.0)
            batch_results.append({
                "batch_size": b_size,
                "gpu_ms": gpu_ms,
                "roundtrip_s": roundtrip_s,
                "reduction_pct": red_pct
            })
            print(f"   ⚡ Batch {b_size:>2}: GPU Compute = {gpu_ms:>6.1f}ms | Roundtrip = {roundtrip_s:>4.2f}s | Red = -{red_pct}%")
        else:
            print(f"   ❌ Batch {b_size}: HTTP {res.status_code}")

    print("\n----------------------------------------------------------------")
    print(f"{'Batch Size':<12} | {'GPU Compute':<16} | {'Total Roundtrip':<16} | {'Reduction':<10}")
    print("----------------------------------------------------------------")
    for r in batch_results:
        b_name = f"Batch {r['batch_size']}" if r['batch_size'] > 1 else "Batch 1 (逐次)"
        print(f"{b_name:<12} | {r['gpu_ms']:>6.1f}ms        | {r['roundtrip_s']:>5.2f}s         | -{r['reduction_pct']}%")
    print("----------------------------------------------------------------\n")

    # -------------------------------------------------------------
    # 3. Wait for Scaledown & Measure True Coldstart
    # -------------------------------------------------------------
    wait_sec = 6
    print(f"3️⃣ [Scaledown Test] Waiting {wait_sec}s for auto-scaledown (scaledown_window=2s)...")
    for s in range(wait_sec, 0, -1):
        print(f"   Sleeping... {s}s remaining", end="\r", flush=True)
        time.sleep(1)
    print("\n   Container stopped (0 active instances).\n")

    print("4️⃣ [True Coldstart] Sending request to stopped container (Snapshot restore)...")
    t_cold_0 = time.time()
    res_cold = requests.post(api_url, json={"text": sample_text, "rate": 0.7, "batch_size": 32}, timeout=120)
    roundtrip_cold = time.time() - t_cold_0

    if res_cold.status_code == 200:
        d_cold = res_cold.json()
        print(f"   ❄️ True Coldstart Roundtrip: {roundtrip_cold:.2f}s (Server compute: {d_cold.get('processing_time_ms', 0):.1f}ms)\n")
    else:
        print(f"   ❌ Coldstart request failed: {res_cold.status_code}")

    print("================================================================")
    print("🎉 Benchmark Complete!")
    print("================================================================")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        target_url = sys.argv[1].strip()
    elif DEFAULT_URL:
        target_url = DEFAULT_URL
    else:
        print("Usage: python test_modal_api.py <MODAL_ENDPOINT_URL>")
        sys.exit(1)

    test_endpoint(target_url)
