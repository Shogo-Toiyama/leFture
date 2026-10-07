# app/services/chat_files.py
"""
チャットに添付するファイル(PDF・Word・PowerPoint・画像)。docs/chatbot_context_and_retrieval_roadmap.md 10章
「ファイルの添付」(2026-10-05〜06に合意、実物8点での検証は contents_generation/test_codes/file_attachment_test/)。

方針: 添付するときに一度だけテキストに直し、そこから先はテキストの資料と同じ仕組み(節・目次・要約・検索・
全文で読む選択)に乗せる。画像の資料だけは、全文で読む(選択中)ときに画像そのものも回答役に渡す。

    端末: 画像・docx/pptxの中の画像を縮める(PDFはそのまま) → アップロード先を頼む(draftの行)→ R2へPUT
                                      ↓
    extract_file(LLMなし・無料・送る前): PDFの文字層 / docx・pptxの本文と埋め込み画像 / 画像。
        画像として読む部分を決め、縮めたJPEGをR2に置く。単位(Unit)の並びをextractionに保存
                                      ↓
    送信 → そのターンの最初に transcribe_file: 画像として読む部分をビジョン(GPT-6 Luna)で書き起こし、
        本文に差し込む → (画像以外は)chat_attachments.read_attachment で審査・目次・要約

- PDFのページを画像として読むのは、文字が少ない(スキャン・画像だけのスライド)・ページ固有の画像がある・
  線や図形が多い(表の罫線・図・分数の横棒)・短い行が多い(数式が1文字ずつ崩れている)ページだけ。
  文字層は正確なので、ビジョンには文字層も渡して綴りと数字はそちらに合わせさせる。
- ビジョンのモデルはLuna(2026-10-06に16枚×3モデルで比較)。Gemini 3.8 Flashは写真が最も正確だが約12倍で、
  論文の表の書き写しを content_filter(RECITATIONとみられる)で止めた。本番ではそれが「断った」扱いになり、
  教科書を添付しただけで断られた回数が増えてしまうので使わない。2.5 Flashは密な表で同じ文を繰り返し続けた。
- PDFは端末で縮められないので上限が大きい(MAX_UPLOAD_BYTES)。サーバーは必要なページだけを描くので重くない。
- pptxのスライドそのものを画像にするにはLibreOfficeが要るので使わない。本文と埋め込み画像を読む
  (図形で描いた図・SmartArtの見た目は取れない)。
"""

import asyncio
import hashlib
import io
import re
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Awaitable, Callable, Optional

from PIL import Image, ImageOps

from app.services.helpers.helpers import _load_prompt
from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM


# =========================================================
# ⚙️ 設定
# =========================================================

VISION_MODEL = "gpt-6-luna"

KIND_BY_EXTENSION = {
    ".pdf": "pdf", ".docx": "docx", ".pptx": "pptx",
    ".jpg": "image", ".jpeg": "image", ".png": "image", ".webp": "image",
}
# 端末がR2へPUTするときのContent-Type(署名に含まれる)。画像は端末がJPEGに縮めてから送る
UPLOAD_CONTENT_TYPES = {
    "pdf": "application/pdf",
    "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    "image": "image/jpeg",
}
# 上限(バイト)。画像・docx・pptxは端末で縮めた後の大きさ(今回のpptx 32MBは縮めると5.4MB)。
# PDFは端末で縮められないので大きめ(スキャンしたPDFが大きくなりやすい)
MAX_UPLOAD_BYTES = {"pdf": 100 * 1024 * 1024, "docx": 30 * 1024 * 1024,
                    "pptx": 30 * 1024 * 1024, "image": 30 * 1024 * 1024}
MAX_PAGES = 500                 # PDFのページ・pptxのスライド
MAX_VISION_IMAGES = 60          # 1本でビジョンに回す画像・ページ(37枚のpptxが収まる)
MAX_DRAFTS_PER_USER = 20        # 送っていないdraftの数(作りすぎの歯止め)
DRAFT_TTL_HOURS = 24            # 送られなかったdraftを消すまで
# zipの中身(docx・pptx)の歯止め(展開すると巨大になるファイル)
MAX_ZIP_UNCOMPRESSED_BYTES = 400 * 1024 * 1024
MAX_ZIP_ENTRIES = 20_000
MAX_IMAGE_PIXELS = 80_000_000
EXTRACT_TIMEOUT_SECONDS = 120

