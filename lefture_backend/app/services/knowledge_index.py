# app/services/knowledge_index.py
"""
横断チャットボット 段階0: knowledge_chunksへの汎用インデクサ。

設計(2026-09-27のセッションで合意した内容):
- DBトリガ(migration: 20261001010000_add_knowledge_chunks.sql)が
  対象テーブルへのINSERT/UPDATEのたびに knowledge_index_queue に
  (source_type, source_id) を積む。削除・ゴミ箱行き・復元はトリガが
  その場で完結させるので、ここには来ない。
- 埋め込み計算(外部API呼び出し)はこのモジュールでしか行わない。
  DBトリガの中では絶対に呼ばない。
- 何度呼んでも安全(冪等)。content_hashが一致していれば埋め込みAPIは
  呼ばず、付随列(course_id等)だけ同期する。
- 呼び出し元は2つ:
    1. patrol (main.py の PATROL_CHECKS、30分おき) — アプリでの
       直接編集分の取りこぼしを拾う。
    2. FINALIZE_JOB (task_runners.py) — 講義処理が完了した直後に
       その場で1回呼び、体感の遅延を無くす。
  どちらも同じ drain_knowledge_index_queue() を呼ぶだけで、
  ロジックの二重化はない。

まだ実装していないもの(段階0の範囲外):
- チャット履歴・プロフィールinsightのインデックス化(段階1/3で追加)
- 近似検索インデックス(HNSW等) — 1ユーザー数万件規模では不要と判断
  (project_overview / chatbot-rag-design メモリ参照)
"""

import asyncio
import hashlib
import json
import random
from dataclasses import dataclass, field
from typing import Any, Callable, Optional

import litellm

from app.core.supabase import get_supabase_client
from app.services.helpers.plan_features import DEEP_NOTES_SKIPPED_PLAN_LIMIT


# =========================================================
# ⚙️ 設定
# =========================================================

# 埋め込みモデルは1箇所にまとめておく。将来モデルを変える場合、
# ベクトル空間に互換性が無いため全件の再埋め込みが必要になる
# (contents_generation/scripts的な位置づけのバックフィルスクリプトを
# もう一度回す)。
KNOWLEDGE_EMBEDDING_MODEL = "gemini/gemini-embedding-2"
KNOWLEDGE_EMBEDDING_DIMENSIONS = 768

# チャンクの目標サイズ。厳密なトークン数ではなく「英語で1トークン≒4文字」
# の目安による概算(日本語はもっと短くなるが、安全側に倒して長めに割る
# 分には支障がない)。Embedding 2自体の上限は8192トークンなので、
# ここは検索の粒度を決めるためのパラメータであってモデル制約ではない。
MAX_CHUNK_CHARS = 3200
CHUNK_OVERLAP_CHARS = 300

# トランスクリプト専用のチャンク目標サイズ (約600〜700トークン、3〜4分間の講義発言)。
# 前後のロジックや説明の文脈を保てるよう3000文字とし、オーバーラップを1/10の300文字にする。
TRANSCRIPT_CHUNK_CHARS = 3000
TRANSCRIPT_CHUNK_OVERLAP_CHARS = 300

# 1往復のチャンクで、学生の発言・返答それぞれに使う最大文字数(3-14 ④)
CHAT_TURN_MAX_CHARS = 1500

# キューの1件が何度失敗したら諦めて'FAILED'に落とすか
MAX_QUEUE_ATTEMPTS = 5


@dataclass
class ChunkDraft:
    """
    1チャンク分の「これから書き込みたい内容」を表す中間データ。

    titleは「コース / 講義 / 種類: 見出し」のような文脈、bodyは本文。
    Embedding 2は検索される側の文書を "title: ... | text: ..." の形式で
    埋め込むことを推奨している(クエリ側は "task: search result | query: ..."
    で、両者は非対称)。そのため2つを分けて持つ。
    """
    chunk_index: int
    title: str
    body: str
    user_id: str
    course_id: Optional[str] = None
    lecture_id: Optional[str] = None
    metadata: dict = field(default_factory=dict)

    @property
    def content(self) -> str:
        """knowledge_chunks.contentに保存し、チャットのLLMにも渡す表示用テキスト。"""
        return f"[{self.title}]\n{self.body}".strip() if self.title else self.body.strip()

    @property
    def embedding_input(self) -> str:
        """埋め込みAPIに実際に送る文字列(公式推奨の文書側フォーマット)。"""
        return f"title: {self.title or 'none'} | text: {self.body}"


