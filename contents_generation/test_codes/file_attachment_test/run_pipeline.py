"""
ファイル添付を、本番の想定どおり端から端まで通して、時間と原価を測る(2026-10-06)。

  1. LLMなしの取り出し(draftの段階): PDFの文字層 / docx・pptxの本文 / htmlはコードのまま
  2. ビジョンに回すページ・画像を決める(PDFはページの判定、docx・pptxは埋め込み画像)
  3. ビジョン(gpt-6-luna)で書き起こし、本文に差し込む
  4. 既存の read_attachment(審査 + 目次 + 要約)
写真(画像1枚)は 1・4 を飛ばしてビジョンだけ(画像は目次を作らない)。

実行例:
  python run_pipeline.py              # 全部
  python run_pipeline.py textbook     # 名前の一部で絞る
"""

import asyncio
import io
import json
import re
import sys
import time
import zipfile
from collections import Counter
from datetime import datetime
from pathlib import Path

from run_vision import MATERIALS, MODELS, PDF_RENDER_LONG_SIDE, REPO_ROOT, prepare, read_image  # noqa: E402

sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))
import app.services.chat_attachments as ca  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, UnifiedLLM  # noqa: E402
from PIL import Image  # noqa: E402

RESULTS = Path(__file__).parent / "results" / "pipeline"
VISION_MODEL = MODELS["luna"]
VISION_CONCURRENCY = 10

# ページをビジョンに回す判定(PDF)
MIN_TEXT_CHARS = 150          # これより文字が少ないページ(スキャン・画像だけのスライド)
MIN_IMAGE_AREA = 0.01         # 繰り返さない画像がページのこの割合以上を占める(図・写真・スクショ)
REPEATED_IMAGE_SHARE = 0.5    # 同じ位置の画像がこの割合以上のページにあれば、ロゴ・テンプレートとして無視
MIN_PATHS = 10                # 線・図形がこれ以上(表の罫線・図・分数の横棒)
SHORT_LINE_SHARE = 0.10       # 2文字以下の行の割合(数式が1文字ずつ崩れている)
# docx・pptxの埋め込み画像: これより小さい画像はビジョンに回さない(アイコン・飾り)
MIN_EMBED_PIXELS = 200 * 200


def visual_block(out: dict) -> str:
    if out.get("kind") == "decorative":
        return ""
    parts = [out.get("text", "").strip()]
    if out.get("visuals", "").strip():
        parts.append(f"[Visual: {out['visuals'].strip()}]")
    return "\n\n".join(p for p in parts if p)


class Meter:
    def __init__(self):
        self.vision_calls = 0
        self.vision_cost = 0.0
        self.vision_in = 0
        self.vision_out = 0
        self.blocked = 0
        self.errors = []

    async def read_all(self, items: list[tuple[str, bytes, str | None]]) -> dict[str, dict]:
        sem = asyncio.Semaphore(VISION_CONCURRENCY)

        async def one(key, jpeg, extracted):
            async with sem:
                return key, await read_image(VISION_MODEL, jpeg, extracted)

        results = dict(await asyncio.gather(*[one(*it) for it in items]))
        outs = {}
        for k, r in results.items():
            if "error" in r:
                self.errors.append(f"{k}: {r['error']}")
                continue
            self.vision_calls += 1
            self.vision_cost += r["cost_usd"]
            self.vision_in += r["input_tokens"]
            self.vision_out += r["output_tokens"]
            if r["output"].get("verdict") == "blocked" or r.get("finish_reason") == "content_filter":
                self.blocked += 1
            outs[k] = r["output"]
        return outs


# =========================================================
# PDF
# =========================================================

def classify_pdf(path: Path) -> list[dict]:
    import pypdfium2 as pdfium
    import pypdfium2.raw as pdfium_c

    pdf = pdfium.PdfDocument(str(path))
    pages = []
    bbox_count: Counter = Counter()
    for i in range(len(pdf)):
        page = pdf[i]
        w, h = page.get_size()
        text = page.get_textpage().get_text_range().strip()
        imgs = []
        for obj in page.get_objects(filter=[pdfium_c.FPDF_PAGEOBJ_IMAGE], max_depth=5):
            l, b, r, t = obj.get_bounds()
            area = max(0.0, min(r, w) - max(l, 0)) * max(0.0, min(t, h) - max(b, 0)) / (w * h)
            key = (round(l), round(b), round(r), round(t))
            imgs.append((key, area))
        for key in {k for k, _ in imgs}:
            bbox_count[key] += 1
        n_paths = sum(1 for _ in page.get_objects(filter=[pdfium_c.FPDF_PAGEOBJ_PATH], max_depth=5))
        lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
        short = sum(1 for ln in lines if len(ln) <= 2) / len(lines) if lines else 0.0
        pages.append({"page": i + 1, "text": text, "imgs": imgs, "paths": n_paths, "short_line_share": short})
    n = len(pages)
    for p in pages:
        own_area = sum(a for k, a in p["imgs"] if bbox_count[k] / n < REPEATED_IMAGE_SHARE or n < 3)
        reasons = []
        if len(p["text"]) < MIN_TEXT_CHARS:
            reasons.append(f"chars={len(p['text'])}")
        if own_area >= MIN_IMAGE_AREA:
            reasons.append(f"image={own_area:.2f}")
        if p["paths"] >= MIN_PATHS:
            reasons.append(f"paths={p['paths']}")
        if p["short_line_share"] >= SHORT_LINE_SHARE:
            reasons.append(f"short_lines={p['short_line_share']:.2f}")
        p["vision_reasons"] = reasons
    return pages


