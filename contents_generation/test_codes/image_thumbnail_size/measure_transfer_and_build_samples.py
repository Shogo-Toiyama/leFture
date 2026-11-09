"""Read-only: (1) measure how transfer size affects download time from R2, and
(2) build thumbnail samples (96x128 and 192x256 WebP q70) for a visual comparison page.

(1) For each image, GETs the same R2 object through a presigned URL with
    Range: first ~3KB (96x128 size), first ~9KB (192x256 size), and the whole object,
    interleaved, several rounds. Same object, same path; only the bytes transferred differ.
    Measured from this Mac, not from a phone or through the Cloudflare Worker.
(2) Writes original / 192 / 96 files as base64 into a JSON for the HTML page.

Only the given user's own images are used. No writes to R2 or Supabase.

Usage: .venv/bin/python contents_generation/test_codes/image_thumbnail_size/measure_transfer_and_build_samples.py --email <login email> [--dry-run] [--images 6] [--rounds 5]
"""
import argparse, base64, datetime as dt, io, json, os, statistics, sys, time

RANGES = {"96x128 (~3KB)": 3 * 1024, "192x256 (~9KB)": 9 * 1024, "original": None}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--email", required=True)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--images", type=int, default=6)
    ap.add_argument("--rounds", type=int, default=5)
    a = ap.parse_args()
    print("PLAN:", json.dumps({"images": a.images, "rounds": a.rounds, "ranges": list(RANGES)}))
    if a.dry_run:
        print("dry-run: no network calls")
        return

    sys.path.insert(0, "lefture_backend")
    from dotenv import load_dotenv
    load_dotenv("lefture_backend/.env")
    import httpx
    from PIL import Image
    from supabase import create_client
    from app.core.r2_storage import R2StorageService

    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    uid, page = None, 1
    while uid is None:
        users = c.auth.admin.list_users(page=page, per_page=200)
        if not users:
            break
        uid = next((u.id for u in users if (u.email or "").lower() == a.email.lower()), None)
        page += 1
    if uid is None:
        sys.exit("user not found")

    rows = (c.table("lecture_topics").select("image_path").eq("user_id", uid)
            .not_.is_("image_path", "null").order("created_at", desc=True).limit(a.images).execute().data)
    r2 = R2StorageService()

    timings = {k: [] for k in RANGES}
    samples = []
    with httpx.Client(timeout=30) as http:
        for r in rows:
            url = r2.generate_presigned_get_url(r["image_path"], expires_in=600)
            http.get(url, headers={"Range": "bytes=0-0"})  # warm the connection once per object
            for _ in range(a.rounds):
                for label, n in RANGES.items():
                    headers = {"Range": f"bytes=0-{n - 1}"} if n else {}
                    t0 = time.perf_counter()
                    resp = http.get(url, headers=headers)
                    resp.raise_for_status()
                    timings[label].append((time.perf_counter() - t0) * 1000)
            raw = r2.download_binary(r["image_path"])
            img = Image.open(io.BytesIO(raw)).convert("RGB")
            s = {"original": base64.b64encode(raw).decode(), "original_bytes": len(raw)}
            for name, size in (("t192", (192, 256)), ("t96", (96, 128))):
                buf = io.BytesIO()
                img.resize(size, Image.LANCZOS).save(buf, "WEBP", quality=70)
                s[name] = base64.b64encode(buf.getvalue()).decode()
                s[f"{name}_bytes"] = len(buf.getvalue())
            samples.append(s)

    summary = {k: {"median_ms": round(statistics.median(v), 1), "p90_ms": round(sorted(v)[int(len(v) * 0.9) - 1], 1),
                   "n": len(v)} for k, v in timings.items()}
    print(json.dumps(summary, indent=2))
    here = os.path.dirname(__file__)
    stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    with open(os.path.join(here, "results", f"transfer_timing_{stamp}.json"), "w") as fh:
        json.dump({"summary": summary, "raw_ms": timings,
                   "note": "presigned R2 GET from a Mac, Range requests on the same object"}, fh, indent=2)
    out = os.path.join(here, "results", f"samples_{stamp}.json")
    with open(out, "w") as fh:
        json.dump(samples, fh)
    print("samples", out)


if __name__ == "__main__":
    main()