def assemble_lecture_transcript(admin_client, lecture_id: str, user_id: Optional[str] = None) -> list[dict]:
    """
    講義の文字起こしを文の並び([{"sid": "s000001", "text": ...}, ...])に取得する。
    パイプライン完了済みの成果物として R2 の pipeline_logs/role_classification.json
    (無ければ transcript_assembled.json) から取得する。
    R2 に成果物が存在しない場合は、講義処理中か異常とみなして安全にスキップ(空配列)する。
    チャットの探索役が文字起こしの範囲を開くときにも使う。
    """
    if not lecture_id:
        return []

    # 1. user_id を特定
    if not user_id:
        try:
            lec_res = admin_client.table("lectures").select("user_id").eq("id", lecture_id).maybe_single().execute()
            if lec_res and lec_res.data:
                user_id = lec_res.data.get("user_id")
        except Exception:
            pass

    if not user_id:
        print(f"⚠️ [knowledge_index] Could not resolve user_id for lecture {lecture_id}, skipping transcript.")
        return []

    # 2. R2 からの取得 (role_classification -> transcript_assembled)
    try:
        from app.core.r2_storage import R2StorageService
        r2 = R2StorageService()
        for candidate in ("role_classification", "transcript_assembled"):
            storage_path = f"{user_id}/{lecture_id}/pipeline_logs/{candidate}.json"
            try:
                binary = r2.download_binary(storage_path)
                data = json.loads(binary)
                if isinstance(data, list) and len(data) > 0 and isinstance(data[0], dict) and "sid" in data[0]:
                    return data
            except Exception:
                continue
    except Exception as e:
        print(f"⚠️ [knowledge_index] R2 storage access failed for lecture {lecture_id}: {e}")
        return []

    print(f"ℹ️ [knowledge_index] Transcript for lecture {lecture_id} not found in R2. Skipping transcript indexing.")
    return []


class _ContextCache:
    """
    1回のdrain呼び出し内で使い回す軽量キャッシュ。
    同じ講義の複数チャンク(Review Card 4枚など)を処理するときに
    lectures/coursesへ毎回問い合わせるのを避ける。
    """
    def __init__(self, admin_client):
        self._client = admin_client
        self._lectures: dict[str, dict] = {}
        self._courses: dict[str, Optional[str]] = {}
        self._transcripts: dict[str, list[dict]] = {}

    def lecture(self, lecture_id: Optional[str]) -> dict:
        if not lecture_id:
            return {"course_id": None, "course_title": None, "lecture_title": None, "user_id": None}
        if lecture_id not in self._lectures:
            res = self._client.table("lectures").select(
                "id, course_id, title, title_generated, user_id"
            ).eq("id", lecture_id).maybe_single().execute()
            row = (res.data if res else None) or {}
            self._lectures[lecture_id] = {
                "course_id": row.get("course_id"),
                "course_title": self.course_title(row.get("course_id")),
                "lecture_title": (row.get("title") or row.get("title_generated") or "").strip(),
                "user_id": row.get("user_id"),
            }
        return self._lectures[lecture_id]

    def course_title(self, course_id: Optional[str]) -> Optional[str]:
        if not course_id:
            return None
        if course_id not in self._courses:
            res = self._client.table("courses").select("course_title") \
                .eq("id", course_id).maybe_single().execute()
            self._courses[course_id] = (res.data or {}).get("course_title") if res else None
        return self._courses[course_id]

    def topic_title(self, lecture_id: Optional[str], topic_number: Optional[int]) -> Optional[str]:
        if lecture_id is None or topic_number is None:
            return None
        res = self._client.table("lecture_topics").select("topic_title") \
            .eq("lecture_id", lecture_id).eq("index", topic_number).maybe_single().execute()
        return (res.data or {}).get("topic_title") if res else None

    def assembled_transcript(self, lecture_id: str) -> list[dict]:
        if lecture_id not in self._transcripts:
            lec = self.lecture(lecture_id)
            self._transcripts[lecture_id] = assemble_lecture_transcript(
                self._client, lecture_id, user_id=lec.get("user_id")
            )
        return self._transcripts[lecture_id]


# =========================================================
# ✂️ テキスト分割ヘルパー
# =========================================================