def render_pdf_page(path: Path, page_no: int) -> bytes:
    import pypdfium2 as pdfium
    pdf = pdfium.PdfDocument(str(path))
    p = pdf[page_no - 1]
    w, h = p.get_size()
    return prepare(p.render(scale=PDF_RENDER_LONG_SIDE / max(w, h)).to_pil(), PDF_RENDER_LONG_SIDE)


async def build_pdf(path: Path, meter: Meter, info: dict) -> str:
    t0 = time.perf_counter()
    pages = classify_pdf(path)
    info["classify_seconds"] = round(time.perf_counter() - t0, 2)
    vision_pages = [p for p in pages if p["vision_reasons"]]
    info["pages"] = len(pages)
    info["vision_pages"] = {p["page"]: p["vision_reasons"] for p in vision_pages}
    items = [(str(p["page"]), render_pdf_page(path, p["page"]), p["text"] or None) for p in vision_pages]
    t1 = time.perf_counter()
    outs = await meter.read_all(items)
    info["vision_seconds"] = round(time.perf_counter() - t1, 1)
    blocks = []
    for p in pages:
        body = visual_block(outs[str(p["page"])]) if str(p["page"]) in outs else p["text"]
        blocks.append(f"[p.{p['page']}]\n{body}")
    return "\n\n".join(blocks)


# =========================================================
# docx / pptx
# =========================================================

def _embed_ok(data: bytes) -> bool:
    try:
        im = Image.open(io.BytesIO(data))
        return im.size[0] * im.size[1] >= MIN_EMBED_PIXELS
    except Exception:
        return False


async def build_docx(path: Path, meter: Meter, info: dict) -> str:
    import docx
    from docx.table import Table
    from docx.text.paragraph import Paragraph

    d = docx.Document(str(path))
    # 本文の順に、段落・表・画像の位置を並べる(画像はあとで書き起こしに置き換える)
    pieces: list[tuple[str, str]] = []  # (kind, text or rId)
    for child in d.element.body.iterchildren():
        tag = child.tag.split("}")[-1]
        if tag == "p":
            p = Paragraph(child, d)
            text = p.text.strip()
            style = (p.style.name if p.style is not None else "") or ""
            if text:
                if style.lower().startswith("heading") or style.lower() == "title":
                    level = int(style.split()[-1]) if style.split()[-1].isdigit() else 1
                    text = "#" * level + " " + text
                pieces.append(("text", text))
            for rid in child.xpath(".//a:blip/@r:embed"):
                pieces.append(("image", rid))
        elif tag == "tbl":
            t = Table(child, d)
            rows = ["| " + " | ".join(c.text.strip().replace("\n", " ") for c in r.cells) + " |" for r in t.rows]
            pieces.append(("text", "\n".join(rows)))
    blobs = {}
    for kind, rid in pieces:
        if kind == "image" and rid not in blobs:
            blobs[rid] = d.part.related_parts[rid].blob
    targets = {rid: b for rid, b in blobs.items() if _embed_ok(b)}
    info["embedded_images"] = len(blobs)
    info["vision_images"] = len(targets)
    t1 = time.perf_counter()
    outs = await meter.read_all([(rid, prepare(Image.open(io.BytesIO(b))), None) for rid, b in targets.items()])
    info["vision_seconds"] = round(time.perf_counter() - t1, 1)
    out_lines, seen = [], set()
    for kind, val in pieces:
        if kind == "text":
            out_lines.append(val)
        elif val in outs and val not in seen:
            seen.add(val)
            block = visual_block(outs[val])
            if block:
                out_lines.append(f"[Image]\n{block}\n[/Image]")
    return "\n\n".join(out_lines)


