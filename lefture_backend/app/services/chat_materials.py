# app/services/chat_materials.py
"""
回答役に渡す材料の形。docs/chatbot_context_and_retrieval_roadmap.md の 3-8 / 3-14。

材料は、検索で当たったチャンク(knowledge_chunks)だけでなく、探索役が開いた中身
(コースの講義一覧・講義・トピック・文字起こしの範囲)、今後はチャット・Webも加わる。
それらを1つの形(Material)にそろえ、回答役のプロンプト・出典の保存・SSEを全部これで扱う。

- 回答役には「直接関係あり」と「つながりの候補」(possible_link)を分けて渡す。
  つながりの候補は、具体的で意外性のある結びつき(AHA)を確信できるときだけ使う(3-4)。
- 材料の合計には上限を付ける(MATERIALS_MAX_CHARS)。直接関係ありを先に、深いもの
  (文字起こし → トピック → 講義 → 検索の断片 → コースの一覧)から入れる。
- 出典(citations)は、画面から該当ページへ飛べるよう、今までの形
  (source_type / source_id / lecture_id / metadata)を保つ。
"""

import re
from dataclasses import dataclass, field
from typing import Any, Optional

MATERIALS_MAX_CHARS = 12000
MATERIALS_MAX_ITEMS = 12
# 1つの材料の上限(ほかの材料が入る余地を残す)
MATERIAL_MAX_CHARS = 4000

# 深いもの・具体的なものほど先に入れる(同じ関係の中での順番)
PRIORITY = {
    "transcript": 0,
    "chat_turn": 0,
    "topic": 1,
    "chat_section": 1,
    "chunk": 2,
    "lecture": 3,
    "course": 4,
    "chat_thread": 4,
}


@dataclass
class Material:
    key: str
    kind: str  # course / lecture / topic / transcript / chunk
    label: str
    content: str
    relation: str = "direct"
    source_type: str = ""
    source_id: Optional[str] = None
    lecture_id: Optional[str] = None
    course_id: Optional[str] = None
    thread_id: Optional[str] = None
    chunk_id: Optional[str] = None
    similarity: Optional[float] = None
    metadata: dict = field(default_factory=dict)
    # 探索役に見せた呼び名(記録用)
    handle: Optional[str] = None

    def citation(self, n: int) -> dict:
        return {
            "n": n,
            "chunk_id": self.chunk_id,
            "source_type": self.source_type,
            "source_id": self.source_id,
            "lecture_id": self.lecture_id,
            "course_id": self.course_id,
            "thread_id": self.thread_id,
            "label": self.label,
            "similarity": self.similarity,
            "metadata": self.metadata,
            "relation": self.relation,
        }


def material_from_chunk(chunk: dict, relation: str = "direct", handle: Optional[str] = None) -> Material:
    """検索で当たったknowledge_chunksの行を材料に。contentの1行目「[コース / 講義 / 種類]」をラベルにする。"""
    content = (chunk.get("content") or "").strip()
    lines = content.splitlines()
    label = ""
    if lines and lines[0].startswith("[") and lines[0].endswith("]"):
        label = lines[0].strip("[]")
        content = "\n".join(lines[1:]).strip()
    return Material(
        key=f"chunk:{chunk.get('id')}",
        kind="chunk",
        label=label,
        content=content,
        relation=relation,
        source_type=chunk.get("source_type") or "",
        source_id=chunk.get("source_id"),
        lecture_id=chunk.get("lecture_id"),
        course_id=chunk.get("course_id"),
        chunk_id=chunk.get("id"),
        similarity=chunk.get("similarity"),
        metadata=chunk.get("metadata") or {},
        handle=handle,
    )


def select_materials(materials: list[Material]) -> list[Material]:
    """
    回答役に渡す材料を選ぶ。同じkeyは1つにまとめ(どれか1つでもdirectならdirect)、
    直接関係あり → つながりの候補、同じ関係の中では深いもの → 類似度の高いものの順。
    合計の文字数と件数の上限を超えたら、そこで止める(長い材料は切り詰める)。
    """
    merged: dict[str, Material] = {}
    for m in materials:
        cur = merged.get(m.key)
        if cur is None:
            merged[m.key] = m
            continue
        if m.relation == "direct":
            cur.relation = "direct"
        if (m.similarity or 0) > (cur.similarity or 0):
            cur.similarity = m.similarity

    ranked = sorted(
        merged.values(),
        key=lambda m: (m.relation != "direct", PRIORITY.get(m.kind, 9), -(m.similarity or 0)),
    )
    out: list[Material] = []
    used = 0
    for m in ranked:
        if len(out) >= MATERIALS_MAX_ITEMS:
            break
        room = MATERIALS_MAX_CHARS - used
        if room < 300:
            break
        limit = min(MATERIAL_MAX_CHARS, room)
        if len(m.content) > limit:
            m.content = m.content[:limit].rstrip() + " …"
        out.append(m)
        used += len(m.content) + len(m.label)
    return out


def format_sources_block(materials: list[Material]) -> str:
    """回答役に渡す出典一覧。番号は1始まりで本文中の[n]と対応し、関係ごとに見出しを分ける。"""
    direct = [(n, m) for n, m in enumerate(materials, start=1) if m.relation == "direct"]
    links = [(n, m) for n, m in enumerate(materials, start=1) if m.relation != "direct"]
    parts = []
    if direct:
        parts.append("Directly relevant to the question:")
        parts += [f"[{n}] {m.label}\n{m.content}" for n, m in direct]
    if links:
        parts.append("Possible links to the student's courses (use only for a striking, specific connection; otherwise ignore):")
        parts += [f"[{n}] {m.label}\n{m.content}" for n, m in links]
    return "\n\n".join(parts)


_CITATION_RE = re.compile(r"\[(\d{1,2})\]")


def extract_citations(answer_text: str, materials: list[Material]) -> list[dict]:
    """
    本文中で実際に使われた[n]だけを出典として残す。範囲外の番号(回答役が
    作ってしまった番号)は捨てる。
    """
    used: list[int] = []
    for m in _CITATION_RE.finditer(answer_text or ""):
        n = int(m.group(1))
        if 1 <= n <= len(materials) and n not in used:
            used.append(n)
    return [materials[n - 1].citation(n) for n in sorted(used)]


def sources_event(materials: list[Material]) -> list[dict[str, Any]]:
    """SSEのsourcesイベントの中身(回答を書き始める前に画面へ送る)。"""
    return [m.citation(n) for n, m in enumerate(materials, start=1)]