def _split_markdown_sections(md: str) -> list[str]:
    """Deep Notes用: `## `見出しで区切り、長すぎる節はさらに文字数で割る。"""
    lines = (md or "").splitlines()
    sections: list[str] = []
    current: list[str] = []
    for line in lines:
        if line.strip().startswith("## ") and current:
            sections.append("\n".join(current).strip())
            current = [line]
        else:
            current.append(line)
    if current:
        sections.append("\n".join(current).strip())
    if not sections:
        sections = [(md or "").strip()]

    out: list[str] = []
    for sec in sections:
        out.extend(_split_text_windows(sec, MAX_CHUNK_CHARS, CHUNK_OVERLAP_CHARS))
    return [s for s in out if s.strip()]


def _text_window_spans(length: int, max_chars: int, overlap: int) -> list[tuple[int, int]]:
    """長さlengthの文字列を、重なりを持たせて等間隔に割ったときの各窓の(開始, 終了)。"""
    if length <= 0:
        return []
    if length <= max_chars:
        return [(0, length)]
    spans = []
    start = 0
    while start < length:
        end = min(start + max_chars, length)
        spans.append((start, end))
        if end == length:
            break
        start = end - overlap
    return spans


def _split_text_windows(text: str, max_chars: int, overlap: int) -> list[str]:
    """トランスクリプト用: 見出しを持たない長文を、重なりを持たせて等間隔に割る。"""
    text = (text or "").strip()
    return [text[a:b] for a, b in _text_window_spans(len(text), max_chars, overlap)]


def _render_card_content(blocks: Any) -> str:
    """review_cards.card_content(jsonb配列)を検索用の平文に変換する。"""
    if not isinstance(blocks, list):
        return ""
    lines = []
    for b in blocks:
        if not isinstance(b, dict):
            continue
        t = b.get("type")
        if t in ("paragraph", "quote"):
            lines.append(b.get("text") or "")
        elif t == "callout":
            lines.append(f"[{b.get('alert_type', 'info')}] {b.get('text') or ''}")
        elif t == "code":
            lines.append(b.get("code_string") or "")
        elif t == "list":
            for item in (b.get("items") or []):
                lines.append(f"- {item}")
    return "\n".join(l for l in lines if l)


def _header(cache: _ContextCache, lecture_id: Optional[str], extra: str = "") -> str:
    """ChunkDraft.titleに入れる「コース / 講義 / 種類」の文脈文字列。"""
    lec = cache.lecture(lecture_id)
    parts = [lec.get("course_title") or "", lec.get("lecture_title") or "", extra]
    return " / ".join(p for p in parts if p)


# =========================================================
# 🧱 source_type ごとのビルダー
#
# 各ビルダーは (admin_client, source_id, cache) -> list[ChunkDraft] を
# 満たす同期関数。元の行がもう存在しない/ゴミ箱にある/内容が空、の
# いずれかなら空リストを返す(=そのsourceのチャンクは全て消える)。
# =========================================================

def _build_review_card(admin_client, source_id: str, cache: _ContextCache) -> list[ChunkDraft]:
    res = admin_client.table("review_cards").select(
        "id, user_id, lecture_id, topic_number, title, hero_emoji, card_type, card_content, deleted_at"
    ).eq("id", source_id).maybe_single().execute()
    row = res.data if res else None
    if not row or row.get("deleted_at"):
        return []

    body = _render_card_content(row.get("card_content"))
    if not body.strip():
        return []

    lec = cache.lecture(row.get("lecture_id"))

    return [ChunkDraft(
        chunk_index=0,
        title=_header(cache, row.get("lecture_id"), f"Review Card: {row.get('title') or ''}"),
        body=body,
        user_id=row["user_id"],
        course_id=lec.get("course_id"),
        lecture_id=row.get("lecture_id"),
        metadata={"title": row.get("title"), "card_type": row.get("card_type")},
    )]


