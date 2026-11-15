"""Before/after measurement of lecture audio playback start, against production.

Before (old clients): GET the whole master_audio.m4a through the artifact worker with an
Authorization header. Playback can start only after this completes.
After (streaming): GET /sign for a signed URL, then let ffmpeg open the signed URL and
decode 1 second starting at 0%, 50% and 90% of the lecture. ffmpeg fetches only what it
needs with Range requests, the same way AVPlayer, ExoPlayer and browsers do. Time and
bytes read come from ffmpeg's own statistics.

Auth: mints a temporary session for --email (magic link + verify_otp). In `finally` it
signs out with scope "local", which revokes only this session. The account's other
sessions (phone, browser) stay signed in. No data is written.

Measured from this Mac over its network, not from a phone.

Usage: .venv/bin/python contents_generation/test_codes/audio_streaming_design/measure_streaming.py --email <email> [--dry-run] [--runs 3]
"""
import argparse
import datetime as dt
import json
import os
import re
import statistics
import subprocess
import sys
import time

WORKER = "https://lefture-artifact-worker.shogo-toiyama.workers.dev"
POSITIONS = (0.0, 0.5, 0.9)


def ffmpeg_start(url: str, seconds: float) -> dict:
    t0 = time.perf_counter()
    res = subprocess.run(
        ["ffmpeg", "-v", "debug", "-ss", f"{seconds:.2f}", "-i", url, "-t", "1", "-f", "null", "-"],
        capture_output=True, text=True, timeout=300,
    )
    elapsed = time.perf_counter() - t0
    m = re.findall(r"Statistics: (\d+) bytes read, (\d+) seeks", res.stderr)
    req = re.findall(r"Statistics: \d+ connections, (\d+) requests", res.stderr)
    return {
        "ok": res.returncode == 0,
        "ms": round(elapsed * 1000),
        "bytes": int(m[-1][0]) if m else None,
        "requests": int(req[-1]) if req else None,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--email", required=True)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--runs", type=int, default=3)
    a = ap.parse_args()
    print("PLAN:", json.dumps({"email": a.email, "positions": POSITIONS, "runs": a.runs,
                               "signout_scope": "local"}))
    if a.dry_run:
        print("dry-run: no network calls")
        return

    sys.path.insert(0, "lefture_backend")
    from dotenv import load_dotenv
    load_dotenv("lefture_backend/.env")
    import httpx
    from supabase import create_client
    from app.services.logic.audio_normalization import inspect_layout

    admin = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    link = admin.auth.admin.generate_link({"type": "magiclink", "email": a.email})
    auth_client = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    session = auth_client.auth.verify_otp({"type": "magiclink", "token_hash": link.properties.hashed_token}).session
    print("temporary session created")
    try:
        token = session.access_token
        uid = session.user.id
        rows = (admin.table("lectures").select("id,audio_path,audio_duration_seconds").eq("user_id", uid)
                .not_.is_("audio_path", "null").is_("deleted_at", "null").execute().data)
        sized = []
        for r in rows:
            layout, size, _ = inspect_layout(r["audio_path"])
            if layout == "faststart" and size:
                sized.append((size, r))
        sized.sort(key=lambda x: x[0])
        # a typical lecture (closest to the 32MB production median) and the largest one
        picks = [min(sized, key=lambda x: abs(x[0] - 32e6)), sized[-1]]

        report = []
        with httpx.Client(timeout=600) as http:
            for size, r in picks:
                key = r["audio_path"]
                entry = {"mb": round(size / 1e6, 1), "minutes": round((r["audio_duration_seconds"] or 0) / 60, 1)}

                t0 = time.perf_counter()
                got = 0
                with http.stream("GET", f"{WORKER}/{key}", headers={"Authorization": f"Bearer {token}"}) as resp:
                    resp.raise_for_status()
                    for chunk in resp.iter_bytes():
                        got += len(chunk)
                entry["before_full_download"] = {"ms": round((time.perf_counter() - t0) * 1000), "bytes": got}

                t0 = time.perf_counter()
                signed = http.get(f"{WORKER}/sign/{key}", headers={"Authorization": f"Bearer {token}"})
                entry["sign_ms"] = round((time.perf_counter() - t0) * 1000)
                signed.raise_for_status()
                url = signed.json()["url"]

                duration = float(r["audio_duration_seconds"] or 0)
                for pos in POSITIONS:
                    runs = [ffmpeg_start(url, duration * pos) for _ in range(a.runs)]
                    entry[f"after_start_at_{int(pos * 100)}pct"] = {
                        "ok": all(x["ok"] for x in runs),
                        "ms_median": statistics.median(x["ms"] for x in runs),
                        "kb_median": round(statistics.median(x["bytes"] or 0 for x in runs) / 1024, 1),
                        "requests_median": statistics.median(x["requests"] or 0 for x in runs),
                    }
                print(json.dumps(entry, ensure_ascii=False))
                report.append(entry)

        out = os.path.join(os.path.dirname(__file__), "results",
                           f"streaming_measure_{dt.datetime.now().strftime('%Y%m%d_%H%M%S')}.json")
        with open(out, "w") as fh:
            json.dump({"note": "from a Mac; before = whole-file download, after = sign + ffmpeg Range playback",
                       "lectures": report}, fh, indent=2)
        print("saved", out)
    finally:
        auth_client.auth.sign_out({"scope": "local"})
        print("temporary session signed out (scope=local)")


if __name__ == "__main__":
    main()
