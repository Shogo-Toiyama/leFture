"""Read-only: is each lecture's master_audio.m4a streamable from the middle?

For recent lectures with an audio_path it reads only the MP4 box headers via
ranged R2 reads (8-16 bytes per box) and reports:
  - file size and duration (lectures.audio_duration_seconds if present)
  - top-level box order: faststart (moov before mdat), moov-at-end, or fragmented (moof)
  - how the lecture was uploaded (metadata.upload_source / client hints if present)
Nothing is downloaded beyond box headers. No writes.

Usage: .venv/bin/python contents_generation/test_codes/audio_streaming_design/inspect_master_audio.py [--dry-run] [--lectures 40]
"""
import argparse, collections, datetime as dt, json, os, statistics, struct, sys


def boxes(s3, bucket, key, size, limit=64):
    out, off = [], 0
    while off < size and len(out) < limit:
        hdr = s3.get_object(Bucket=bucket, Key=key, Range=f"bytes={off}-{off + 15}")["Body"].read()
        if len(hdr) < 8:
            break
        n, typ = struct.unpack(">I4s", hdr[:8])
        if n == 1:
            n = struct.unpack(">Q", hdr[8:16])[0]
        elif n == 0:
            n = size - off
        out.append((typ.decode("latin-1"), off, n))
        if n < 8:
            break
        off += n
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--lectures", type=int, default=40)
    a = ap.parse_args()
    print("PLAN:", json.dumps({"lectures": a.lectures}))
    if a.dry_run:
        print("dry-run: no network calls")
        return
    sys.path.insert(0, "lefture_backend")
    from dotenv import load_dotenv
    load_dotenv("lefture_backend/.env")
    from supabase import create_client
    from app.core.r2_storage import R2StorageService

    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    r2 = R2StorageService()
    rows = (c.table("lectures").select("id,audio_path,audio_duration_seconds,metadata,created_at")
            .not_.is_("audio_path", "null").order("created_at", desc=True).limit(a.lectures).execute().data)

    results = []
    for r in rows:
        size = r2.object_size(r["audio_path"])
        if not size:
            continue
        bx = boxes(r2.s3, r2.bucket_name, r["audio_path"], size)
        types = [b[0] for b in bx]
        if bx and bx[0][0] not in ("ftyp",):
            head = r2.s3.get_object(Bucket=r2.bucket_name, Key=r["audio_path"], Range="bytes=0-3")["Body"].read()
            layout = "mp3" if head[:3] == b"ID3" or head[:2] in (b"\xff\xfb", b"\xff\xf3", b"\xff\xf2") else "unknown"
        elif "moof" in types:
            layout = "fragmented"
        elif "moov" in types and "mdat" in types:
            layout = "faststart" if types.index("moov") < types.index("mdat") else "moov_at_end"
        else:
            layout = "unknown:" + ",".join(types[:6])
        md = r.get("metadata") or {}
        results.append({
            "mb": round(size / 1e6, 1),
            "minutes": round((r.get("audio_duration_seconds") or 0) / 60, 1) or None,
            "layout": layout,
            "top_boxes": types[:6],
            "box_count": len(bx),
            "moov_kb": next((round(b[2] / 1024) for b in bx if b[0] == "moov"), None),
            "source_hint": md.get("upload_source") or md.get("source") or md.get("recorded_on"),
        })

    summary = {
        "lectures": len(results),
        "layout_counts": dict(collections.Counter(x["layout"] for x in results)),
        "mb": {"median": statistics.median(x["mb"] for x in results), "max": max(x["mb"] for x in results)},
        "moov_kb": {"median": statistics.median([x["moov_kb"] for x in results if x["moov_kb"]] or [0]),
                    "max": max([x["moov_kb"] for x in results if x["moov_kb"]] or [0])},
        "minutes_median": statistics.median([x["minutes"] for x in results if x["minutes"]] or [0]),
        "mb_per_min_median": statistics.median([x["mb"] / x["minutes"] for x in results if x["minutes"]] or [0]),
    }
    print(json.dumps(summary, indent=2))
    out = os.path.join(os.path.dirname(__file__), "results",
                       f"master_audio_layout_{dt.datetime.now().strftime('%Y%m%d_%H%M%S')}.json")
    with open(out, "w") as fh:
        json.dump({"summary": summary, "lectures": results}, fh, indent=2)
    print("saved", out)


if __name__ == "__main__":
    main()