def _build_deep_note(admin_client, source_id: str, cache: _ContextCache) -> list[ChunkDraft]:
    res = admin_client.table("deep_notes").select(
        "id, user_id, lecture_id, topic_number, note_contents, deleted_at"
    ).eq("id", source_id).maybe_single().execute()
    row = res.data if res else None
    if not row or row.get("deleted_at"):
        return []

    contents = row.get("note_contents") or ""
    if not contents.strip() or contents == DEEP_NOTES_SKIPPED_PLAN_LIMIT:
        return []

    lec = cache.lecture(row.get("lecture_id"))
    topic_title = cache.topic_title(row.get("lecture_id"), row.get("topic_number"))
    title = _header(cache, row.get("lecture_id"), f"Deep Note: {topic_title or ''}")

    sections = _split_markdown_sections(contents)
    return [
        ChunkDraft(
            chunk_index=idx,
            title=title,
            body=section,
            user_id=row["user_id"],
            course_id=lec.get("course_id"),
            lecture_id=row.get("lecture_id"),
            metadata={"topic_number": row.get("topic_number")},
        )
        for idx, section in enumerate(sections)
    ]


def _build_keyword(admin_client, source_id: str, cache: _ContextCache) -> list[ChunkDraft]:
    res = admin_client.table("keywords").select(
        "id, user_id, lecture_id, topic_number, keyword, definition, deleted_at"
    ).eq("id", source_id).maybe_single().execute()
    row = res.data if res else None
    if not row or row.get("deleted_at"):
        return []
    if not (row.get("keyword") or "").strip():
        return []

    lec = cache.lecture(row.get("lecture_id"))
    return [ChunkDraft(
        chunk_index=0,
        title=_header(cache, row.get("lecture_id"), "Keyword"),
        body=f"{row.get('keyword')}: {row.get('definition') or ''}".strip(),
        user_id=row["user_id"],
        course_id=lec.get("course_id"),
        lecture_id=row.get("lecture_id"),
        metadata={"keyword": row.get("keyword")},
    )]


def _build_announcement(admin_client, source_id: str, cache: _ContextCache) -> list[ChunkDraft]:
    res = admin_client.table("announcements").select(
        "id, user_id, lecture_id, type, title, description, location, deleted_at"
    ).eq("id", source_id).maybe_single().execute()
    row = res.data if res else None
    if not row or row.get("deleted_at"):
        return []

    parts = [row.get("title") or "", row.get("description") or ""]
    if row.get("location"):
        parts.append(f"Location: {row['location']}")
    body = " / ".join(p for p in parts if p)
    if not body.strip():
        return []

    lec = cache.lecture(row.get("lecture_id"))
    return [ChunkDraft(
        chunk_index=0,
        title=_header(cache, row.get("lecture_id"), f"Announcement ({row.get('type') or ''})"),
        body=body,
        user_id=row["user_id"],
        course_id=lec.get("course_id"),
        lecture_id=row.get("lecture_id"),
        metadata={"type": row.get("type")},
    )]


def _build_fun_fact(admin_client, source_id: str, cache: _ContextCache) -> list[ChunkDraft]:
    res = admin_client.table("fun_facts").select(
        "id, user_id, lecture_id, title, hook, body, deleted_at"
    ).eq("id", source_id).maybe_single().execute()
    row = res.data if res else None
    if not row or row.get("deleted_at"):
        return []

    lec = cache.lecture(row.get("lecture_id"))
    body = f"{row.get('hook') or ''}\n{row.get('body') or ''}".strip()
    if not body:
        return []

    return [ChunkDraft(
        chunk_index=0,
        title=_header(cache, row.get("lecture_id"), f"Fun Fact: {row.get('title') or ''}"),
        body=body,
        user_id=row["user_id"],
        course_id=lec.get("course_id"),
        lecture_id=row.get("lecture_id"),
        metadata={"title": row.get("title")},
    )]


def _build_lecture_summary(admin_client, source_id: str, cache: _ContextCache) -> list[ChunkDraft]:
    res = admin_client.table("lectures").select(
        "id, user_id, course_id, title, title_generated, summary, lecture_datetime, deleted_at"
    ).eq("id", source_id).maybe_single().execute()
    row = res.data if res else None
    if not row or row.get("deleted_at"):
        return []
    if not (row.get("summary") or "").strip():
        return []

    course_title = cache.course_title(row.get("course_id"))
    title = (row.get("title") or row.get("title_generated") or "").strip()
    chunk_title = " / ".join(p for p in [course_title or "", title, "Lecture Summary"] if p)

    return [ChunkDraft(
        chunk_index=0,
        title=chunk_title,
        body=row["summary"].strip(),
        user_id=row["user_id"],
        course_id=row.get("course_id"),
        lecture_id=row["id"],
        metadata={"title": title, "lecture_datetime": row.get("lecture_datetime")},
    )]


