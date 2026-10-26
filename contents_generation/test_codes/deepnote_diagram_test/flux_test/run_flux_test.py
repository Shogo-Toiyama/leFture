import os
import sys
import time
import json
import asyncio
import httpx
import argparse
from pathlib import Path
from dotenv import dotenv_values

base_dir = Path(__file__).resolve().parent
repo_root = base_dir.parents[3]

# Load credentials from contents_generation/.env
cg_env = dotenv_values(repo_root / "contents_generation/.env")
ACCOUNT_ID = cg_env.get("CLOUDFLARE_ACCOUNT_ID")
API_TOKEN = cg_env.get("CLOUDFLARE_API_KEY")

MODEL_ID = "@cf/black-forest-labs/flux-2-klein-4b"

TEST_CASES = [
    {
        "id": "case_1_digging_stick",
        "title": "掘り棒の使用例",
        "course": "考古学",
        "lecture": "縄文の道具・集落と社会",
        "original_description": "一端が尖り、もう一端がヘラ状になった木製の棒を人が地面に突き刺し、土を掘り起こしている様子。もう一人の人がヘラ状の部分で土を掻き出している様子も描く。",
        "flux_prompt": "Clean educational textbook illustration of two prehistoric Jomon period artisans using wooden digging tools in a natural landscape, one piercing the earth with a pointed stick while the other scoops soft soil with a flat wooden spatula, warm sunlight, gentle academic color palette, minimal clear composition, isolated on clean off-white background, high clarity, no text"
    },
    {
        "id": "case_2_pottery_coiling",
        "title": "粘土紐による土器の成形",
        "course": "考古学",
        "lecture": "縄文の生業と土器の技術・造形",
        "original_description": "粘土の紐を螺旋状に積み重ねて土器の形を作り、表面をならしていく様子。特に、口縁部が大きく開いた器形では、粘土が柔らかいと自重で崩れるため、乾燥させながら慎重に作業を進める必要があることを示す。",
        "flux_prompt": "Pedagogical textbook illustration showing an ancient craftsman hand-building a pottery vessel by spiraling coils of wet clay, carefully smoothing the ceramic surface with fingertips, step-by-step cross-section visible, warm terracotta and earthy tones, clean educational aesthetic, isolated on pure white background, no text"
    }
]

async def run_single_flux(case: dict, run_dir: Path, dry_run: bool = False):
    case_id = case["id"]
    title = case["title"]
    prompt = case["flux_prompt"]
    
    print(f"\n[FLUX] Starting {case_id} ({title}) (dry_run={dry_run})...")
    print(f"       Prompt: {prompt}")
    
    out_img_path = run_dir / f"{case_id}.jpg"
    start_time = time.time()
    
    if dry_run:
        elapsed = 0.05
        cost_usd = 0.000287
        # Generate dummy 1x1 image for dry run
        with open(out_img_path, "wb") as f:
            f.write(b"DUMMY_IMAGE_DATA")
        print(f"[FLUX] [DRY RUN] Generated mock image -> {out_img_path.name}")
    else:
        if not ACCOUNT_ID or not API_TOKEN:
            raise ValueError("CLOUDFLARE_ACCOUNT_ID or CLOUDFLARE_API_KEY missing in contents_generation/.env")
            
        url = f"https://api.cloudflare.com/client/v4/accounts/{ACCOUNT_ID}/ai/run/{MODEL_ID}"
        headers = {
            "Authorization": f"Bearer {API_TOKEN}",
        }
        
        # multipart/form-data payload for flux-2-klein-4b
        files = {
            "prompt": (None, prompt),
            "width": (None, "672"),
            "height": (None, "448"),
            "steps": (None, "4"),
        }
        
        async with httpx.AsyncClient(timeout=60.0) as client:
            res = await client.post(url, headers=headers, files=files)
            res.raise_for_status()
            data = res.json()
            image_b64 = data.get("result", {}).get("image")
            if not image_b64:
                raise ValueError(f"No image in response: {data}")
            import base64
            image_bytes = base64.b64decode(image_b64)
            
        with open(out_img_path, "wb") as f:
            f.write(image_bytes)
            
        elapsed = time.time() - start_time
        # Cloudflare flux-2-klein-4b pricing: ~0.000287 per tile/render
        cost_usd = 0.000287
        print(f"[FLUX] Finished {case_id} in {elapsed:.2f}s (Cost: ~${cost_usd:.6f}) -> {out_img_path.name}")
        
    return {
        "case_id": case_id,
        "title": title,
        "course": case["course"],
        "lecture": case["lecture"],
        "prompt": prompt,
        "original_description": case["original_description"],
        "elapsed_seconds": elapsed,
        "cost_usd": cost_usd,
        "image_path": out_img_path.name
    }

