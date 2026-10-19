"""
Does putting the style FIRST in the FLUX prompt make the 4 topic images of one lecture look like one series?
7 styles that missed in flux_style_experiments.py x first 4 topics x 2 prompt orders ("current" = scene, suffix / "style_first" = suffix. scene).
Outputs: luna_exp_results/flux_order/ (gitignored).
"""
import asyncio
import json

import httpx
from PIL import Image, ImageDraw

import flux_style_experiments as fx

OUT = fx.RES / "flux_order"
OUT.mkdir(exist_ok=True)
N_TOPICS = 4


def sources():
    e1c = [r for r in fx.load("exp1_assigned.json") if r["condition"] == "assigned_clean"]
    e4, e4b, e5 = fx.load("exp4_catalog_after.json"), fx.load("exp4b_96_replaced.json"), fx.load("exp5_for_flux.json")
    def one(rows, **m):
        hits = [r for r in rows if all(str(r.get(k, "")).startswith(v) if isinstance(v, str) else r.get(k) == v for k, v in m.items())]
        assert len(hits) == 1, (m, len(hits))
        return hits[0]
    F = "Functional"
    return [
        ("Swiss grid",        one(e1c, assigned_style="Modern Swiss-style graphic design", lecture="Channel")),
        ("Constructivist",    one(e5, style_index=78)),
        ("Circular motifs",   one(e4, style_index=80, lecture=F)),
        ("Stained glass",     one(e1c, assigned_style="Stained glass panel art", lecture="ML")),
        ("Woven tapestry",    one(e4, style_index=93, lecture=F)),
        ("Ink wash",          one(e4b, lecture=F)),
        ("Risograph",         one(e5, style_index=71)),
    ]


async def main():
    jobs, meta = [], []
    sem = asyncio.Semaphore(6)
    async with httpx.AsyncClient() as client:
        for si, (label, row) in enumerate(sources(), 1):
            suffix = row["output"]["global_art_direction"]["flux_style_suffix"]
            scenes = sorted(row["output"]["image_prompts"], key=lambda p: p["topic_idx"])[:N_TOPICS]
            for order in ("current", "style_first"):
                for p in scenes:
                    scene = p["flux_scene_description"]
                    prompt = f"{scene}, {suffix}" if order == "current" else f"{suffix}. {scene}"
                    path = OUT / f"s{si}_{order}_t{p['topic_idx']}.jpg"
                    meta.append({"style": label, "style_no": si, "order": order, "topic_idx": p["topic_idx"], "file": path.name, "prompt": prompt})
                    jobs.append(fx_render(client, sem, path, prompt))
        await asyncio.gather(*jobs)
    (OUT / "manifest.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False))
    # one sheet per style: top row = current order, bottom row = style first
    TW, TH = 256, 341
    for si, (label, _) in enumerate(sources(), 1):
        items = [m for m in meta if m["style_no"] == si]
        cols = max(sum(1 for m in items if m["order"] == "current"), 1)
        sheet = Image.new("RGB", (cols * (TW + 6) + 6, 2 * (TH + 28) + 12), "white")
        d = ImageDraw.Draw(sheet)
        for r, order in enumerate(("current", "style_first")):
            row_items = [m for m in items if m["order"] == order]
            for c, m in enumerate(row_items):
                x, y = 6 + c * (TW + 6), 6 + r * (TH + 28)
                d.text((x + 2, y + 6), f"{label} / {order} / topic {m['topic_idx']}", fill="black")
                sheet.paste(Image.open(OUT / m["file"]).convert("RGB").resize((TW, TH)), (x, y + 24))
        sheet.save(OUT / f"sheet_{si}_{label.replace(' ', '_')}.jpg", quality=88)
    print(f"rendered {len(meta)} images; est. cost ${len(meta) * 0.000287:.4f}")


async def fx_render(client, sem, path, prompt):
    import base64
    async with sem:
        for attempt in range(3):
            r = await client.post(fx.URL, headers={"Authorization": f"Bearer {fx.TOKEN}"}, timeout=90.0,
                                  files={"prompt": (None, prompt), "width": (None, str(fx.W)), "height": (None, str(fx.H))})
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


if __name__ == "__main__":
    asyncio.run(main())
