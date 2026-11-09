"""Read-only: compare 96x128 vs 192x256 thumbnails as they would look in the 44pt (132px @3x) LectureTile.

Downloads a few real topic images from R2 (no writes), makes both thumbnail sizes (WebP q70),
then renders each the way the tile does (center-crop square, scaled to 132x132) into one
comparison sheet. Saves sizes + the sheet into results/.

Usage: .venv/bin/python contents_generation/test_codes/image_thumbnail_size/compare_96.py [--dry-run] [--images 12]
"""
import argparse, datetime as dt, io, json, os, statistics, sys

SIZES = {"96x128": (96, 128), "192x256": (192, 256)}
TILE_PX = 132


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--images", type=int, default=12)
    a = ap.parse_args()
    print("PLAN:", json.dumps({"images": a.images, "sizes": SIZES, "tile_px": TILE_PX}))
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

    sizes = {k: [] for k in SIZES}
    sheet = Image.new("RGB", (TILE_PX * 3 + 40, (TILE_PX + 10) * min(4, len(rows))), "white")
    for i, r in enumerate(rows):
        img = Image.open(io.BytesIO(r2.download_binary(r["image_path"]))).convert("RGB")
        tiles = [ImageOps.fit(img, (TILE_PX, TILE_PX), Image.LANCZOS)]  # what the original gives today
        for k, (w, h) in SIZES.items():
            buf = io.BytesIO()
            img.resize((w, h), Image.LANCZOS).save(buf, "WEBP", quality=70)
            sizes[k].append(len(buf.getvalue()))
            thumb = Image.open(io.BytesIO(buf.getvalue())).convert("RGB")
            tiles.append(ImageOps.fit(thumb, (TILE_PX, TILE_PX), Image.LANCZOS))
        if i < 4:
            for j, t in enumerate(tiles):
                sheet.paste(t, (j * (TILE_PX + 20), i * (TILE_PX + 10)))

    summary = {k: {"kb_median": round(statistics.median(v) / 1024, 2), "kb_max": round(max(v) / 1024, 2)}
               for k, v in sizes.items()}
    print(json.dumps(summary, indent=2))
    here = os.path.dirname(__file__)
    stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    sheet_path = os.path.join(here, "results", f"tile_compare_{stamp}.png")
    sheet.save(sheet_path)
    with open(os.path.join(here, "results", f"compare_96_{stamp}.json"), "w") as fh:
        json.dump({"summary": summary, "raw_bytes": sizes,
                   "sheet_columns": ["original->tile", "96x128->tile", "192x256->tile"]}, fh, indent=2)
    print("sheet", sheet_path)


if __name__ == "__main__":
    main()
