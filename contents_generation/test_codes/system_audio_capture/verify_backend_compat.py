"""Phase 0 check: can the production audio pipeline read Chrome MediaRecorder m4a files?

Chrome's MediaRecorder writes fragmented MP4 (ftyp, moov with mvhd duration 0, then moof/mdat pairs).
The backend reads durations and cuts clips with ffmpeg, so this replays the exact production commands:

  - lefture_backend/app/services/helpers/helpers.py::_get_audio_duration_seconds
      ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 <src>
      used on a local file (transcription.py) and on an R2 presigned URL (main.py, timeout=15 s)
  - modal/whisper_deploy_api.py::_extract_probe_clip
      ffmpeg -y -ss <offset> -t 30 -i <file> -ar 16000 -ac 1 -f wav <tmp>

against several ffmpeg versions (production: Ubuntu 22.04 -> 4.4.x on Modal, python:3.11-slim -> Debian ffmpeg on
Cloud Run), and serves the files over a local HTTP server with Range support and a fixed per-request latency
to stand in for the R2 presigned URL.

No external API is called ($0).

Usage:
  python3 verify_backend_compat.py [--latency-ms 40] [--synthetic-minutes 90] [extra.m4a ...]
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
RESULTS = HERE / "results"
WORK = RESULTS / "synthetic"

FFMPEG_VERSIONS = {
    "4.4 (Modal: ubuntu22.04)": "/opt/homebrew/opt/ffmpeg@4/bin",
    "5.1 (Debian bookworm)": "/opt/homebrew/opt/ffmpeg@5/bin",
    "7.1 (Debian trixie)": "/opt/homebrew/opt/ffmpeg@7/bin",
    "9.0 (latest)": "/opt/homebrew/bin",
}
BACKEND_PROBE_TIMEOUT = 15  # helpers.py: subprocess.run(..., timeout=15)


# --------------------------------------------------------------------------- HTTP stand-in for R2
class Stats:
    def __init__(self):
        self.lock = threading.Lock()
        self.requests = 0
        self.bytes = 0

    def reset(self):
        with self.lock:
            self.requests = 0
            self.bytes = 0


STATS = Stats()
LATENCY = 0.04
ROOT = RESULTS


class RangeHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def _serve(self, head_only):
        path = (ROOT / self.path.lstrip("/").split("?")[0]).resolve()
        if not str(path).startswith(str(ROOT.resolve())) or not path.is_file():
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        size = path.stat().st_size
        start, end = 0, size - 1
        status = 200
        rng = self.headers.get("Range")
        if rng:
            m = re.match(r"bytes=(\d*)-(\d*)", rng)
            if m:
                if m.group(1):
                    start = int(m.group(1))
                    if m.group(2):
                        end = min(int(m.group(2)), size - 1)
                else:  # suffix range
                    start = max(0, size - int(m.group(2)))
                status = 206
        with STATS.lock:
            STATS.requests += 1
        time.sleep(LATENCY)
        if start > end or start >= size:
            self.send_response(416)
            self.send_header("Content-Range", f"bytes */{size}")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self.send_response(status)
        self.send_header("Content-Type", "audio/x-m4a")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if head_only:
            return
        with open(path, "rb") as f:
            f.seek(start)
            remaining = end - start + 1
            try:
                while remaining > 0:
                    chunk = f.read(min(65536, remaining))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    with STATS.lock:
                        STATS.bytes += len(chunk)
                    remaining -= len(chunk)
            except (BrokenPipeError, ConnectionResetError):
                pass

    def do_GET(self):
        self._serve(False)

    def do_HEAD(self):
        self._serve(True)


# --------------------------------------------------------------------------- helpers
def mp4_layout(path: Path):
    """Top-level box counts and mvhd duration (0 means 'unknown' in fragmented MP4)."""
    import struct

    data = path.read_bytes()
    counts, mvhd = {}, None

    def walk(off, end, depth):
        nonlocal mvhd
        while off + 8 <= end:
            size, typ = struct.unpack(">I4s", data[off:off + 8])
            typ = typ.decode("latin1")
            hdr = 8
            if size == 1:
                size = struct.unpack(">Q", data[off + 8:off + 16])[0]
                hdr = 16
            elif size == 0:
                size = end - off
            if depth == 0:
                counts[typ] = counts.get(typ, 0) + 1
            if typ == "mvhd":
                v = data[off + 8]
                ts, dur = (struct.unpack(">II", data[off + 20:off + 28]) if v == 0
                           else struct.unpack(">IQ", data[off + 28:off + 40]))
                mvhd = {"timescale": ts, "duration": dur}
            if typ in ("moov",):
                walk(off + hdr, off + size, depth + 1)
            off += size

    walk(0, len(data), 0)
    return {"top_level": counts, "mvhd": mvhd, "bytes": len(data)}


def run_probe(bin_dir, src):
    t = time.perf_counter()
    try:
        proc = subprocess.run(
            [f"{bin_dir}/ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1", str(src)],
            capture_output=True, text=True, timeout=BACKEND_PROBE_TIMEOUT,
        )
        out = proc.stdout.strip()
        try:
            value = float(out)  # exactly what helpers.py does
            err = None
        except ValueError:
            value, err = None, f"float() would raise on {out!r}; stderr={proc.stderr.strip()[:200]!r}"
    except subprocess.TimeoutExpired:
        value, err = None, f"timeout after {BACKEND_PROBE_TIMEOUT}s (backend would raise)"
    return {"duration": value, "error": err, "seconds": round(time.perf_counter() - t, 2)}


def run_clip(bin_dir, src, offset):
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        t = time.perf_counter()
        proc = subprocess.run(
            [f"{bin_dir}/ffmpeg", "-y", "-ss", str(max(0.0, offset)), "-t", "30", "-i", str(src),
             "-ar", "16000", "-ac", "1", "-f", "wav", tmp.name],
            capture_output=True, text=True,
        )
        elapsed = time.perf_counter() - t
        if proc.returncode != 0:
            return {"offset": offset, "ok": False, "stderr": proc.stderr.strip()[-300:]}
        wav_bytes = os.path.getsize(tmp.name)
        clip_seconds = max(0, wav_bytes - 44) / (16000 * 2)
        return {"offset": round(offset, 1), "ok": True, "clip_seconds": round(clip_seconds, 2),
                "seconds": round(elapsed, 2)}


def make_synthetic(minutes, frag_seconds):
    """Fragmented MP4 shaped like Chrome's output: empty moov (mvhd duration 0) + one moof/mdat per fragment."""
    WORK.mkdir(parents=True, exist_ok=True)
    out = WORK / f"synthetic_{minutes}min_frag{frag_seconds}s.m4a"
    if out.exists():
        return out
    subprocess.run(
        ["/opt/homebrew/bin/ffmpeg", "-v", "error", "-y",
         "-f", "lavfi", "-i", f"sine=frequency=440:sample_rate=48000:duration={minutes * 60}",
         "-ac", "2", "-c:a", "aac", "-b:a", "64k",
         "-movflags", "+empty_moov+default_base_moof+separate_moof",
         "-frag_duration", str(int(frag_seconds * 1_000_000)),
         str(out)],
        check=True,
    )
    return out