# ビジョンに渡す画像の長辺(写真・埋め込み画像)と、PDFのページを描く長辺
VISION_LONG_SIDE = 2048
PDF_RENDER_LONG_SIDE = 1600
JPEG_QUALITY = 88
# 回答役に毎ターン渡す画像の長辺。Lunaのトークン数はほぼ 縦×横÷850 で、2048pxの写真は約2,800、
# 1536pxは約1,550(2026-10-06に実測)。文字の読み取りは書き起こしを一緒に渡して補う
ANSWER_IMAGE_LONG_SIDE = 1536
IMAGE_PIXELS_PER_TOKEN = 850

# PDFのページを画像として読む判定(2026-10-06に教科書・スライドPDFで調整)
MIN_TEXT_CHARS = 150            # 文字がこれより少ない(スキャン・画像だけのスライド)
MIN_OWN_IMAGE_AREA = 0.01       # ページ固有の画像がページのこの割合以上(図・写真・スクショ)
REPEATED_IMAGE_SHARE = 0.5      # 同じ位置の画像がこの割合以上のページにあれば、ロゴ・テンプレートとして無視
MIN_PATHS = 10                  # 線・図形がこれ以上(表の罫線・図・分数の横棒)
SHORT_LINE_SHARE = 0.10         # 数字だけでない2文字以下の行の割合(数式が1文字ずつ崩れている)
SHORT_LINE_MIN = 3
# docx・pptxの埋め込み画像: これより小さい画像は読まない(アイコン・飾り)
MIN_EMBED_PIXELS = 200 * 200
# 書き起こし1回あたりの文字数の見積もり(送る前に10万字を超えそうかを判定する)
EST_CHARS_PER_VISION = 1500
EST_TOKENS_PER_VISION = 500
VISION_MAX_TOKENS = 8192

VISION_SCHEMA: dict[str, Any] = {
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
# 画像1枚だけの資料: 目次・要約役を通さないので、名前と要約もここで作る
STANDALONE_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        **VISION_SCHEMA["properties"],
        "title": {"type": "string"},
        "summary": {"type": "string"},
        "forbids_ai_code": {"type": "boolean"},
    },
    "required": [*VISION_SCHEMA["required"], "title", "summary", "forbids_ai_code"],
}


