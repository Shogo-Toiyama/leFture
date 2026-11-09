"""Local test of lefture_backend/app/services/logic/audio_normalization.convert_file.

No R2 / Supabase access. For each layout found in production (faststart, moov at end,
fragmented MP4, MP3 named .m4a) it checks that:
  - the input layout is detected correctly,
  - convert_file produces AAC + faststart with the same duration (its own checks),
  - a remux decodes bit-identical to the original AAC file (MD5 of decoded PCM).
    The reference is v_faststart.m4a, not the input: a fragmented MP4 has no edit list,
    so it decodes the AAC encoder priming (640 samples at 16kHz, 40 ms) as extra audio.
    The remux puts the edit list back, so its output matches the original.

Make the inputs from any AAC .m4a (see the ffmpeg lines in the conversation log or below):
  ffmpeg -i in.m4a -c copy -f mp4 v_moov_end.m4a
  ffmpeg -i in.m4a -c copy -movflags +frag_keyframe+empty_moov+default_base_moof -frag_duration 2000000 v_frag.m4a
  ffmpeg -i in.m4a -c:a libmp3lame -b:a 64k -f mp3 v_mp3.m4a
  cp in.m4a v_faststart.m4a

Usage: .venv/bin/python contents_generation/test_codes/audio_streaming_design/normalize_local_test.py <dir with v_*.m4a>
"""
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, "lefture_backend")
from dotenv import load_dotenv  # noqa: E402

load_dotenv("lefture_backend/.env")
from app.services.logic.audio_normalization import (  # noqa: E402
    _head16, _layout_from_boxes, _top_level_boxes_local, convert_file,
)


def pcm_md5(path: Path) -> str:
    out = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-map", "0:a:0", "-f", "md5", "-"],
                         capture_output=True, text=True, check=True).stdout.strip()
    return out


def main():
    d = Path(sys.argv[1])
    expected = {"v_faststart.m4a": "faststart", "v_moov_end.m4a": "moov_at_end",
                "v_frag.m4a": "fragmented", "v_mp3.m4a": "mp3"}
    failed = 0
    for name, want in expected.items():
        src = d / name
        layout = _layout_from_boxes(_top_level_boxes_local(src), _head16(src))
        dst = d / f"out_{name}"
        r = convert_file(src, dst, layout)
        ok_detect = layout == want
        ok_checks = all(r["checks"].values())
        line = {"file": name, "detected": layout, "planned": r["planned"], "checks": r["checks"],
                "duration": [r["duration_before"], r["duration_after"]], "bytes_after": r["bytes_after"]}
        if r["planned"] == "remux":
            same = pcm_md5(d / "v_faststart.m4a") == pcm_md5(dst)
            line["decoded_audio_identical"] = same
            ok_checks = ok_checks and same
        status = "PASS" if ok_detect and ok_checks else "FAIL"
        failed += status == "FAIL"
        print(status, json.dumps(line, ensure_ascii=False))
    print("all passed" if not failed else f"{failed} FAILED")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
