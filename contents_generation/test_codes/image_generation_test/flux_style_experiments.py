"""
Render a hand-picked set of Luna outputs with FLUX (flux-2-klein-4b), exactly as production does:
  prompt = f"{flux_scene_description}, {flux_style_suffix}", 384x512, multipart/form-data.
Inputs are the Luna outputs already saved by luna_style_experiments.py (luna_exp_results/*.json).
Outputs (images, manifest, contact sheets, index.html) go to luna_exp_results/flux/ (gitignored: real lecture data).
"""
import asyncio
import base64
import json
import os
from pathlib import Path

import httpx
from dotenv import load_dotenv
from PIL import Image, ImageDraw

here = Path(__file__).resolve().parent
load_dotenv(here.parent.parent / ".env")  # contents_generation/.env holds the Cloudflare credentials
RES = here / "luna_exp_results"
OUT = RES / "flux"
OUT.mkdir(exist_ok=True)

ACCOUNT, TOKEN = os.environ["CLOUDFLARE_ACCOUNT_ID"], os.environ["CLOUDFLARE_API_KEY"]
URL = f"https://api.cloudflare.com/client/v4/accounts/{ACCOUNT}/ai/run/@cf/black-forest-labs/flux-2-klein-4b"
W, H = 384, 512


def load(name):
    return json.loads((RES / name).read_text())


def pick(rows, topic_idx, **match):
    hits = [r for r in rows if all(r.get(k) == v or (isinstance(v, str) and str(r.get(k, "")).startswith(v)) for k, v in match.items())]
    assert len(hits) == 1, (match, len(hits))
    r = hits[0]
    gad = r["output"]["global_art_direction"]
    scene = next(p for p in r["output"]["image_prompts"] if p["topic_idx"] == topic_idx)
    return r["assigned_style"], scene["flux_scene_description"], gad["flux_style_suffix"], r.get("lecture", "Channel capacity (Nyquist/Shannon)")


def cases():
    e1, e3, e4, e4b, e5 = (load(f) for f in ("exp1_assigned.json", "exp3_abstraction.json", "exp4_catalog_after.json",
                                              "exp4b_96_replaced.json", "exp5_for_flux.json"))
    e1c = [r for r in e1 if r["condition"] == "assigned_clean"]
    e3a = [r for r in e3 if r["version"] == "abstracted"]
    F, P, CH = "Functional", "Python", "Channel"
    return [
        # --- A. abstract geometry ---
        ("A", "Swiss grid",            pick(e1c, 2, assigned_style="Modern Swiss-style graphic design", lecture=CH)),
        ("A", "Bauhaus shapes",        pick(e5, 2, style_index=77)),
        ("A", "Constructivist",        pick(e5, 4, style_index=78)),
        ("A", "Minimal geometric",     pick(e5, 5, style_index=79)),
        ("A", "Circular motifs",       pick(e4, 4, style_index=80, lecture=F)),
        ("A", "Low-poly",              pick(e5, 4, style_index=50)),
        # --- B. style / subject mismatch ---
        ("B", "Night photo (ATM)",     pick(e3a, 3, style_key="Breathtaking celestial", lecture=F)),
        ("B", "Screenprint poster",    pick(e3a, 2, style_key="Vintage national park", lecture=P)),
        ("B", "Travel-poster gouache", pick(e3a, 2, style_key="Classic Riviera", lecture=F)),
        ("B", "Shin-Hanga (new)",      pick(e5, 5, style_index=38)),
        ("B", "Stained glass",         pick(e1c, 2, assigned_style="Stained glass panel art", lecture="ML")),
        # --- C. hard materials ---
        ("C", "Claymation",            pick(e1c, 2, assigned_style="Tactile claymation", lecture="CRC")),
        ("C", "Woven tapestry",        pick(e4, 3, style_index=93, lecture=F)),
        ("C", "Ink wash",              pick(e4b, 2, lecture=F)),
        ("C", "Mosaic tiles",          pick(e5, 4, style_index=94)),
        ("C", "Linocut",               pick(e1c, 2, assigned_style="Bold relief linocut", lecture="HCI: context")),
        ("C", "Risograph",             pick(e5, 5, style_index=71)),
        ("C", "Carved wood relief",    pick(e1c, 3, assigned_style="Hand-carved relief wood", lecture=CH)),
        # --- D. photoreal / people / 3D light ---
        ("D", "Golden-hour wide (barista)", pick(e4, 2, style_index=14, lecture=F)),
        ("D", "Midday photo (travelers)",   pick(e5, 6, style_index=11)),
        ("D", "Volumetric 3D",         pick(e5, 1, style_index=56)),
    ]