class FileError(Exception):
    """取り出せないファイル。codeは画面の出し分けに使う。"""

    def __init__(self, code: str, message: str, extra: Optional[dict] = None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.extra = extra or {}


def kind_for(file_name: str) -> Optional[str]:
    return KIND_BY_EXTENSION.get(Path(file_name or "").suffix.lower())


def storage_prefix(user_id: str, attachment_id: str) -> str:
    return f"{user_id}/chat_attachments/{attachment_id}/"


def upload_key(prefix: str, kind: str) -> str:
    return prefix + {"pdf": "original.pdf", "docx": "original.docx", "pptx": "original.pptx",
                     "image": "upload.jpg"}[kind]


# =========================================================
# 🧩 データの形
# =========================================================

@dataclass
class Unit:
    """
    本文の1かたまり(PDFの1ページ・pptxの1スライド・docxの段落のまとまりや画像1枚)。
    - label: 本文に入れる位置の印("p.3" / "slide 3")。目次の節の区切りの候補にもなる。docxは無し
    - text: 取り出した文字
    - images: ビジョンで読む画像のキー(extraction.imagesでR2のキーに引く)
    - replace: Trueなら書き起こしでtextを置き換える(PDFのページ。textは綴りの手がかりとして渡す)。
      Falseならtextの後ろに書き起こしを足す(docx・pptxの埋め込み画像)
    - tail: 書き起こしの後ろに置く文字(pptxのノート)
    """
    label: Optional[str] = None
    text: str = ""
    images: list[str] = field(default_factory=list)
    replace: bool = False
    tail: str = ""
    reasons: list[str] = field(default_factory=list)

    def to_json(self) -> dict:
        return {k: v for k, v in {"label": self.label, "text": self.text, "images": self.images,
                                  "replace": self.replace or None, "tail": self.tail or None,
                                  "reasons": self.reasons or None}.items() if v}

    @classmethod
    def from_json(cls, raw: dict) -> "Unit":
        return cls(label=raw.get("label"), text=raw.get("text") or "", images=list(raw.get("images") or []),
                   replace=bool(raw.get("replace")), tail=raw.get("tail") or "", reasons=list(raw.get("reasons") or []))


@dataclass
class Extraction:
    """extract_fileの結果。imagesはキー → JPEGのバイト列(R2に置いた後はキー → R2のキーで保存する)。"""
    kind: str
    units: list[Unit]
    images: dict[str, bytes]
    page_count: Optional[int] = None
    warnings: list[str] = field(default_factory=list)

    @property
    def text_chars(self) -> int:
        return sum(len(u.text) + len(u.tail) for u in self.units if not u.replace)

    @property
    def vision_count(self) -> int:
        return len({k for u in self.units for k in u.images})

    @property
    def estimated_chars(self) -> int:
        return self.text_chars + self.vision_count * EST_CHARS_PER_VISION

    def estimated_tokens(self) -> int:
        """全文で読むときのトークン数の見積もり(送る前の表示用。送った後に書き起こしから数え直す)。"""
        from app.services.chat_attachments import estimate_tokens
        text = "".join(u.text + u.tail for u in self.units if not u.replace)
        tokens = estimate_tokens(text) + self.vision_count * EST_TOKENS_PER_VISION
        if self.kind == "image" and "main" in self.images:
            tokens += image_tokens(self.images["main"])
        return tokens


# =========================================================
# 🖼️ 画像の前処理
# =========================================================

def prepare_image(img: Image.Image, long_side: int = VISION_LONG_SIDE) -> bytes:
    """向きを直す(EXIF) → RGB(透過は白) → 長辺long_sideに縮小 → JPEGで作り直す(GPSなどのEXIFは残らない)。"""
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


def answer_image(jpeg: bytes) -> bytes:
    """回答役に毎ターン渡す大きさに縮める。"""
    img = Image.open(io.BytesIO(jpeg))
    if max(img.size) <= ANSWER_IMAGE_LONG_SIDE:
        return jpeg
    return prepare_image(img, ANSWER_IMAGE_LONG_SIDE)


def image_tokens(jpeg: bytes) -> int:
    """回答役に渡したときのトークン数の概算(answer_imageの大きさで)。"""
    w, h = Image.open(io.BytesIO(jpeg)).size
    scale = min(1.0, ANSWER_IMAGE_LONG_SIDE / max(w, h))
    return -(-int(w * scale) * int(h * scale) // IMAGE_PIXELS_PER_TOKEN)


def _open_image(data: bytes) -> Image.Image:
    img = Image.open(io.BytesIO(data))
    img.load()
    return img


def _embed_ok(data: bytes) -> bool:
    try:
        w, h = Image.open(io.BytesIO(data)).size
        return w * h >= MIN_EMBED_PIXELS
    except Exception:
        return False


# =========================================================
# 📄 取り出し(LLMなし)
# =========================================================

def _check_zip(path: Path, required: str) -> None:
    try:
        with zipfile.ZipFile(path) as z:
            infos = z.infolist()
            names = {i.filename for i in infos}
    except zipfile.BadZipFile:
        raise FileError("FILE_CORRUPT", "The file could not be opened.")
    if required not in names:
        raise FileError("FILE_CORRUPT", "The file is not a valid document of this type.")
    if len(infos) > MAX_ZIP_ENTRIES or sum(i.file_size for i in infos) > MAX_ZIP_UNCOMPRESSED_BYTES:
        raise FileError("FILE_TOO_COMPLEX", "The file is too large to read once unpacked.")


def _short_line_share(lines: list[str]) -> tuple[float, int]:
    short = [ln for ln in lines if len(ln) <= 2 and not ln.isdigit()]
    return (len(short) / len(lines) if lines else 0.0), len(short)


def _extract_pdf(path: Path) -> Extraction:
    import pypdfium2 as pdfium
    import pypdfium2.raw as pdfium_c

    with open(path, "rb") as f:
        if b"%PDF-" not in f.read(1024):
            raise FileError("FILE_CORRUPT", "The file is not a PDF.")
    try:
        pdf = pdfium.PdfDocument(str(path))
    except pdfium.PdfiumError as e:
        if "password" in str(e).lower():
            raise FileError("PDF_ENCRYPTED", "Password-protected PDFs cannot be read.")
        raise FileError("FILE_CORRUPT", "The PDF could not be opened.")
    n = len(pdf)
    if n == 0:
        raise FileError("FILE_EMPTY", "The PDF has no pages.")
    if n > MAX_PAGES:
        raise FileError("TOO_MANY_PAGES", f"The file has more than {MAX_PAGES} pages.", {"max_pages": MAX_PAGES})

    pages = []
    bbox_pages: dict[tuple, int] = {}
    for i in range(n):
        page = pdf[i]
        w, h = page.get_size()
        text = page.get_textpage().get_text_range().strip()
        imgs = []
        for obj in page.get_objects(filter=[pdfium_c.FPDF_PAGEOBJ_IMAGE], max_depth=5):
            l, b, r, t = obj.get_bounds()
            area = max(0.0, min(r, w) - max(l, 0)) * max(0.0, min(t, h) - max(b, 0)) / max(w * h, 1.0)
            imgs.append(((round(l), round(b), round(r), round(t)), area))
        for key in {k for k, _ in imgs}:
            bbox_pages[key] = bbox_pages.get(key, 0) + 1
        n_paths = sum(1 for _ in page.get_objects(filter=[pdfium_c.FPDF_PAGEOBJ_PATH], max_depth=5))
        pages.append((text, imgs, n_paths, (w, h)))

    units: list[Unit] = []
    images: dict[str, bytes] = {}
    for i, (text, imgs, n_paths, (w, h)) in enumerate(pages):
        own_area = sum(a for k, a in imgs if n < 3 or bbox_pages[k] / n < REPEATED_IMAGE_SHARE)
        lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
        share, short_count = _short_line_share(lines)
        reasons = []
        if len(text) < MIN_TEXT_CHARS:
            reasons.append("little_text")
        if own_area >= MIN_OWN_IMAGE_AREA:
            reasons.append("image")
        if n_paths >= MIN_PATHS:
            reasons.append("drawing")
        if share >= SHORT_LINE_SHARE and short_count >= SHORT_LINE_MIN:
            reasons.append("broken_math")
        unit = Unit(label=f"p.{i + 1}", text=text, reasons=reasons)
        # 文字の無い白紙のページは読まない
        if reasons and (text or imgs or n_paths):
            key = f"p{i + 1}"
            page = pdf[i]
            img = page.render(scale=PDF_RENDER_LONG_SIDE / max(w, h)).to_pil()
            images[key] = prepare_image(img, PDF_RENDER_LONG_SIDE)
            unit.images = [key]
            unit.replace = True
        units.append(unit)
    return Extraction(kind="pdf", units=units, images=images, page_count=n)


def _extract_docx(path: Path) -> Extraction:
    import docx
    from docx.table import Table
    from docx.text.paragraph import Paragraph

    _check_zip(path, "word/document.xml")
    try:
        d = docx.Document(str(path))
    except Exception:
        raise FileError("FILE_CORRUPT", "The Word file could not be opened.")

    units: list[Unit] = []
    images: dict[str, bytes] = {}
    key_by_hash: dict[str, str] = {}
    buf: list[str] = []

    def flush() -> None:
        if buf:
            units.append(Unit(text="\n\n".join(buf)))
            buf.clear()

    for child in d.element.body.iterchildren():
        tag = child.tag.split("}")[-1]
        if tag == "p":
            p = Paragraph(child, d)
            text = p.text.strip()
            style = ((p.style.name if p.style is not None else "") or "").lower()
            if text:
                if style.startswith("heading") or style == "title":
                    level = int(style.split()[-1]) if style.split()[-1].isdigit() else 1
                    text = "#" * min(level, 6) + " " + text
                buf.append(text)
            for rid in child.xpath(".//a:blip/@r:embed"):
                part = d.part.related_parts.get(rid)
                blob = getattr(part, "blob", None)
                if not blob or not _embed_ok(blob):
                    continue
                digest = hashlib.sha1(blob).hexdigest()
                if digest in key_by_hash:
                    continue  # 同じ画像を2回読まない(2回目は書き起こしも入れない)
                key = f"i{len(key_by_hash) + 1}"
                key_by_hash[digest] = key
                try:
                    images[key] = prepare_image(_open_image(blob))
                except Exception:
                    continue
                flush()
                units.append(Unit(images=[key]))
        elif tag == "tbl":
            t = Table(child, d)
            rows = ["| " + " | ".join(c.text.strip().replace("\n", " ") for c in r.cells) + " |" for r in t.rows]
            if rows:
                buf.append("\n".join(rows))
    flush()
    return Extraction(kind="docx", units=units, images=images)


def _extract_pptx(path: Path) -> Extraction:
    from pptx import Presentation
    from pptx.enum.shapes import MSO_SHAPE_TYPE

    _check_zip(path, "ppt/presentation.xml")
    try:
        prs = Presentation(str(path))
    except Exception:
        raise FileError("FILE_CORRUPT", "The PowerPoint file could not be opened.")
    slides = list(prs.slides)
    if len(slides) > MAX_PAGES:
        raise FileError("TOO_MANY_PAGES", f"The file has more than {MAX_PAGES} slides.", {"max_pages": MAX_PAGES})

    def walk(shapes):
        for sh in shapes:
            if sh.shape_type == MSO_SHAPE_TYPE.GROUP:
                yield from walk(sh.shapes)
            else:
                yield sh

    per_slide: list[tuple[list[str], list[tuple[str, bytes]], str]] = []
    slides_with: dict[str, int] = {}
    for s in slides:
        texts, pics = [], []
        for sh in walk(s.shapes):
            if sh.has_text_frame and sh.text_frame.text.strip():
                texts.append(sh.text_frame.text.strip())
            if getattr(sh, "has_table", False) and sh.has_table:
                texts.append("\n".join("| " + " | ".join(c.text.strip() for c in r.cells) + " |" for r in sh.table.rows))
            if sh.shape_type == MSO_SHAPE_TYPE.PICTURE:
                try:
                    blob = sh.image.blob
                except Exception:
                    continue
                if _embed_ok(blob):
                    pics.append((hashlib.sha1(blob).hexdigest(), blob))
        for digest in {d for d, _ in pics}:
            slides_with[digest] = slides_with.get(digest, 0) + 1
        notes = ""
        if s.has_notes_slide and s.notes_slide.notes_text_frame is not None:
            notes = s.notes_slide.notes_text_frame.text.strip()
        per_slide.append((texts, pics, notes))

    n = len(slides)
    units: list[Unit] = []
    images: dict[str, bytes] = {}
    key_by_hash: dict[str, str] = {}
    for i, (texts, pics, notes) in enumerate(per_slide, start=1):
        keys = []
        for digest, blob in pics:
            # 多くのスライドに同じ画像があるのはロゴ・飾り(読まない)
            if n >= 3 and slides_with[digest] / n >= REPEATED_IMAGE_SHARE:
                continue
            if digest not in key_by_hash:
                key = f"s{i}_{len(keys) + 1}"
                try:
                    images[key] = prepare_image(_open_image(blob))
                except Exception:
                    continue
                key_by_hash[digest] = key
            elif key_by_hash[digest] in keys:
                continue
            keys.append(key_by_hash[digest])
        units.append(Unit(label=f"slide {i}", text="\n\n".join(texts), images=keys,
                          tail=f"[Speaker notes]\n{notes}" if notes else ""))
    return Extraction(kind="pptx", units=units, images=images, page_count=n)


def _extract_image(path: Path) -> Extraction:
    try:
        img = _open_image(path.read_bytes())
    except Exception:
        raise FileError("FILE_CORRUPT", "The image could not be opened.")
    return Extraction(kind="image", units=[Unit(images=["main"], replace=True)], images={"main": prepare_image(img)})


_EXTRACTORS: dict[str, Callable[[Path], Extraction]] = {
    "pdf": _extract_pdf, "docx": _extract_docx, "pptx": _extract_pptx, "image": _extract_image,
}


def extract_file(kind: str, path: Path) -> Extraction:
    """
    LLMを使わずに中身を取り出す(同期。呼び出し側がスレッドで動かす)。取り出せない・上限を超えるときは
    FileError。画像として読む数が多すぎるときもここで止める(送る前に理由を見せるため)。
    """
    Image.MAX_IMAGE_PIXELS = MAX_IMAGE_PIXELS
    try:
        ex = _EXTRACTORS[kind](path)
    except FileError:
        raise
    except Image.DecompressionBombError:
        raise FileError("FILE_TOO_COMPLEX", "An image in the file is too large.")
    except Exception as e:
        print(f"⚠️ [chat_files] failed to extract {kind}: {type(e).__name__}: {e}")
        raise FileError("FILE_CORRUPT", "The file could not be read.")
    if ex.vision_count > MAX_VISION_IMAGES:
        raise FileError("TOO_MANY_IMAGES", f"More than {MAX_VISION_IMAGES} pages or images would need to be read as images.",
                        {"max_images": MAX_VISION_IMAGES, "count": ex.vision_count})
    if not ex.vision_count and not ex.text_chars:
        raise FileError("FILE_EMPTY", "No text or images were found in the file.")
    return ex


# =========================================================
# 👁️ 書き起こし(送信後のターンの中)
# =========================================================

@dataclass
class TranscribeResult:
    content: str = ""
    blocked: bool = False
    # 画像1枚の資料のときだけ
    title: str = ""
    summary: str = ""
    forbids_ai_code: bool = False
    calls: int = 0
    input_tokens: int = 0
    output_tokens: int = 0
    failed_images: list[str] = field(default_factory=list)

    def usage_json(self) -> dict:
        return {"model": VISION_MODEL, "calls": self.calls, "input_tokens": self.input_tokens,
                "output_tokens": self.output_tokens, "failed_images": self.failed_images}


def _vision_options(standalone: bool) -> LLMOptions:
    schema = STANDALONE_SCHEMA if standalone else VISION_SCHEMA
    return LLMOptions(output_type="json", json_schema=schema, temperature=1.0,
                      max_completion_tokens=VISION_MAX_TOKENS, reasoning_effort="none")


def _looks_like_safety_block(error: Exception) -> bool:
    text = str(error).lower()
    return any(k in text for k in ("prohibited_content", "blockreason", "block_reason", "safety", "content_filter"))


async def _read_image(llm: UnifiedLLM, jpeg: bytes, hint: str, standalone: bool, result: TranscribeResult,
                      limiter: Optional[asyncio.Semaphore]) -> Optional[dict]:
    """
    1枚を読む。断ったらresult.blocked。読めなかったら(2回試して)None。審査の結果だけは読めないと困るので、
    読めなかった画像の分は本文に入れない(何も見ていないものを回答役に渡さない)。
    """
    user = f"<extracted_text>\n{hint}\n</extracted_text>" if hint else ""
    if standalone:
        user = "This is a standalone image: also give title, summary, and forbids_ai_code."
    messages = [Message(role="system", content=_load_prompt("chat_attachment_vision_prompt.txt")),
                Message(role="user", content=user, images=[jpeg])]
    for _attempt in range(2):
        if result.blocked:
            return None
        try:
            if limiter is None:
                res = await llm.generate(VISION_MODEL, messages, _vision_options(standalone))
            else:
                async with limiter:
                    res = await llm.generate(VISION_MODEL, messages, _vision_options(standalone))
        except Exception as e:
            if _looks_like_safety_block(e):
                result.blocked = True
                return None
            print(f"⚠️ [chat_files] vision call failed: {e}")
            continue
        result.calls += 1
        result.input_tokens += res.input_tokens
        result.output_tokens += res.output_tokens
        if res.finish_reason == "content_filter":
            result.blocked = True
            return None
        out = res.output_json
        if isinstance(out, dict) and out.get("verdict") in ("ok", "blocked"):
            if out["verdict"] == "blocked":
                result.blocked = True
                return None
            return out
    return None


def _visual_block(out: dict) -> str:
    if out.get("kind") == "decorative":
        return ""
    parts = [str(out.get("text") or "").strip()]
    visuals = str(out.get("visuals") or "").strip()
    if visuals:
        parts.append(f"[Visual: {visuals}]")
    return "\n\n".join(p for p in parts if p)


def assemble(units: list[Unit], transcripts: dict[str, str]) -> str:
    """単位を本文にする。PDFは [p.N]、pptxは [slide N] を各単位の先頭に置く(目次の節の区切りの候補になる)。"""
    blocks = []
    for u in units:
        parts: list[str] = []
        read = [transcripts[k] for k in u.images if transcripts.get(k)]
        if u.replace and u.images:
            # 書き起こせなかったページは文字層で代える
            parts.extend(read if read else [u.text])
        else:
            parts.append(u.text)
            if u.label is None:
                parts.extend(f"[Image]\n{t}\n[/Image]" for t in read)
            else:
                parts.extend(read)
        if u.tail:
            parts.append(u.tail)
        body = "\n\n".join(p.strip() for p in parts if p and p.strip())
        if u.label:
            blocks.append(f"[{u.label}]\n{body}" if body else f"[{u.label}]")
        elif body:
            blocks.append(body)
    return "\n\n".join(blocks)


async def transcribe_file(
    llm: UnifiedLLM,
    kind: str,
    units: list[Unit],
    load_image: Callable[[str], Awaitable[bytes]],
    limiter: Optional[asyncio.Semaphore] = None,
) -> TranscribeResult:
    """
    画像として読む部分をすべて(並列に)書き起こし、本文を組み立てる。どれか1枚でも断ったら、そのファイルを断る。
    画像1枚の資料は、名前・要約・AIでのコード禁止もここで作る(目次・要約役を通さない)。
    """
    result = TranscribeResult()
    standalone = kind == "image"
    hints = {k: (u.text if u.replace else "") for u in units for k in u.images}
    keys = list(hints)

    async def one(key: str) -> tuple[str, Optional[dict]]:
        jpeg = await load_image(key)
        return key, await _read_image(llm, jpeg, hints[key], standalone, result, limiter)

    outs = dict(await asyncio.gather(*[one(k) for k in keys]))
    if result.blocked:
        return result
    transcripts: dict[str, str] = {}
    for k in keys:
        out = outs.get(k)
        if out is None:
            result.failed_images.append(k)
            continue
        transcripts[k] = _visual_block(out)
        if standalone:
            result.title = str(out.get("title") or "").strip()[:60]
            result.summary = str(out.get("summary") or "").strip()[:800]
            result.forbids_ai_code = out.get("forbids_ai_code") is True
    if standalone and not transcripts:
        raise RuntimeError("the image could not be read")
    result.content = assemble(units, transcripts)
    return result


# =========================================================
# 🗂️ draftの行
# =========================================================

def extraction_json(ex: Extraction, image_keys: dict[str, str]) -> dict:
    """draftの行に保存する形(画像はR2のキー)。"""
    return {
        "units": [u.to_json() for u in ex.units],
        "images": image_keys,
        "vision_count": ex.vision_count,
        "text_chars": ex.text_chars,
        "estimated_chars": ex.estimated_chars,
        "estimated_tokens": ex.estimated_tokens(),
        "warnings": ex.warnings,
    }


def units_from_json(raw: dict) -> list[Unit]:
    return [Unit.from_json(u) for u in (raw or {}).get("units") or [] if isinstance(u, dict)]


def draft_info(row: dict) -> dict:
    """画面に返す、送る前に分かること(ページ数・文字数・画像として読む数・概算のトークン数)。"""
    ex = row.get("extraction") or {}
    vision = int(ex.get("vision_count") or 0)
    est_chars = int(ex.get("estimated_chars") or 0)
    pages = [u.get("label") for u in ex.get("units") or [] if u.get("replace") and u.get("images")]
    return {
        "id": row["id"],
        "kind": row.get("kind"),
        "file_name": row.get("file_name"),
        "file_size": row.get("file_size"),
        "page_count": row.get("page_count"),
        "text_chars": int(ex.get("text_chars") or 0),
        "estimated_chars": est_chars,
        "vision_count": vision,
        "vision_pages": [p for p in pages if p][:MAX_VISION_IMAGES],
        "estimated_tokens": int(ex.get("estimated_tokens") or 0),
    }


_SAFE_NAME_RE = re.compile(r"[^\w.\- ()\[\]（）ぁ-んァ-ヶ一-龠ー]+")


def clean_file_name(name: str) -> str:
    """表示とContent-Dispositionに使う名前(パスの区切りや制御文字を除く)。"""
    base = Path((name or "").replace("\\", "/")).name.strip()
    base = _SAFE_NAME_RE.sub("_", base)[:120]
    return base or "file"