def _build_topic_summary(admin_client, source_id: str, cache: _ContextCache) -> list[ChunkDraft]:
    res = admin_client.table("lecture_topics").select(
        "id, user_id, lecture_id, topic_title, topic_type, summary, deleted_at"
    ).eq("id", source_id).maybe_single().execute()
    row = res.data if res else None
    if not row or row.get("deleted_at"):
        return []
    if not (row.get("summary") or "").strip():
        return []

    lec = cache.lecture(row.get("lecture_id"))
    return [ChunkDraft(
        chunk_index=0,
        title=_header(cache, row.get("lecture_id"), f"Topic: {row.get('topic_title') or ''}"),
        body=row["summary"].strip(),
        user_id=row["user_id"],
        course_id=lec.get("course_id"),
        lecture_id=row.get("lecture_id"),
        metadata={"topic_title": row.get("topic_title"), "topic_type": row.get("topic_type")},
    )]


def _build_transcript_topic(admin_client, source_id: str, cache: _ContextCache) -> list[ChunkDraft]:
    res = admin_client.table("lecture_topics").select(
        "id, user_id, lecture_id, topic_title, topic_type, start_sid, end_sid, deleted_at"
    ).eq("id", source_id).maybe_single().execute()
    row = res.data if res else None
    if not row or row.get("deleted_at"):
        return []
    # LOGISTICS(事務連絡)トピックは既にannouncementとして別途拾われるため、
    # トランスクリプト本文としての二重インデックスはACADEMICのみに絞る。
    if row.get("topic_type") != "ACADEMIC":
        return []

    from app.services.helpers.helpers import _sid_to_int
    start_n, end_n = _sid_to_int(row.get("start_sid")), _sid_to_int(row.get("end_sid"))
    if start_n is None or end_n is None:
        return []

    lecture_id = row.get("lecture_id")
    sentences = cache.assembled_transcript(lecture_id) if lecture_id else []
    in_range = [
        s for s in sentences
        if s.get("text") and start_n <= (_sid_to_int(s.get("sid")) or -1) <= end_n
    ]
    joined = " ".join(s.get("text", "") for s in in_range)
    segment_text = joined.strip()
    if not segment_text:
        return []

    # 各文がsegment_textの何字目から何字目か(" "でつないでからstripしているので、
    # 先頭で削れた分だけずらす)。窓と重なる文の最初と最後を、そのチャンクの文の範囲にする。
    lead = len(joined) - len(joined.lstrip())
    sentence_spans = []
    pos = 0
    for s in in_range:
        text = s.get("text", "")
        sentence_spans.append((pos - lead, pos - lead + len(text), _sid_to_int(s.get("sid"))))
        pos += len(text) + 1

    title = _header(cache, lecture_id, f"Transcript: {row.get('topic_title') or ''}")
    lec = cache.lecture(lecture_id)

    drafts = []
    for idx, (a, b) in enumerate(_text_window_spans(len(segment_text), TRANSCRIPT_CHUNK_CHARS, TRANSCRIPT_CHUNK_OVERLAP_CHARS)):
        sids = [sid for s_start, s_end, sid in sentence_spans if sid is not None and s_start < b and s_end > a]
        metadata: dict[str, Any] = {"topic_title": row.get("topic_title")}
        if sids:
            metadata["sid_start"] = min(sids)
            metadata["sid_end"] = max(sids)
        drafts.append(ChunkDraft(
            chunk_index=idx,
            title=title,
            body=segment_text[a:b],
            user_id=row["user_id"],
            course_id=lec.get("course_id"),
            lecture_id=lecture_id,
            metadata=metadata,
        ))
    return drafts


def _build_lecture_moment(admin_client, source_id: str, cache: _ContextCache) -> list[ChunkDraft]:
    res = admin_client.table("lecture_moments").select(
        "id, user_id, lecture_id, moment_type, note_text, deleted_at"
    ).eq("id", source_id).maybe_single().execute()
    row = res.data if res else None
    if not row or row.get("deleted_at"):
        return []
    if not (row.get("note_text") or "").strip():
        return []

    lec = cache.lecture(row.get("lecture_id"))
    return [ChunkDraft(
        chunk_index=0,
        title=_header(cache, row.get("lecture_id"), f"My note ({row.get('moment_type') or ''})"),
        body=row["note_text"].strip(),
        user_id=row["user_id"],
        course_id=lec.get("course_id"),
        lecture_id=row.get("lecture_id"),
        metadata={"moment_type": row.get("moment_type")},
    )]