# --------------------------------------------------------------------------- main
def main():
    global LATENCY
    ap = argparse.ArgumentParser()
    ap.add_argument("--latency-ms", type=float, default=40.0)
    ap.add_argument("--synthetic-minutes", type=int, default=90)
    ap.add_argument("--dry-run", action="store_true", help="only list files/versions and file layouts")
    ap.add_argument("files", nargs="*")
    args = ap.parse_args()
    LATENCY = args.latency_ms / 1000

    versions = {k: v for k, v in FFMPEG_VERSIONS.items() if Path(v, "ffprobe").exists()}
    files = [Path(f).resolve() for f in args.files] or sorted(RESULTS.glob("*.m4a"))
    if not args.dry_run:
        files += [make_synthetic(args.synthetic_minutes, 1), make_synthetic(args.synthetic_minutes, 10)]

    report = {"run_at": datetime.now().isoformat(), "latency_ms_per_request": args.latency_ms,
              "versions": list(versions), "files": {}}
    print(f"versions: {list(versions)}")
    for f in files:
        report["files"][f.name] = {"layout": mp4_layout(f)}
        print(f"file: {f.name} {report['files'][f.name]['layout']}")
    if args.dry_run:
        return

    server = ThreadingHTTPServer(("127.0.0.1", 0), RangeHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    port = server.server_address[1]

    for f in files:
        rel = f.relative_to(RESULTS)
        url = f"http://127.0.0.1:{port}/{rel.as_posix()}"
        entry = report["files"][f.name]
        entry["by_version"] = {}
        for label, bin_dir in versions.items():
            local = run_probe(bin_dir, f)
            STATS.reset()
            http = run_probe(bin_dir, url)
            http.update({"requests": STATS.requests, "bytes_read": STATS.bytes,
                         "file_fraction_read": round(STATS.bytes / f.stat().st_size, 3)})
            dur = local["duration"] or 0
            offsets = [0.0] if dur <= 60 else [dur * p for p in (0.1, 0.3, 0.5, 0.7, 0.9)]
            clips = [run_clip(bin_dir, f, o) for o in offsets]
            entry["by_version"][label] = {"probe_local": local, "probe_http": http, "clips": clips}
            print(f"  [{label}] {f.name}: local={local} http={http} "
                  f"clips={[(c['offset'], c.get('clip_seconds'), c['ok']) for c in clips]}")
    server.shutdown()

    RESULTS.mkdir(exist_ok=True)
    out = RESULTS / f"backend_compat_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False))
    print(f"saved {out.relative_to(HERE)}")


if __name__ == "__main__":
    main()
