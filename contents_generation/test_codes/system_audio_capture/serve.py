"""Local server for the system-audio capture test page.

getDisplayMedia() only works in a secure context, and http://localhost counts as one,
so this serves the page on 127.0.0.1 and accepts POST /save?name=<file> to write
recordings and result JSON into ./results/ (timestamped names are chosen by the page).

Usage:
    python3 contents_generation/test_codes/system_audio_capture/serve.py [--port 8765]
"""

import argparse
import json
import re
import shutil
import subprocess
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

HERE = Path(__file__).resolve().parent
RESULTS = HERE / "results"
SAFE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.\-]{0,200}$")
MAX_BYTES = 2 * 1024 * 1024 * 1024  # 2 GB: a 3-hour opus recording is far below this


def ffprobe(path: Path):
    exe = shutil.which("ffprobe")
    if not exe:
        return {"available": False}
    proc = subprocess.run(
        [exe, "-v", "error", "-show_format", "-show_streams", "-of", "json", str(path)],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if proc.returncode != 0:
        return {"available": True, "ok": False, "stderr": proc.stderr.strip()}
    return {"available": True, "ok": True, "probe": json.loads(proc.stdout)}


class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def _json(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        url = urlparse(self.path)
        if url.path != "/save":
            return self._json(404, {"error": "not found"})
        name = (parse_qs(url.query).get("name") or [""])[0]
        if not SAFE_NAME.match(name) or ".." in name:
            return self._json(400, {"error": "invalid name"})
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_BYTES:
            return self._json(400, {"error": f"invalid length {length}"})

        RESULTS.mkdir(exist_ok=True)
        dest = RESULTS / name
        remaining = length
        with open(dest, "wb") as f:
            while remaining > 0:
                chunk = self.rfile.read(min(remaining, 1024 * 1024))
                if not chunk:
                    break
                f.write(chunk)
                remaining -= len(chunk)
        if remaining:
            dest.unlink(missing_ok=True)
            return self._json(400, {"error": "truncated upload"})

        result = {"saved": str(dest.relative_to(HERE)), "bytes": length}
        if dest.suffix.lower() not in (".json",):
            result["ffprobe"] = ffprobe(dest)
        print(f"[save] {dest.name} ({length} bytes)")
        return self._json(200, result)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    handler = partial(Handler, directory=str(HERE))
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    print(f"Open http://localhost:{args.port}/ in Chrome  (results -> {RESULTS})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