def _build_chat_turn(admin_client, source_id: str, cache: _ContextCache) -> list[ChunkDraft]:
    """
    1往復(student + assistant)を1チャンクに。source_id = 返答(assistant)のメッセージID。
    トリガはrole='assistant' AND status='complete'の行だけを積むが、ここでも念のため
    確認する。往復の番号(turn_number)は、要約(chat_summary.pair_turns)と全く同じ数え方で
    振る(検索で当たった往復を、要約に畳まれた節(S*)や過去のスレッド(P*)の呼び名に
    結びつけるため、探索役chat_navigator.pyが使う)。
    """
    # 循環import回避(chat_summary.pyはこのモジュールに依存していない、一方向)。
    from app.services.chat_summary import fetch_active_blocks, pair_turns

    res = admin_client.table("chat_messages").select(
        "id, user_id, thread_id, role, content, status, deleted_at"
    ).eq("id", source_id).maybe_single().execute()
    row = res.data if res else None
    if not row or row.get("deleted_at") or row.get("role") != "assistant" or row.get("status") != "complete":
        return []

    thread_id = row["thread_id"]
    thread_res = admin_client.table("chat_threads").select("title, deleted_at")         .eq("id", thread_id).maybe_single().execute()
    thread = thread_res.data if thread_res else None
    if not thread or thread.get("deleted_at"):
        return []

    blocks = fetch_active_blocks(admin_client, thread_id)
    last = blocks[-1] if blocks else None
    rows_query = admin_client.table("chat_messages").select(
        "id, role, content, status, router, created_at"
    ).eq("thread_id", thread_id).is_("deleted_at", "null")
    if last:
        rows_query = rows_query.gt("created_at", last["end_message_created_at"])
    rows = rows_query.order("created_at").execute().data or []
    turns = pair_turns(rows, first_number=(last["turn_end"] + 1) if last else 1)

    turn = next((t for t in turns if t.assistant_message_id == source_id), None)
    if turn is None:
        # 既にもっと後ろまで畳まれた(このメッセージが属するブロックが新しく出来た)後の
        # 再実行や、断った/危機対応等でそもそも往復として数えられない場合。
        return []

    title = (thread.get("title") or "Untitled conversation").strip()
    date_str = (turn.assistant_created_at or "")[:10]
    body = f"Student: {turn.user_content[:CHAT_TURN_MAX_CHARS]}\nAssistant: {turn.assistant_content[:CHAT_TURN_MAX_CHARS]}"

    return [ChunkDraft(
        chunk_index=0,
        title=f"Chat: {title} / {date_str}",
        body=body,
        user_id=row["user_id"],
        metadata={
            "thread_id": thread_id,
            "turn_number": turn.number,
            "user_message_id": turn.user_message_id,
            "assistant_message_id": turn.assistant_message_id,
        },
    )]


SOURCE_TYPE_BUILDERS: dict[str, Callable[[Any, str, _ContextCache], list[ChunkDraft]]] = {
    "review_card": _build_review_card,
    "deep_note": _build_deep_note,
    "keyword": _build_keyword,
    "announcement": _build_announcement,
    "fun_fact": _build_fun_fact,
    "lecture_summary": _build_lecture_summary,
    "topic_summary": _build_topic_summary,
    "transcript_topic": _build_transcript_topic,
    "lecture_moment": _build_lecture_moment,
    "chat_turn": _build_chat_turn,
}


# =========================================================
# 🔢 埋め込み計算
# =========================================================

def _content_hash(draft: ChunkDraft) -> str:
    """
    「埋め込みAPIに実際に送る文字列 + モデル名 + 次元数」のハッシュ。
    本文だけでなくこれらも含めるのは、前置きの形式やモデルを将来変えた
    ときに「内容は同じだからスキップ」と誤判定させず、自動で再埋め込み
    させるため(バックフィルスクリプトを再実行するだけで入れ替わる)。
    """
    key = f"{KNOWLEDGE_EMBEDDING_MODEL}|{KNOWLEDGE_EMBEDDING_DIMENSIONS}|{draft.embedding_input}"
    return hashlib.sha256(key.encode("utf-8")).hexdigest()


