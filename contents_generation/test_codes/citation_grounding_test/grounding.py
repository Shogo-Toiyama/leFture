"""
出典の「根拠の箇所」を探すための文字列処理(LLMもAPIも使わない部分)。

- normalize_with_map: 比較用の正規化(NFKC・大文字小文字・空白・句読点/記号/結合文字を除く)と、
  正規化後の各文字が元の文字列のどこだったかの対応表。言語ごとの表は持たない
  (Unicodeの分類だけで13言語の句読点・引用符の揺れを吸収する)。
- split_sentences: 出典本文を文に分ける(位置つき)。
- locate_quote: LLMが書いた抜粋(方式B)を原文から探す。完全一致 → 正規化一致 → 部分一致から広げる。
- cited_claims: 回答の [n] / [Wn] 1か所ごとに、それが付いている文(主張)を取り出す。

本番に入れるときは app/services/ に移し、chat_screen.locate_selection と正規化を共通にする想定。
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from typing import Optional

# =========================================================
# 正規化
# =========================================================


def _keep(ch: str) -> bool:
    if ch.isspace():
        return False
    cat = unicodedata.category(ch)
    # P*: 句読点・括弧・引用符(「」« » „ “ ، ؟ । など) / S*: 記号(Markdownの*や#も) / Mn: 結合文字(アラビア語の母音記号など)
    return not (cat[0] in "PS" or cat == "Mn")


def normalize_with_map(text: str) -> tuple[str, list[int]]:
    """比較用の文字列と、その各文字の元の位置。NFKCで1文字が複数文字に展開されても元の位置を保つ。"""
    chars: list[str] = []
    positions: list[int] = []
    for i, ch in enumerate(text):
        for c in unicodedata.normalize("NFKC", ch).casefold():
            if _keep(c):
                chars.append(c)
                positions.append(i)
    return "".join(chars), positions


def normalize(text: str) -> str:
    return normalize_with_map(text)[0]


# =========================================================
# 文の分割
# =========================================================

# 文末: 。！？!?؟।(と全角) / 「.」は後ろが空白か終わりのときだけ(3.5 や e.g. の途中で切らない)
_SENT_END_RE = re.compile(r"[。！？!?؟।]+[」』）)\]\"'”’]*|\.(?=\s|$)[\"'”’)\]]*|\n+")
MIN_SENTENCE_CHARS = 12


@dataclass
class Sentence:
    start: int
    end: int
    text: str


def split_sentences(text: str) -> list[Sentence]:
    """文に分ける。短すぎる断片(見出し・「Keywords:」等)は次の文につなげる。"""
    raw: list[tuple[int, int]] = []
    pos = 0
    for m in _SENT_END_RE.finditer(text):
        end = m.end()
        if text[pos:end].strip():
            raw.append((pos, end))
        pos = end
    if text[pos:].strip():
        raw.append((pos, len(text)))

    out: list[Sentence] = []
    carry: Optional[int] = None
    for a, b in raw:
        start = carry if carry is not None else a
        if len(normalize(text[start:b])) < MIN_SENTENCE_CHARS and (a, b) != raw[-1]:
            carry = start
            continue
        carry = None
        s, e = _trim(text, start, b)
        if e > s:
            out.append(Sentence(s, e, text[s:e]))
    return out


def _trim(text: str, a: int, b: int) -> tuple[int, int]:
    while a < b and text[a].isspace():
        a += 1
    while b > a and text[b - 1].isspace():
        b -= 1
    return a, b


def sentence_window(sentences: list[Sentence], start: int, end: int, extra: int = 1) -> tuple[int, int]:
    """[start, end)を含む文の範囲に、前後extra文を足した(開始, 終了)。表示の文脈用。"""
    idx = [i for i, s in enumerate(sentences) if s.end > start and s.start < end]
    if not idx:
        return start, end
    i0 = max(0, idx[0] - extra)
    i1 = min(len(sentences) - 1, idx[-1] + extra)
    return sentences[i0].start, sentences[i1].end


# =========================================================
# 方式B: 抜粋を原文から探す
# =========================================================

ANCHOR_CHARS = 12
# 部分一致から広げた結果、抜粋(正規化後)のこの割合以上が原文と一致していれば「見つかった」とする
MIN_EXPANDED_RATIO = 0.6


@dataclass
class Located:
    start: int
    end: int
    step: str  # exact / normalized / anchor
    matched_ratio: float = 1.0


def locate_quote(source: str, quote: str) -> Optional[Located]:
    quote = (quote or "").strip()
    if not quote:
        return None
    i = source.find(quote)
    if i >= 0:
        return Located(i, i + len(quote), "exact")

    hay, pos = normalize_with_map(source)
    needle = normalize(quote)
    if len(needle) < 4:
        return None
    j = hay.find(needle)
    if j >= 0:
        return Located(pos[j], pos[j + len(needle) - 1] + 1, "normalized")

    # 部分一致: 抜粋の中のいくつかの位置から短い断片(アンカー)を取り、原文で見つかったら
    # 前後に一致が続く限り広げる。一番長く一致したものを採る。
    best: Optional[tuple[int, int]] = None  # hay上の(開始, 終了)
    best_len = 0
    if len(needle) >= ANCHOR_CHARS:
        for frac in (0.5, 0.25, 0.75, 0.0, 1.0):
            k = min(int((len(needle) - ANCHOR_CHARS) * frac), len(needle) - ANCHOR_CHARS)
            anchor = needle[k:k + ANCHOR_CHARS]
            h = hay.find(anchor)
            while h >= 0:
                a_h, a_n = h, k
                while a_h > 0 and a_n > 0 and hay[a_h - 1] == needle[a_n - 1]:
                    a_h -= 1
                    a_n -= 1
                b_h, b_n = h + ANCHOR_CHARS, k + ANCHOR_CHARS
                while b_h < len(hay) and b_n < len(needle) and hay[b_h] == needle[b_n]:
                    b_h += 1
                    b_n += 1
                if b_h - a_h > best_len:
                    best, best_len = (a_h, b_h), b_h - a_h
                h = hay.find(anchor, h + 1)
    if best and best_len / len(needle) >= MIN_EXPANDED_RATIO:
        return Located(pos[best[0]], pos[best[1] - 1] + 1, "anchor", best_len / len(needle))
    return None


# =========================================================
# 回答の [n] ごとの主張
# =========================================================

_CODE_RE = re.compile(r"```[\s\S]*?(?:```|$)|`[^`\n]*`")
_MARK_RE = re.compile(r"(?<![A-Za-z0-9_])\[(W?\d{1,2})\](?!\()")
_MARKS_RUN_RE = re.compile(r"(?:\s*\[W?\d{1,2}\])+")
_CLAIM_BOUNDARY_RE = re.compile(r"[。！？!?؟।]|\.(?=\s)|\n")
_MD_RE = re.compile(r"\*\*|__|`|^#+\s*|^\s*(?:[-*+]|\d+\.)\s+", re.M)


@dataclass
class Claim:
    occurrence: int      # 本文中の何番目の印か(0始まり)
    ref: str             # "1" / "W2"
    ref_occurrence: int  # その番号の何回目か(0始まり)。方式Bの抜粋との対応に使う
    text: str            # 印が付いている文(Markdownと印を除いたもの)
    mark_pos: int


def _clean(text: str) -> str:
    return _MD_RE.sub("", _MARK_RE.sub("", text)).strip(" \t\n:：")


def cited_claims(answer: str) -> list[Claim]:
    """
    本文の [n] 1か所ごとに、それが支えている文を取り出す。印は文の直後(「…だ。[1]」)にも
    文末の直前(「…だ [1]。」)にも付くので、印の直前(他の印と空白を飛ばした位置)から
    1つ前の文の区切りまでを主張とする。短すぎれば(「つまり、[1]」)さらに前の文まで含める。
    コードの中の [n] は数えない。
    """
    masked = _CODE_RE.sub(lambda m: " " * len(m.group(0)), answer)
    claims: list[Claim] = []
    per_ref: dict[str, int] = {}
    for i, m in enumerate(_MARK_RE.finditer(masked)):
        ref = m.group(1)
        # 直前に続く他の印 [1][2] の [2] なら、[1] と同じ文を指す
        end = m.start()
        run = re.search(r"(?:\s*\[W?\d{1,2}\])+\s*$", masked[:end])
        if run:
            end = run.start()
        body_end = end
        while body_end > 0 and masked[body_end - 1] in " \t。.!?！？":
            body_end -= 1
        limit = body_end
        start = 0
        for _ in range(2):
            bounds = list(_CLAIM_BOUNDARY_RE.finditer(masked, 0, limit))
            start = bounds[-1].end() if bounds else 0
            if not bounds or len(normalize(_clean(answer[start:end]))) >= 10:
                break
            limit = bounds[-1].start()  # 短すぎる: 1つ前の文まで含める
        text = _clean(_MARKS_RUN_RE.sub("", answer[start:end]))
        claims.append(Claim(i, ref, per_ref.get(ref, 0), text, m.start()))
        per_ref[ref] = per_ref.get(ref, 0) + 1
    return claims
