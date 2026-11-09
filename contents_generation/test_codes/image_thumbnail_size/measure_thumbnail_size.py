"""Read-only: how small can topic-image thumbnails be?

Downloads a few real topic images from R2 (no writes), resizes them locally with
Pillow and reports byte sizes for candidate thumbnail formats:
  - tile   : 132x132 px (44 logical px x 3 DPR), center-crop square
  - slot   : 192x256 px (half of the 384x512 original), for the hero collage placeholder
  - inline : 48x64 px, base64 length (if embedded in a DB row)
Each in JPEG q70 and WebP q70. Saves a timestamped JSON plus sample files for a visual check.

Usage: .venv/bin/python contents_generation/test_codes/image_thumbnail_size/measure_thumbnail_size.py [--dry-run] [--images 12]
"""
import argparse, base64, datetime as dt, io, json, os, statistics, sys

VARIANTS = {"tile": (132, 132, True), "slot": (192, 256, False), "inline": (48, 64, False)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--images", type=int, default=12)
    a = ap.parse_args()
    print("PLAN:", json.dumps({"images": a.images, "variants": VARIANTS, "formats": ["JPEG q70", "WEBP q70"]}))
    if a.dry_run:
        print("dry-run: no network calls")
        return

    sys.path.insert(0, "lefture_backend")
    from dotenv import load_dotenv
    load_dotenv("lefture_backend/.env")
    from PIL import Image, ImageOps
    from supabase import create_client
    from app.core.r2_storage import R2StorageService

    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    r2 = R2StorageService()
    rows = (c.table("lecture_topics").select("image_path").not_.is_("image_path", "null")
            .order("created_at", desc=True).limit(a.images).execute().data)

    here = os.path.dirname(__file__)
    stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    sample_dir = os.path.join(here, "results", f"samples_{stamp}")
    os.makedirs(sample_dir, exist_ok=True)

    sizes = {f"{v}_{f}": [] for v in VARIANTS for f in ("jpeg", "webp")}
    originals = []
    for i, r in enumerate(rows):
        raw = r2.download_binary(r["image_path"])
        originals.append(len(raw))
        img = Image.open(io.BytesIO(raw)).convert("RGB")
        if i == 0:
            img.save(os.path.join(sample_dir, "original.jpg"), quality=95)
        for name, (w, h, square) in VARIANTS.items():
            t = ImageOps.fit(img, (w, h), Image.LANCZOS) if square else img.resize((w, h), Image.LANCZOS)
            for fmt, key in (("JPEG", "jpeg"), ("WEBP", "webp")):
                buf = io.BytesIO()
                t.save(buf, fmt, quality=70)
                b = buf.getvalue()
                n = len(base64.b64encode(b)) if name == "inline" else len(b)
                sizes[f"{name}_{key}"].append(n)
                if i == 0:
                    with open(os.path.join(sample_dir, f"{name}.{key}"), "wb") as fh:
                        fh.write(b)

    summary = {"images": len(rows),
               "original_kb_median": round(statistics.median(originals) / 1024, 1)}
    for k, v in sizes.items():
        unit = "base64_chars" if k.startswith("inline") else "kb"
        val = statistics.median(v) if unit == "base64_chars" else round(statistics.median(v) / 1024, 2)
        summary[f"{k}_{unit}_median"] = val
    print(json.dumps(summary, indent=2))
    out = os.path.join(here, "results", f"thumbnail_size_{stamp}.json")
    with open(out, "w") as fh:
        json.dump({"summary": summary, "raw_bytes": sizes, "original_bytes": originals}, fh, indent=2)
    print("saved", out, "samples in", sample_dir)


if __name__ == "__main__":
    main()