_total_embedding_prompt_tokens = 0


def reset_embedding_token_usage() -> None:
    """バックフィルスクリプトが実行前に呼び、集計をゼロから始める。"""
    global _total_embedding_prompt_tokens
    _total_embedding_prompt_tokens = 0


def get_embedding_token_usage() -> int:
    """reset_embedding_token_usage()以降に_embed()へ渡された入力トークンの合計。"""
    return _total_embedding_prompt_tokens


_EMBED_RATE_LIMIT_MAX_RETRIES = 5
_EMBED_RATE_LIMIT_BASE_DELAY_SECONDS = 2.0


async def _embed(inputs: list[str]) -> tuple[list[list[float]], int]:
    """
    (ベクトルのリスト, 入力トークン数) を返す。トークン数は原価計算用。

    429(レート制限)だけは、その場で指数バックオフ(2s, 4s, 8s, 16s, 32s +
    ジッター)しながら数回リトライする。バックフィル等でconcurrencyを
    上げたときにAPI側の瞬間的な上限に当たっても、キューの再試行(最大5回)を
    無駄打ちせずその場で吸収するため。
    """
    global _total_embedding_prompt_tokens
    for attempt in range(_EMBED_RATE_LIMIT_MAX_RETRIES + 1):
        try:
            response = await litellm.aembedding(
                model=KNOWLEDGE_EMBEDDING_MODEL,
                input=inputs,
                dimensions=KNOWLEDGE_EMBEDDING_DIMENSIONS,
            )
            break
        except litellm.RateLimitError:
            if attempt >= _EMBED_RATE_LIMIT_MAX_RETRIES:
                raise
            delay = _EMBED_RATE_LIMIT_BASE_DELAY_SECONDS * (2 ** attempt) + random.uniform(0, 1)
            print(f"  ⏳ [knowledge_index] Embedding APIのレート制限、{delay:.1f}秒待って再試行します ({attempt + 1}/{_EMBED_RATE_LIMIT_MAX_RETRIES})")
            await asyncio.sleep(delay)

    usage = getattr(response, "usage", None)
    prompt_tokens = int(getattr(usage, "prompt_tokens", 0) or 0)
    _total_embedding_prompt_tokens += prompt_tokens
    return [d["embedding"] for d in response.data], prompt_tokens


async def embed_document(draft: ChunkDraft) -> list[float]:
    """
    検索される側(文書)の埋め込み。Embedding 2にはtask_type引数が無く、
    公式ドキュメントは非対称検索で文書側を "title: {title} | text: {本文}"、
    クエリ側を "task: search result | query: {質問}" にするよう推奨している。
    (2026-10-01以前の実装は文書側にもクエリ形式を付けていた。バックフィル前に
    気付いたため、誤った形式で保存されたデータは無い。)
    """
    vectors, _ = await _embed([draft.embedding_input])
    return vectors[0]


async def embed_queries(queries: list[str], billing=None) -> list[list[float]]:
    """
    チャットの検索クエリ側の埋め込み。文書側とは前置きが違うので必ずこちらを使う。
    billing(BillingEngine)を渡すと、その分の原価をチャットの課金に含める。
    """
    vectors, prompt_tokens = await _embed([f"task: search result | query: {q}" for q in queries])
    if billing is not None:
        billing.add_token_cost(KNOWLEDGE_EMBEDDING_MODEL, prompt_tokens, 0)
    return vectors


# =========================================================
# 🧭 1件のインデックス化 + キューの処理
# =========================================================

