"""
ファイル添付の「LLMなしの取り出し」(draftの段階)で、どこまで取れるかを測る(2026-10-06)。

materials/ の各ファイルについて:
- PDF: ページごとの文字数・画像の数と面積の割合・取り出しの時間。ページを画像にした場合の時間も測る
- docx: 段落・見出し・表・埋め込み画像の数、取り出した文字数
- pptx: スライドごとの文字・ノート・画像の数、メディアの大きさ
- html: 本文の文字数
- 画像: 大きさ・EXIF(GPSの有無)

結果は results/extract/ に、ファイルごとの取り出したテキストと、まとめ(summary.json)を書く。

実行例:
  python extract_profile.py
"""

import io
import json
import time
import zipfile
from pathlib import Path

HERE = Path(__file__).parent
MATERIALS = HERE / "materials"
OUT = HERE / "results" / "extract"
RENDER = HERE / "results" / "rendered_pages"

# ページを画像にするときの長辺(px)。ビジョンに渡す大きさの候補
RENDER_LONG_SIDE = 1600


def profile_pdf(path: Path) -> dict:
    import pypdfium2 as pdfium
    import pypdfium2.raw as pdfium_c

    t0 = time.perf_counter()
    pdf = pdfium.PdfDocument(str(path))
    pages = []
    texts = []
    for i in range(len(pdf)):
        page = pdf[i]
        w, h = page.get_size()
        text = page.get_textpage().get_text_range()
        texts.append(f"[p.{i + 1}]\n{text.strip()}")
        img_area = 0.0
        n_img = 0
        for obj in page.get_objects(filter=[pdfium_c.FPDF_PAGEOBJ_IMAGE], max_depth=5):
            n_img += 1
            l, b, r, t = obj.get_bounds()
            img_area += max(0.0, min(r, w) - max(l, 0)) * max(0.0, min(t, h) - max(b, 0))
        n_path = sum(1 for _ in page.get_objects(filter=[pdfium_c.FPDF_PAGEOBJ_PATH], max_depth=5))
        pages.append({"page": i + 1, "chars": len(text.strip()), "images": n_img,
                      "image_area_ratio": round(min(img_area / (w * h), 1.0), 3), "paths": n_path,
                      "size_pt": [round(w), round(h)]})
    extract_s = time.perf_counter() - t0

    # 全ページを画像にする時間(ビジョンに回すページだけ描くが、上限の目安として全ページで測る)
    t1 = time.perf_counter()
    out_dir = RENDER / path.stem
    out_dir.mkdir(parents=True, exist_ok=True)
    for i in range(len(pdf)):
        page = pdf[i]
        w, h = page.get_size()
        scale = RENDER_LONG_SIDE / max(w, h)
        img = page.render(scale=scale).to_pil()
        img.save(out_dir / f"p{i + 1:03d}.png")
    render_s = time.perf_counter() - t1

    full = "\n\n".join(texts)
    (OUT / f"{path.stem}.txt").write_text(full)
    return {"kind": "pdf", "pages": len(pdf), "chars": sum(p["chars"] for p in pages),
            "extract_seconds": round(extract_s, 2), "render_all_seconds": round(render_s, 2),
            "page_detail": pages}


def profile_docx(path: Path) -> dict:
    import docx

    t0 = time.perf_counter()
    d = docx.Document(str(path))
    lines = []
    headings = 0
    # 本文の順番どおりに段落と表をたどる
    body = d.element.body
    for child in body.iterchildren():
        tag = child.tag.split("}")[-1]
        if tag == "p":
            p = docx.text.paragraph.Paragraph(child, d)
            style = (p.style.name if p.style is not None else "") or ""
            text = p.text.strip()
            if not text:
                continue
            if style.lower().startswith("heading") or style.lower() == "title":
                level = int(style.split()[-1]) if style.split()[-1].isdigit() else 1
                lines.append("#" * level + " " + text)
                headings += 1
            else:
                lines.append(text)
        elif tag == "tbl":
            t = docx.table.Table(child, d)
            for r in t.rows:
                lines.append("| " + " | ".join(c.text.strip().replace("\n", " ") for c in r.cells) + " |")
    text = "\n\n".join(lines)
    extract_s = time.perf_counter() - t0
    with zipfile.ZipFile(path) as z:
        media = [(n, z.getinfo(n).file_size) for n in z.namelist() if n.startswith("word/media/")]
    (OUT / f"{path.stem}.txt").write_text(text)
    return {"kind": "docx", "chars": len(text), "paragraphs": len(d.paragraphs), "headings": headings,
            "tables": len(d.tables), "inline_images": len(d.inline_shapes),
            "media_files": [{"name": n, "bytes": s} for n, s in media],
            "extract_seconds": round(extract_s, 2)}


