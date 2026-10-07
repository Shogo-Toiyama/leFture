"""
ファイル添付のビジョン(画像・PDFのページ・スライド・docxの埋め込み画像を文字に直す)を、
実物の資料でモデルごとに比べる(2026-10-06)。

- 比べる: python run_vision.py compare
    TARGETSの各画像を、MODELSの各モデルで1回ずつ読む。結果は results/vision/compare_<時刻>/ に、
    モデル名を伏せた blind.md(採点用)と、伏せ字の対応・トークン・時間・原価の runs.json を書く。
- 1本まるごと: python run_vision.py deck <pptx|slides_pdf|textbook_pdf|docx> --model luna
    資料の全ページ(全スライド・全画像)を本番と同じく並列で読み、かかった時間と原価を測る。

画像の前処理(本番でもやる予定): 向きを直す(EXIF) → RGBにする(透過は白) → 長辺LONG_SIDEに縮小 →
JPEGで作り直す(EXIFのGPSなどは残らない)。
"""

import argparse
import asyncio
import base64
import io
import json
import random
import re
import sys
import time
import zipfile
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).parent
REPO_ROOT = HERE.resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv  # noqa: E402

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")

import litellm  # noqa: E402
from PIL import Image, ImageOps  # noqa: E402

from app.services.helpers.llm_unified import PRICE_MATRIX  # noqa: E402

litellm.suppress_debug_info = True

MATERIALS = HERE / "materials"
RESULTS = HERE / "results" / "vision"
PROMPT = (HERE / "vision_prompt.txt").read_text()

LONG_SIDE = 2048
PDF_RENDER_LONG_SIDE = 1600
JPEG_QUALITY = 88

SCHEMA = {
    "type": "object",
    "properties": {
        "verdict": {"type": "string", "enum": ["ok", "blocked"]},
        "kind": {"type": "string", "enum": ["document_page", "slide", "photo_of_board", "photo_of_slide",
                                            "handwritten_note", "screenshot", "chart_or_diagram", "photo_other",
                                            "decorative"]},
        "text": {"type": "string"},
        "visuals": {"type": "string"},
    },
    "required": ["verdict", "kind", "text", "visuals"],
}

MODELS = {
    "luna": "gpt-6-luna",
    "f25": "gemini/gemini-2.5-flash",
    "f38": "gemini/gemini-3.8-flash",
}


# =========================================================
# 画像の用意
# =========================================================

def prepare(img: Image.Image, long_side: int = LONG_SIDE) -> bytes:
    img = ImageOps.exif_transpose(img)
    if img.mode in ("RGBA", "LA", "P"):
        img = img.convert("RGBA")
        bg = Image.new("RGB", img.size, "white")
        bg.paste(img, mask=img.split()[-1])
        img = bg
    else:
        img = img.convert("RGB")
    if max(img.size) > long_side:
        img.thumbnail((long_side, long_side), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=JPEG_QUALITY)
    return buf.getvalue()


def image_file(name: str):
    return lambda: (prepare(Image.open(MATERIALS / name)), None)


def pdf_page(name: str, page: int):
    def load():
        import pypdfium2 as pdfium
        pdf = pdfium.PdfDocument(str(MATERIALS / name))
        p = pdf[page - 1]
        w, h = p.get_size()
        img = p.render(scale=PDF_RENDER_LONG_SIDE / max(w, h)).to_pil()
        text = p.get_textpage().get_text_range().strip()
        return prepare(img, PDF_RENDER_LONG_SIDE), text
    return load


def pptx_slide(name: str, slide: int):
    def load():
        z = zipfile.ZipFile(MATERIALS / name)
        rel = z.read(f"ppt/slides/_rels/slide{slide}.xml.rels").decode()
        media = re.search(r'Target="\.\./media/([^"]+)"', rel).group(1)
        return prepare(Image.open(io.BytesIO(z.read(f"ppt/media/{media}")))), None
    return load


def docx_media(name: str, media: str):
    def load():
        z = zipfile.ZipFile(MATERIALS / name)
        return prepare(Image.open(io.BytesIO(z.read(f"word/media/{media}")))), None
    return load