async def build_pptx(path: Path, meter: Meter, info: dict) -> str:
    from pptx import Presentation
    from pptx.enum.shapes import MSO_SHAPE_TYPE

    prs = Presentation(str(path))

    def walk(shapes):
        for sh in shapes:
            if sh.shape_type == MSO_SHAPE_TYPE.GROUP:
                yield from walk(sh.shapes)
            else:
                yield sh

    slides = []
    items = []
    for i, s in enumerate(prs.slides, start=1):
        texts, pics = [], []
        for sh in walk(s.shapes):
            if sh.has_text_frame and sh.text_frame.text.strip():
                texts.append(sh.text_frame.text.strip())
            if getattr(sh, "has_table", False) and sh.has_table:
                texts.append("\n".join("| " + " | ".join(c.text.strip() for c in r.cells) + " |" for r in sh.table.rows))
            if sh.shape_type == MSO_SHAPE_TYPE.PICTURE:
                blob = sh.image.blob
                if _embed_ok(blob):
                    key = f"{i}:{len(pics)}"
                    pics.append(key)
                    items.append((key, prepare(Image.open(io.BytesIO(blob))), "\n".join(texts) or None))
        notes = s.notes_slide.notes_text_frame.text.strip() if s.has_notes_slide and s.notes_slide.notes_text_frame else ""
        slides.append((i, texts, pics, notes))
    info["slides"] = len(slides)
    info["vision_images"] = len(items)
    t1 = time.perf_counter()
    outs = await meter.read_all(items)
    info["vision_seconds"] = round(time.perf_counter() - t1, 1)
    blocks = []
    for i, texts, pics, notes in slides:
        body = list(texts) + [visual_block(outs[k]) for k in pics if k in outs]
        if notes:
            body.append(f"[Speaker notes]\n{notes}")
        blocks.append(f"[slide {i}]\n" + "\n\n".join(b for b in body if b))
    return "\n\n".join(blocks)


async def build_image(path: Path, meter: Meter, info: dict) -> str:
    t1 = time.perf_counter()
    outs = await meter.read_all([("img", prepare(Image.open(path)), None)])
    info["vision_seconds"] = round(time.perf_counter() - t1, 1)
    return visual_block(outs.get("img", {}))


async def build_code(path: Path, meter: Meter, info: dict) -> str:
    return path.read_text(errors="replace")


BUILDERS = {".pdf": build_pdf, ".docx": build_docx, ".pptx": build_pptx, ".html": build_code,
            ".jpg": build_image, ".jpeg": build_image, ".png": build_image}


async def run_one(path: Path) -> dict:
    meter = Meter()
    info: dict = {"file": path.name, "bytes": path.stat().st_size}
    t0 = time.perf_counter()
    text = await BUILDERS[path.suffix.lower()](path, meter, info)
    info["extract_and_vision_seconds"] = round(time.perf_counter() - t0, 1)
    info["chars"] = len(text)
    info["token_count"] = ca.estimate_tokens(text)
    info["vision"] = {"calls": meter.vision_calls, "cost_usd": round(meter.vision_cost, 5),
                      "input_tokens": meter.vision_in, "output_tokens": meter.vision_out,
                      "blocked": meter.blocked, "errors": meter.errors}
    is_image = BUILDERS[path.suffix.lower()] is build_image
    if not is_image:
        billing = BillingEngine(task_type="CHAT_MESSAGE")
        llm = UnifiedLLM(billing)
        t1 = time.perf_counter()
        r = await ca.read_attachment(llm, text)
        info["read"] = {"seconds": round(time.perf_counter() - t1, 1), "cost_usd": round(billing.total_usd(), 5),
                        "blocked": r.blocked, "error": r.error, "title": r.title, "summary": r.summary,
                        "sections": len(r.sections), "forbids_ai_code": r.forbids_ai_code,
                        "toc": [f"S{s.index} {s.title} — {s.description}" for s in r.sections]}
    info["total_seconds"] = round(time.perf_counter() - t0, 1)
    info["total_cost_usd"] = round(meter.vision_cost + (info.get("read", {}).get("cost_usd") or 0), 5)
    info["text"] = text
    return info


async def main() -> None:
    RESULTS.mkdir(parents=True, exist_ok=True)
    only = sys.argv[1] if len(sys.argv) > 1 else ""
    paths = [p for p in sorted(MATERIALS.iterdir()) if p.suffix.lower() in BUILDERS and only in p.name]
    # 資料どうしは並列(本番で5本まとめて送ったときに近い)
    results = await asyncio.gather(*[run_one(p) for p in paths])
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    (RESULTS / f"pipeline_{stamp}.json").write_text(json.dumps(results, ensure_ascii=False, indent=1))
    for r in results:
        (RESULTS / f"{Path(r['file']).stem}_{stamp}.txt").write_text(r["text"])
        read = r.get("read", {})
        print(f"\n▶ {r['file']} ({r['bytes'] / 1e6:.1f}MB)  chars={r['chars']:,} tokens≈{r['token_count']:,}")
        for k in ("pages", "slides", "embedded_images", "vision_images"):
            if k in r:
                print(f"   {k}: {r[k]}")
        if "vision_pages" in r:
            print(f"   vision pages: {len(r['vision_pages'])} → {r['vision_pages']}")
        v = r["vision"]
        print(f"   vision: {v['calls']} calls ${v['cost_usd']} in {r.get('vision_seconds', 0)}s blocked={v['blocked']} {v['errors'] or ''}")
        if read:
            print(f"   read: {read['seconds']}s ${read['cost_usd']} sections={read['sections']} blocked={read['blocked']} "
                  f"error={read['error']} forbids_ai_code={read['forbids_ai_code']}")
            print(f"   title: {read['title']}")
        print(f"   TOTAL {r['total_seconds']}s ${r['total_cost_usd']}")
    print(f"\n→ {RESULTS}/pipeline_{stamp}.json")


if __name__ == "__main__":
    asyncio.run(main())