def profile_pptx(path: Path) -> dict:
    from pptx import Presentation
    from pptx.enum.shapes import MSO_SHAPE_TYPE

    t0 = time.perf_counter()
    prs = Presentation(str(path))
    slide_w, slide_h = prs.slide_width, prs.slide_height
    slides = []
    texts = []

    def walk(shapes):
        for sh in shapes:
            if sh.shape_type == MSO_SHAPE_TYPE.GROUP:
                yield from walk(sh.shapes)
            else:
                yield sh

    for i, s in enumerate(prs.slides, start=1):
        parts, n_pic, pic_area, n_media = [], 0, 0, 0
        for sh in walk(s.shapes):
            if sh.has_text_frame and sh.text_frame.text.strip():
                parts.append(sh.text_frame.text.strip())
            if getattr(sh, "has_table", False) and sh.has_table:
                for r in sh.table.rows:
                    parts.append("| " + " | ".join(c.text.strip() for c in r.cells) + " |")
            if sh.shape_type == MSO_SHAPE_TYPE.PICTURE:
                n_pic += 1
                if sh.width and sh.height:
                    pic_area += sh.width * sh.height
            if sh.shape_type == MSO_SHAPE_TYPE.MEDIA:
                n_media += 1
        notes = ""
        if s.has_notes_slide:
            notes = s.notes_slide.notes_text_frame.text.strip() if s.notes_slide.notes_text_frame else ""
        body = "\n".join(parts)
        texts.append(f"[slide {i}]\n{body}" + (f"\n[notes]\n{notes}" if notes else ""))
        slides.append({"slide": i, "chars": len(body), "notes_chars": len(notes), "pictures": n_pic,
                       "picture_area_ratio": round(min(pic_area / (slide_w * slide_h), 1.0), 3), "media": n_media})
    extract_s = time.perf_counter() - t0
    with zipfile.ZipFile(path) as z:
        media = sorted(((n, z.getinfo(n).file_size) for n in z.namelist() if n.startswith("ppt/media/")),
                       key=lambda x: -x[1])
    full = "\n\n".join(texts)
    (OUT / f"{path.stem}.txt").write_text(full)
    return {"kind": "pptx", "slides": len(slides), "chars": len(full), "extract_seconds": round(extract_s, 2),
            "media_total_bytes": sum(s for _, s in media), "largest_media": [{"name": n, "bytes": s} for n, s in media[:8]],
            "slide_detail": slides}


def profile_html(path: Path) -> dict:
    from bs4 import BeautifulSoup

    t0 = time.perf_counter()
    raw = path.read_text(errors="replace")
    soup = BeautifulSoup(raw, "html.parser")
    for tag in soup(["script", "style", "noscript", "svg"]):
        tag.decompose()
    text = soup.get_text("\n")
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    text = "\n".join(lines)
    extract_s = time.perf_counter() - t0
    (OUT / f"{path.stem}.txt").write_text(text)
    return {"kind": "html", "raw_chars": len(raw), "chars": len(text), "imgs": len(soup.find_all("img")),
            "extract_seconds": round(extract_s, 3)}


def profile_image(path: Path) -> dict:
    from PIL import Image
    from PIL.ExifTags import TAGS

    img = Image.open(path)
    exif = img.getexif()
    names = {TAGS.get(k, k) for k in exif.keys()}
    has_gps = "GPSInfo" in names or bool(exif.get_ifd(0x8825))
    return {"kind": "image", "size_px": list(img.size), "mode": img.mode, "bytes": path.stat().st_size,
            "exif_tags": len(names), "has_gps": has_gps, "orientation": exif.get(0x0112)}


HANDLERS = {".pdf": profile_pdf, ".docx": profile_docx, ".pptx": profile_pptx, ".html": profile_html,
            ".htm": profile_html, ".jpg": profile_image, ".jpeg": profile_image, ".png": profile_image}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    summary = {}
    for path in sorted(MATERIALS.iterdir()):
        handler = HANDLERS.get(path.suffix.lower())
        if handler is None:
            continue
        print(f"▶ {path.name}")
        try:
            info = handler(path)
        except Exception as e:  # 曲者の資料で落ちたら、そのこと自体が結果
            info = {"error": f"{type(e).__name__}: {e}"}
        info["file_bytes"] = path.stat().st_size
        summary[path.name] = info
        brief = {k: v for k, v in info.items() if not k.endswith("_detail")}
        print("  ", json.dumps(brief, ensure_ascii=False)[:600])
    (OUT / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