def generate_preview_gallery(results: list, run_dir: Path):
    gallery_path = run_dir / "preview_gallery.html"
    cards_html = []
    
    for r in results:
        img_src = r["image_path"]
        card = f"""
        <div class="figure-card">
          <div class="card-header">
            <h3>{r['title']} <span class="badge">illustration (Flux 2 Klein)</span></h3>
            <p class="meta">{r['course']} / {r['lecture']} | {r['elapsed_seconds']:.2f}s | ~${r['cost_usd']:.5f}</p>
          </div>
          <div class="img-wrap">
            <img src="{img_src}" alt="{r['title']}" />
          </div>
          <div class="prompt-box">
            <strong>Original Description:</strong><br>
            <span>{r['original_description']}</span>
            <hr style="margin: 8px 0; border: none; border-top: 1px dashed #e2e8f0;">
            <strong>Flux Prompt (English):</strong><br>
            <code>{r['prompt']}</code>
          </div>
        </div>
        """
        cards_html.append(card)
        
    html = f"""<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>DeepNotes Illustration Test (Flux 2 Klein)</title>
<style>
  body {{
    background-color: #FAF5E9; /* Paper World */
    color: #1e293b;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    padding: 32px 16px;
    margin: 0;
  }}
  header {{
    max-width: 640px;
    margin: 0 auto 32px auto;
  }}
  h1 {{ margin: 0 0 8px 0; font-size: 22px; color: #0f172a; }}
  .figure-card {{
    max-width: 640px;
    margin: 0 auto 32px auto;
    background: #ffffff;
    border: 1px solid #e2e8f0;
    border-radius: 12px;
    box-shadow: 0 4px 12px rgba(15, 23, 42, 0.06);
    overflow: hidden;
  }}
  .card-header {{
    padding: 16px 20px;
    background: #f8fafc;
    border-bottom: 1px solid #e2e8f0;
  }}
  .card-header h3 {{ margin: 0 0 4px 0; font-size: 16px; }}
  .badge {{
    font-size: 11px;
    background: #8b5cf6;
    color: #fff;
    padding: 2px 8px;
    border-radius: 999px;
    margin-left: 8px;
    font-weight: 600;
  }}
  .meta {{ margin: 0; color: #64748b; font-size: 12px; }}
  .img-wrap {{
    background: #f8fafc;
    padding: 16px;
    display: flex;
    justify-content: center;
  }}
  .img-wrap img {{
    max-width: 100%;
    height: auto;
    border-radius: 8px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.08);
  }}
  .prompt-box {{
    padding: 16px 20px;
    font-size: 12px;
    color: #475569;
    background: #ffffff;
    border-top: 1px solid #e2e8f0;
    line-height: 1.5;
  }}
  code {{
    font-family: monospace;
    color: #0f172a;
    background: #f1f5f9;
    padding: 2px 4px;
    border-radius: 4px;
    display: block;
    margin-top: 4px;
  }}
</style>
</head>
<body>
  <header>
    <h1>🎨 DeepNotes Illustration Test (Flux 2 Klein)</h1>
    <p style="margin: 0; color: #64748b; font-size: 14px;">Cloudflare Workers AI @cf/black-forest-labs/flux-2-klein-4b</p>
  </header>
  {''.join(cards_html)}
</body>
</html>
"""
    with open(gallery_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"\n✨ Generated Gallery -> {gallery_path.relative_to(base_dir)}")

async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="Run mock dry run without API call")
    args = parser.parse_args()
    
    run_dir = base_dir / "results"
    run_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"=== Starting DeepNotes Illustration Test (Flux 2 Klein) ===")
    print(f"Cases: {len(TEST_CASES)}")
    print(f"Dry Run: {args.dry_run}")
    
    results = []
    for c in TEST_CASES:
        r = await run_single_flux(c, run_dir, dry_run=args.dry_run)
        results.append(r)
        
    summary_path = run_dir / "summary.json"
    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
        
    generate_preview_gallery(results, run_dir)
    print(f"\n✅ All steps finished successfully! Results saved to {run_dir.relative_to(base_dir)}")

if __name__ == "__main__":
    asyncio.run(main())
