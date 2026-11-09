"""
講義のマスター音声(`{uid}/{lectureId}/master_audio.m4a`)を、途中から再生できる形
(AAC + 索引(moov)がファイルの先頭にあるMP4 = faststart)に揃える。

アプリ/Webappは音声を丸ごとダウンロードせず、署名付きURLへのRangeリクエストで
再生位置の周りだけを取る(artifact_worker)。そのためには、プレイヤーが最初に
索引だけを読んで、任意の位置へ飛べる形である必要がある。実際にR2に入っている形は
次の通りで(2026-11-09、245講義を調査)、faststart以外は揃える:

- faststart (54%)            : そのまま。先頭の数バイトを読むだけで何もしない。
- 索引が末尾 (23%)            : 中身はそのまま並べ替え(`-c copy -movflags +faststart`)。
- 細切れ(fragmented MP4) (21%): 同上。アプリの録音確定時の作り直しが失敗すると残る。
- MP3 (2%)                   : 拡張子は.m4aだがMP3のまま。AACへ変換する。

上書きの前に、変換結果がAACで、長さが元とほぼ同じで、faststartであることを確かめる。
また、ダウンロード後にR2側が変わっていたら(再アップロード等)上書きしない。
"""
from __future__ import annotations

import json
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

from botocore.exceptions import ClientError

from app.core.r2_storage import storage_service

NORMALIZED_CONTENT_TYPE = "audio/mp4"
# 長さの許容差。AACへの変換ではエンコーダの遅延分(数十ミリ秒)ずれうる。
_DURATION_TOLERANCE_S = 1.0
_FFMPEG_TIMEOUT_S = 900


def _top_level_boxes_remote(key: str, size: int, limit: int = 8) -> list[str]:
    """R2上のMP4の先頭から、トップレベルのボックス名を数個だけ読む(Rangeで16バイトずつ)。"""
    s3, bucket = storage_service.s3, storage_service.bucket_name
    out: list[str] = []
    off = 0
    while off < size and len(out) < limit:
        hdr = s3.get_object(Bucket=bucket, Key=key, Range=f"bytes={off}-{off + 15}")["Body"].read()
        if len(hdr) < 8:
            break
        n, typ = struct.unpack(">I4s", hdr[:8])
        if n == 1 and len(hdr) >= 16:
            n = struct.unpack(">Q", hdr[8:16])[0]
        elif n == 0:
            n = size - off
        out.append(typ.decode("latin-1"))
        if n < 8:
            break
        off += n
    return out


def _top_level_boxes_local(path: Path, limit: int = 8) -> list[str]:
    out: list[str] = []
    size = path.stat().st_size
    with path.open("rb") as f:
        off = 0
        while off < size and len(out) < limit:
            f.seek(off)
            hdr = f.read(16)
            if len(hdr) < 8:
                break
            n, typ = struct.unpack(">I4s", hdr[:8])
            if n == 1 and len(hdr) >= 16:
                n = struct.unpack(">Q", hdr[8:16])[0]
            elif n == 0:
                n = size - off
            out.append(typ.decode("latin-1"))
            if n < 8:
                break
            off += n
    return out


def _layout_from_boxes(boxes: list[str], head: bytes) -> str:
    if head[4:8] != b"ftyp":
        if head[:3] == b"ID3" or head[:2] in (b"\xff\xfb", b"\xff\xf3", b"\xff\xf2"):
            return "mp3"
        return "other"
    if "moof" in boxes:
        return "fragmented"
    if "moov" in boxes and "mdat" in boxes:
        return "faststart" if boxes.index("moov") < boxes.index("mdat") else "moov_at_end"
    return "other"


def inspect_layout(key: str) -> tuple[str, int | None, str | None]:
    """(layout, size, etag)。layoutは faststart / moov_at_end / fragmented / mp3 / other / missing。"""
    try:
        head = storage_service.s3.head_object(Bucket=storage_service.bucket_name, Key=key)
    except ClientError:
        return "missing", None, None
    size = int(head["ContentLength"])
    etag = head.get("ETag")
    first = storage_service.s3.get_object(
        Bucket=storage_service.bucket_name, Key=key, Range="bytes=0-15"
    )["Body"].read()
    boxes = _top_level_boxes_remote(key, size) if first[4:8] == b"ftyp" else []
    return _layout_from_boxes(boxes, first), size, etag