TARGETS = {
    "photo_blackboard": image_file("blackboard_picture.jpg"),
    "photo_slide": image_file("slide_picture.jpg"),
    "handwritten_jp": image_file("handwritten_note_jp.PNG"),
    "slides_pdf_p2": pdf_page("management_lecture_slides.pdf", 2),
    "slides_pdf_p8_table": pdf_page("management_lecture_slides.pdf", 8),
    "slides_pdf_p12_screenshot": pdf_page("management_lecture_slides.pdf", 12),
    "slides_pdf_p15_tiny_text": pdf_page("management_lecture_slides.pdf", 15),
    "textbook_p4_math": pdf_page("CS_algorithm_textbook.pdf", 4),
    "textbook_p6_figure": pdf_page("CS_algorithm_textbook.pdf", 6),
    "pptx_s6_pie": pptx_slide("UC_essay_slides.pptx", 6),
    "pptx_s12_small_en": pptx_slide("UC_essay_slides.pptx", 12),
    "pptx_s28_arrows": pptx_slide("UC_essay_slides.pptx", 28),
    "pptx_s31_list": pptx_slide("UC_essay_slides.pptx", 31),
    "docx_img1_logo": docx_media("management_essay.docx", "image1.png"),
    "docx_img2_rubric": docx_media("management_essay.docx", "image2.png"),
    "docx_img6_paper_table": docx_media("management_essay.docx", "image6.png"),
}


def deck_targets(deck: str) -> dict:
    if deck == "pptx":
        return {f"s{i:02d}": pptx_slide("UC_essay_slides.pptx", i) for i in range(1, 38)}
    if deck == "slides_pdf":
        return {f"p{i:02d}": pdf_page("management_lecture_slides.pdf", i) for i in range(1, 19)}
    if deck == "textbook_pdf":
        return {f"p{i:02d}": pdf_page("CS_algorithm_textbook.pdf", i) for i in range(1, 11)}
    if deck == "docx":
        return {f"img{i}": docx_media("management_essay.docx", f"image{i}.png") for i in range(1, 7)}
    raise SystemExit(f"unknown deck {deck}")


# =========================================================
# 呼び出し
# =========================================================

def cost_of(model: str, inp: int, out: int) -> float:
    p = PRICE_MATRIX["tokens"][model]
    return (inp * p["input"] + out * p["output"]) / 1_000_000


async def read_image(model: str, jpeg: bytes, extracted: str | None) -> dict:
    content = []
    if extracted:
        content.append({"type": "text", "text": f"<extracted_text>\n{extracted}\n</extracted_text>"})
    content.append({"type": "image_url",
                    "image_url": {"url": "data:image/jpeg;base64," + base64.b64encode(jpeg).decode()}})
    kwargs = dict(model=model, num_retries=2,
                  messages=[{"role": "system", "content": PROMPT}, {"role": "user", "content": content}],
                  response_format={"type": "json_schema", "json_schema": {"name": "output", "schema": SCHEMA}})
    if model.startswith("gpt-"):
        kwargs.update(temperature=1.0, reasoning_effort="none", allowed_openai_params=["reasoning_effort"],
                      max_completion_tokens=8192)
    elif "gemini-3" in model:
        kwargs.update(reasoning_effort="low", max_tokens=12000)
    else:
        kwargs.update(temperature=0.0, reasoning_effort="none", max_tokens=8192)
    t0 = time.perf_counter()
    try:
        res = await litellm.acompletion(**kwargs)
    except Exception as e:
        return {"error": f"{type(e).__name__}: {str(e)[:400]}", "seconds": round(time.perf_counter() - t0, 2)}
    sec = time.perf_counter() - t0
    raw = res.choices[0].message.content or ""
    try:
        out = json.loads(raw)
    except Exception:
        out = {"unparsed": raw}
    u = res.usage
    inp, outp = u.prompt_tokens, u.completion_tokens
    return {"output": out, "seconds": round(sec, 2), "input_tokens": inp, "output_tokens": outp,
            "cost_usd": round(cost_of(model, inp, outp), 6), "finish_reason": res.choices[0].finish_reason}


# =========================================================
# 実行
# =========================================================