async def _index_one(admin_client, cache: _ContextCache, source_type: str, source_id: str) -> None:
    builder = SOURCE_TYPE_BUILDERS.get(source_type)
    if builder is None:
        raise ValueError(f"Unknown source_type for knowledge indexing: {source_type}")

    drafts = await asyncio.to_thread(builder, admin_client, source_id, cache)

    existing_res = await asyncio.to_thread(
        lambda: admin_client.table("knowledge_chunks")
            .select("id, chunk_index, content_hash")
            .eq("source_type", source_type).eq("source_id", source_id)
            .execute()
    )
    existing_by_index = {row["chunk_index"]: row for row in (existing_res.data or [])}

    keep_indices: set[int] = set()
    for draft in drafts:
        keep_indices.add(draft.chunk_index)
        content_hash = _content_hash(draft)
        existing = existing_by_index.get(draft.chunk_index)

        if existing and existing.get("content_hash") == content_hash:
            # 内容は不変。講義の移動等で付随列だけ変わっている可能性が
            # あるのでそこだけ同期し、埋め込みAPIは呼ばない。
            await asyncio.to_thread(
                lambda existing=existing, draft=draft: admin_client.table("knowledge_chunks").update({
                    "user_id": draft.user_id,
                    "course_id": draft.course_id,
                    "lecture_id": draft.lecture_id,
                    "metadata": draft.metadata,
                    "deleted_at": None,
                }).eq("id", existing["id"]).execute()
            )
            continue

        embedding = await embed_document(draft)
        await asyncio.to_thread(
            lambda draft=draft, content_hash=content_hash, embedding=embedding:
                admin_client.table("knowledge_chunks").upsert({
                    "source_type": source_type,
                    "source_id": source_id,
                    "chunk_index": draft.chunk_index,
                    "user_id": draft.user_id,
                    "course_id": draft.course_id,
                    "lecture_id": draft.lecture_id,
                    "content": draft.content,
                    "content_hash": content_hash,
                    "embedding": embedding,
                    "embedding_model": KNOWLEDGE_EMBEDDING_MODEL,
                    "metadata": draft.metadata,
                    "deleted_at": None,
                }, on_conflict="source_type,source_id,chunk_index").execute()
        )

    # 前回より生成チャンク数が減った(内容が短くなった等)場合の残骸を消す。
    stale_indices = [idx for idx in existing_by_index if idx not in keep_indices]
    if stale_indices:
        await asyncio.to_thread(
            lambda: admin_client.table("knowledge_chunks").delete()
                .eq("source_type", source_type).eq("source_id", source_id)
                .in_("chunk_index", stale_indices).execute()
        )


async def drain_knowledge_index_queue(limit: int = 200, concurrency: int = 8) -> dict:
    """
    knowledge_index_queueからPENDING分を(FOR UPDATE SKIP LOCKEDで安全に)
    取り出して処理する。patrol・FINALIZE_JOB・バックフィルスクリプトの
    全てがこれを呼ぶ、ロジックの実体はここ1箇所だけ。

    concurrencyは主にバックフィル(数千件を一度に処理)を現実的な時間で
    終わらせるためのもの。Embedding 2のレート上限(10000 rpm)に対して
    既定値8は十分小さく、通常運用のpatrol/FINALIZE_JOBでもそのまま使う。
    """
    admin_client = get_supabase_client()

    claimed = await asyncio.to_thread(
        lambda: admin_client.rpc("claim_knowledge_index_queue_batch", {"p_limit": limit}).execute()
    )
    rows = claimed.data or []
    if not rows:
        return {"claimed": 0, "succeeded": 0, "failed": 0}

    cache = _ContextCache(admin_client)
    semaphore = asyncio.Semaphore(max(1, concurrency))
    counts = {"succeeded": 0, "failed": 0}

    async def _process(row: dict) -> None:
        async with semaphore:
            try:
                await _index_one(admin_client, cache, row["source_type"], row["source_id"])
                await asyncio.to_thread(
                    lambda: admin_client.table("knowledge_index_queue").delete().eq("id", row["id"]).execute()
                )
                counts["succeeded"] += 1
            except Exception as e:
                counts["failed"] += 1
                attempts = row.get("attempts", 1)
                new_status = "FAILED" if attempts >= MAX_QUEUE_ATTEMPTS else "PENDING"
                print(f"⚠️ [knowledge_index] {row['source_type']}/{row['source_id']} failed (attempt {attempts}): {e}")
                try:
                    await asyncio.to_thread(
                        lambda: admin_client.table("knowledge_index_queue").update({
                            "status": new_status,
                            "last_error": str(e)[:2000],
                        }).eq("id", row["id"]).execute()
                    )
                except Exception:
                    # 処理中だった間に同じsourceへの新しい編集が入り、既に別の
                    # PENDING行が積まれている(partial unique indexに抵触)。
                    # 新しい方がこの内容を包含するはずなので、古い方はただ消す。
                    await asyncio.to_thread(
                        lambda: admin_client.table("knowledge_index_queue").delete().eq("id", row["id"]).execute()
                    )

    await asyncio.gather(*(_process(row) for row in rows))
    return {"claimed": len(rows), "succeeded": counts["succeeded"], "failed": counts["failed"]}