async def render(client, sem, i, group, label, style, scene, suffix, lecture):
    prompt = f"{scene}, {suffix}".strip().strip(",")
    path = OUT / f"{i:02d}_{group}_{label.replace(' ', '_').replace('(', '').replace(')', '')}.jpg"
    async with sem:
        for attempt in range(3):
            r = await client.post(URL, headers={"Authorization": f"Bearer {TOKEN}"}, timeout=90.0,
                                  files={"prompt": (None, prompt), "width": (None, str(W)), "height": (None, str(H))})
            if r.status_code == 429 or r.status_code >= 500:
                await asyncio.sleep(2 ** attempt)
                continue
            break
    r.raise_for_status()
    if "application/json" in r.headers.get("Content-Type", ""):
        data = r.json()
        assert data.get("success"), data
        path.write_bytes(base64.b64decode(data["result"]["image"]))
    else:
        path.write_bytes(r.content)
    return {"n": i, "group": group, "label": label, "file": path.name, "style": style, "lecture": lecture, "prompt": prompt}


def contact_sheets(items, per_sheet=6, cols=3):
    cell_w, cell_h, pad = W, H + 34, 6
    for s in range(0, len(items), per_sheet):
        chunk = items[s:s + per_sheet]
        rows = (len(chunk) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * (cell_w + pad) + pad, rows * (cell_h + pad) + pad), "white")
        d = ImageDraw.Draw(sheet)
        for k, it in enumerate(chunk):
            x, y = pad + (k % cols) * (cell_w + pad), pad + (k // cols) * (cell_h + pad)
            sheet.paste(Image.open(OUT / it["file"]).convert("RGB"), (x, y + 34))
            d.text((x + 4, y + 8), f"#{it['n']} [{it['group']}] {it['label']}", fill="black")
        sheet.save(OUT / f"sheet_{s // per_sheet + 1}.jpg", quality=88)


def index_html(items):
    parts = ["<meta charset=utf-8><title>FLUX style check</title><body style='font-family:sans-serif;max-width:1100px;margin:auto'>"]
    for it in items:
        parts.append(f"<div style='display:flex;gap:16px;margin:24px 0;border-top:1px solid #ccc;padding-top:16px'>"
                     f"<img src='{it['file']}' width=384><div><h3>#{it['n']} [{it['group']}] {it['label']}</h3>"
                     f"<p><b>lecture:</b> {it['lecture']}</p><p><b>style:</b> {it['style']}</p>"
                     f"<p style='font-size:13px;color:#444'><b>prompt:</b> {it['prompt']}</p></div></div>")
    (OUT / "index.html").write_text("\n".join(parts))


async def main():
    cs = cases()
    sem = asyncio.Semaphore(4)
    async with httpx.AsyncClient() as client:
        items = await asyncio.gather(*(render(client, sem, i, g, l, *t) for i, (g, l, t) in enumerate(cs, 1)))
    items = sorted(items, key=lambda x: x["n"])
    (OUT / "manifest.json").write_text(json.dumps(items, indent=2, ensure_ascii=False))
    contact_sheets(items)
    index_html(items)
    print(f"rendered {len(items)} images; est. cost ${len(items) * 0.000287:.4f}")


if __name__ == "__main__":
    asyncio.run(main())