async def compare(model_keys: list[str], target_keys: list[str]) -> None:
    run_dir = RESULTS / f"compare_{datetime.now():%Y%m%d_%H%M%S}"
    run_dir.mkdir(parents=True, exist_ok=True)
    prepared = {k: TARGETS[k]() for k in target_keys}
    sem = asyncio.Semaphore(12)

    async def one(t, m):
        async with sem:
            jpeg, extracted = prepared[t]
            r = await read_image(MODELS[m], jpeg, extracted)
            print(f"  {t:28s} {m:5s} {r.get('seconds')}s in={r.get('input_tokens')} out={r.get('output_tokens')} "
                  f"${r.get('cost_usd')} {r.get('error', '')[:120]}")
            return t, m, r

    results = await asyncio.gather(*[one(t, m) for t in target_keys for m in model_keys])
    runs = {}
    for t, m, r in results:
        runs.setdefault(t, {})[m] = r
    # モデル名を伏せた採点用の文書
    letters = "XYZWV"
    mapping = {}
    lines = ["# Blind outputs\n"]
    for t in target_keys:
        jpeg, extracted = prepared[t]
        (run_dir / f"{t}.jpg").write_bytes(jpeg)
        keys = list(model_keys)
        random.shuffle(keys)
        mapping[t] = {letters[i]: k for i, k in enumerate(keys)}
        lines.append(f"\n## {t}\n")
        for i, k in enumerate(keys):
            r = runs[t][k]
            lines.append(f"\n### {letters[i]}\n")
            lines.append("```json\n" + json.dumps(r.get("output", r.get("error")), ensure_ascii=False, indent=1) + "\n```\n")
    (run_dir / "blind.md").write_text("".join(lines))
    (run_dir / "runs.json").write_text(json.dumps({"mapping": mapping, "runs": runs}, ensure_ascii=False, indent=1))
    # モデルごとの合計
    for m in model_keys:
        rs = [runs[t][m] for t in target_keys if "error" not in runs[t][m]]
        if not rs:
            continue
        secs = sorted(r["seconds"] for r in rs)
        print(f"{m}: ok {len(rs)}/{len(target_keys)}  cost ${sum(r['cost_usd'] for r in rs):.4f}  "
              f"avg in {sum(r['input_tokens'] for r in rs) / len(rs):.0f} / out {sum(r['output_tokens'] for r in rs) / len(rs):.0f} "
              f"tokens  median {secs[len(secs) // 2]}s  max {secs[-1]}s")
    print(f"→ {run_dir}")


async def deck(deck_name: str, model_key: str, concurrency: int) -> None:
    targets = deck_targets(deck_name)
    run_dir = RESULTS / f"deck_{deck_name}_{model_key}_{datetime.now():%Y%m%d_%H%M%S}"
    run_dir.mkdir(parents=True, exist_ok=True)
    t0 = time.perf_counter()
    prepared = {k: f() for k, f in targets.items()}
    prep_s = time.perf_counter() - t0
    sem = asyncio.Semaphore(concurrency)

    async def one(k):
        async with sem:
            jpeg, extracted = prepared[k]
            return k, await read_image(MODELS[model_key], jpeg, extracted)

    t1 = time.perf_counter()
    results = dict(await asyncio.gather(*[one(k) for k in targets]))
    wall = time.perf_counter() - t1
    ok = [r for r in results.values() if "error" not in r]
    total_cost = sum(r["cost_usd"] for r in ok)
    md = [f"# {deck_name} / {model_key}\n"]
    for k, r in results.items():
        o = r.get("output", {})
        md.append(f"\n## {k} ({o.get('kind', '?')}, {r.get('seconds')}s)\n\n{o.get('text', r.get('error', ''))}\n")
        if o.get("visuals"):
            md.append(f"\n> visuals: {o['visuals']}\n")
    (run_dir / "transcript.md").write_text("".join(md))
    (run_dir / "runs.json").write_text(json.dumps(results, ensure_ascii=False, indent=1))
    print(f"{deck_name} / {model_key}: {len(ok)}/{len(targets)} ok, prepare {prep_s:.1f}s, wall {wall:.1f}s "
          f"(concurrency {concurrency}), cost ${total_cost:.4f}, "
          f"in {sum(r['input_tokens'] for r in ok)} / out {sum(r['output_tokens'] for r in ok)} tokens, "
          f"blocked {sum(1 for r in ok if r['output'].get('verdict') == 'blocked')}")
    print(f"→ {run_dir}")


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("compare")
    c.add_argument("--models", default=",".join(MODELS))
    c.add_argument("--targets", default=",".join(TARGETS))
    d = sub.add_parser("deck")
    d.add_argument("deck")
    d.add_argument("--model", default="luna")
    d.add_argument("--concurrency", type=int, default=10)
    args = ap.parse_args()
    if args.cmd == "compare":
        asyncio.run(compare(args.models.split(","), args.targets.split(",")))
    else:
        asyncio.run(deck(args.deck, args.model, args.concurrency))


if __name__ == "__main__":
    main()