def _probe(path: Path) -> dict:
    res = subprocess.run(
        ["ffprobe", "-v", "error", "-print_format", "json", "-show_format", "-show_streams", str(path)],
        capture_output=True, text=True, timeout=120, check=True,
    )
    data = json.loads(res.stdout)
    audio = next((s for s in data.get("streams", []) if s.get("codec_type") == "audio"), {})
    return {
        "codec": audio.get("codec_name"),
        "duration": float(data.get("format", {}).get("duration") or 0.0),
    }


def _head16(path: Path) -> bytes:
    with path.open("rb") as f:
        return f.read(16)


def convert_file(src: Path, dst: Path, layout: str) -> dict:
    """手元のファイル[src]をfaststartのAAC/MP4にして[dst]へ書き、検証結果を返す。
    R2には触らない(テストやバックフィルのドライランからも使う)。"""
    before = _probe(src)
    # MP4でもAAC以外なら変換する(-c copyでは他コーデックのまま残るため)。
    planned = "transcode" if layout == "mp3" or before["codec"] != "aac" else "remux"
    if planned == "remux":
        cmd = ["ffmpeg", "-y", "-v", "error", "-i", str(src), "-map", "0:a:0", "-c", "copy",
               "-movflags", "+faststart", "-f", "mp4", str(dst)]
    else:
        # アプリの録音と同じ64kbps・モノラル(講義の話し声には十分)。
        cmd = ["ffmpeg", "-y", "-v", "error", "-i", str(src), "-map", "0:a:0", "-vn",
               "-c:a", "aac", "-b:a", "64k", "-ac", "1", "-movflags", "+faststart", "-f", "mp4", str(dst)]
    subprocess.run(cmd, capture_output=True, text=True, timeout=_FFMPEG_TIMEOUT_S, check=True)

    after = _probe(dst)
    out_layout = _layout_from_boxes(_top_level_boxes_local(dst), _head16(dst))
    return {
        "planned": planned,
        "duration_before": round(before["duration"], 2),
        "duration_after": round(after["duration"], 2),
        "bytes_after": dst.stat().st_size,
        "checks": {
            "codec_aac": after["codec"] == "aac",
            "duration_match": abs(after["duration"] - before["duration"]) <= _DURATION_TOLERANCE_S,
            "faststart": out_layout == "faststart",
        },
    }


def normalize_master_audio(key: str, *, dry_run: bool = False) -> dict:
    """[key]の音声をfaststartのAAC/MP4に揃える(同期処理)。結果を辞書で返す。

    action: none(既に揃っている) / remux / transcode / skipped(dry_run) / missing /
            unsupported(判別できない形式) / changed(処理中に再アップロードされた) /
            failed(検証に失敗、上書きしていない)
    """
    layout, size, etag = inspect_layout(key)
    result: dict = {"key": key, "layout": layout, "bytes": size}
    if layout == "missing":
        return {**result, "action": "missing"}
    if layout == "faststart":
        return {**result, "action": "none"}
    if layout == "other":
        return {**result, "action": "unsupported"}

    planned = "transcode" if layout == "mp3" else "remux"
    if dry_run:
        return {**result, "action": "skipped", "planned": planned}

    work = Path(tempfile.mkdtemp(prefix="normalize_audio_"))
    try:
        src = work / "input"
        dst = work / "output.m4a"
        storage_service.download_file(key, src)
        converted = convert_file(src, dst, layout)
        result.update(converted)
        if not all(converted["checks"].values()):
            return {**result, "action": "failed"}

        # ダウンロード後に再アップロードされていたら、古い音声で上書きしない。
        current = storage_service.s3.head_object(Bucket=storage_service.bucket_name, Key=key)
        if current.get("ETag") != etag:
            return {**result, "action": "changed"}

        storage_service.s3.upload_file(
            str(dst), storage_service.bucket_name, key,
            ExtraArgs={"ContentType": NORMALIZED_CONTENT_TYPE},
        )
        return {**result, "action": converted["planned"]}
    except subprocess.CalledProcessError as e:
        return {**result, "action": "failed", "error": (e.stderr or str(e))[-500:]}
    finally:
        shutil.rmtree(work, ignore_errors=True)
