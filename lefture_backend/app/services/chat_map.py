# app/services/chat_map.py
"""
チャットの探索役(chat_navigator.py)に見せる「地図」と、短い呼び名(C1, C1/L3)の対応表。
docs/chatbot_context_and_retrieval_roadmap.md の 3-5。

- 探索役にはUUIDを見せず、1ターンの間だけ有効な短い呼び名を使わせる(UUIDは長くて
  トークンの無駄が多く、存在しないIDを作ることがある)。呼び名 → UUIDの変換はここで行い、
  探索役が選べる呼び名はJSON Schemaのenumで縛る。
- 呼び名はターンごとに振り直す。コースは作成順、講義はコースの中でsort_order順
  (同じなら日時順)。次のターンに持ち越すもの(前のターンで開いたものなど)は、
  呼び名ではなくUUIDで保存すること(講義が増えたり消えたりすると番号がずれる)。
- 地図のコースの行には、学期(course_attributesは任意入力)と講義の日付の範囲、
  録音の言語とまとめの言語を載せる。学期が未設定でも日付の範囲から「今学期」を判断でき、
  検索語を「探す先の材料の言語」で書けるようにするため。
"""

from collections import Counter
from dataclasses import dataclass, field
from datetime import date, datetime, timezone, tzinfo
from typing import Optional
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

LANGUAGE_NAMES = {
    "en": "English", "ja": "Japanese", "zh": "Chinese", "ko": "Korean", "es": "Spanish",
    "fr": "French", "de": "German", "pt": "Portuguese", "it": "Italian", "vi": "Vietnamese",
}


def language_name(code: Optional[str]) -> str:
    if not code:
        return "unknown"
    base = code.strip().split("-")[0].split("_")[0].lower()
    return LANGUAGE_NAMES.get(base, code.strip())


def _majority(values: list[Optional[str]]) -> Optional[str]:
    counts = Counter(v.strip() for v in values if v and v.strip())
    return counts.most_common(1)[0][0] if counts else None


def resolve_timezone(name: Optional[str]) -> tzinfo:
    """クライアントが送ってきたIANAのタイムゾーン名(例: Asia/Tokyo)。無い・不正ならUTC。"""
    if name:
        try:
            return ZoneInfo(name)
        except (ZoneInfoNotFoundError, ValueError):
            pass
    return timezone.utc


def _to_date(value: Optional[str], tz: tzinfo) -> Optional[date]:
    """lecture_datetime(timestamptz)を、ユーザーのタイムゾーンでの日付に。"""
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(tz).date()
    except ValueError:
        return None


@dataclass
class MapLecture:
    handle: str
    id: str
    course_handle: str
    title: str
    date: Optional[date]


@dataclass
class MapCourse:
    handle: str
    id: str
    title: str
    term: Optional[str]
    recorded_language: Optional[str]
    notes_language: Optional[str]
    lectures: list[MapLecture] = field(default_factory=list)

    def map_line(self) -> str:
        dates = [lec.date for lec in self.lectures if lec.date]
        span = f" ({min(dates).isoformat()} – {max(dates).isoformat()})" if dates else ""
        return (
            f"{self.handle}: {self.title} — {self.term or 'term not set'} — {len(self.lectures)} lectures{span}"
            f" — recorded in {language_name(self.recorded_language)}, notes in {language_name(self.notes_language)}"
        )


@dataclass
class StudentMap:
    courses: list[MapCourse] = field(default_factory=list)
    _course_by_handle: dict[str, MapCourse] = field(default_factory=dict)
    _lecture_by_handle: dict[str, MapLecture] = field(default_factory=dict)
    _lecture_handle_by_id: dict[str, str] = field(default_factory=dict)
    _course_handle_by_id: dict[str, str] = field(default_factory=dict)

    @classmethod
    def build(cls, courses: list[MapCourse]) -> "StudentMap":
        m = cls(courses=courses)
        for c in courses:
            m._course_by_handle[c.handle] = c
            m._course_handle_by_id[c.id] = c.handle
            for lec in c.lectures:
                m._lecture_by_handle[lec.handle] = lec
                m._lecture_handle_by_id[lec.id] = lec.handle
        return m

    @property
    def has_lectures(self) -> bool:
        return bool(self._lecture_by_handle)

    def scope_handles(self) -> list[str]:
        """絞り込み(within)に使える呼び名: 全コースと全講義。"""
        return [c.handle for c in self.courses] + list(self._lecture_by_handle)

    def course(self, handle: str) -> Optional[MapCourse]:
        return self._course_by_handle.get(handle)

    def lecture(self, handle: str) -> Optional[MapLecture]:
        return self._lecture_by_handle.get(handle)

    def lecture_handle(self, lecture_id: Optional[str]) -> Optional[str]:
        return self._lecture_handle_by_id.get(lecture_id) if lecture_id else None

    def course_handle(self, course_id: Optional[str]) -> Optional[str]:
        return self._course_handle_by_id.get(course_id) if course_id else None

    def lectures_between(self, start: date, end: date, within: Optional[str] = None) -> list[MapLecture]:
        """日付で引く(by_date)。withinはコースか講義の呼び名。"""
        out = []
        for c in self.courses:
            for lec in c.lectures:
                if lec.date is None or not (start <= lec.date <= end):
                    continue
                if within and within not in (c.handle, lec.handle):
                    continue
                out.append(lec)
        return sorted(out, key=lambda lec: (lec.date, lec.handle))

    def describe(self, handle: str) -> str:
        """画面の文脈などで「C2/L4 (Price Elasticity of Demand, 2026-04-10)」のように添える説明。"""
        lec = self.lecture(handle)
        if lec:
            when = f", {lec.date.isoformat()}" if lec.date else ""
            return f"{handle} ({self.course(lec.course_handle).title} / {lec.title}{when})"
        c = self.course(handle)
        return f"{handle} ({c.title})" if c else handle

    def render_courses(self) -> str:
        if not self.courses:
            return "(The student has no courses yet.)"
        return "\n".join(c.map_line() for c in self.courses)


@dataclass
class ChatSection:
    """この会話の要約に畳んだ節(chat_summary_blocks.sections)。handleは要約側が振った
    通し番号をそのまま使う(ブロックをまたいでも重複しない)。"""
    handle: str  # "S{n}"
    title: str
    turns: list[int]


@dataclass
class ChatThreadRef:
    handle: str  # "P{n}"
    id: str
    title: str
    date: Optional[str]
    trail: list[str]

    def map_line(self, max_trail: int = 4) -> str:
        trail = " → ".join([self.title, *self.trail[:max_trail]])
        return f"{self.handle} ({self.date or 'no date'}) {trail}"


@dataclass
class ChatMap:
    """この会話の畳んだ節(S*)と、最近のチャット(P*)。3-14 ④の地図。"""
    sections: list[ChatSection] = field(default_factory=list)
    recent_threads: list[ChatThreadRef] = field(default_factory=list)
    _section_by_handle: dict[str, ChatSection] = field(default_factory=dict)
    _thread_by_handle: dict[str, ChatThreadRef] = field(default_factory=dict)
    _thread_handle_by_id: dict[str, str] = field(default_factory=dict)
    # 検索で当たった、最近のチャットに無いスレッドに動的に振る番号(P21〜)
    _next_extra: int = 0

    @classmethod
    def build(cls, sections: list[ChatSection], recent_threads: list[ChatThreadRef]) -> "ChatMap":
        m = cls(sections=sections, recent_threads=recent_threads, _next_extra=len(recent_threads) + 1)
        for s in sections:
            m._section_by_handle[s.handle] = s
        for t in recent_threads:
            m._thread_by_handle[t.handle] = t
            m._thread_handle_by_id[t.id] = t.handle
        return m

    @property
    def has_anything(self) -> bool:
        return bool(self.sections or self.recent_threads)

    def scope_handles(self) -> list[str]:
        return [s.handle for s in self.sections] + [t.handle for t in self.recent_threads]

    def section(self, handle: str) -> Optional[ChatSection]:
        return self._section_by_handle.get(handle)

    def thread(self, handle: str) -> Optional[ChatThreadRef]:
        return self._thread_by_handle.get(handle)

    def thread_handle(self, thread_id: Optional[str]) -> Optional[str]:
        return self._thread_handle_by_id.get(thread_id) if thread_id else None

    def handle_for_new_thread(self, thread_id: str, title: str, date_str: Optional[str]) -> str:
        """検索で最近20件に無いスレッドが当たったとき、その場でP21…を振って覚えておく。"""
        existing = self.thread_handle(thread_id)
        if existing:
            return existing
        handle = f"P{self._next_extra}"
        self._next_extra += 1
        self.add_thread(ChatThreadRef(handle=handle, id=thread_id, title=title, date=date_str, trail=[]))
        return handle

    def add_thread(self, ref: ChatThreadRef) -> None:
        """最近20件に入っていないスレッドを、呼び名で開けるように覚える(地図の一覧には出さない)。"""
        self._thread_by_handle[ref.handle] = ref
        self._thread_handle_by_id[ref.id] = ref.handle

    def render(self) -> str:
        parts = []
        if self.sections:
            parts.append("Folded sections of this conversation:")
            parts += [f"{s.handle} {s.title}" for s in self.sections]
        if self.recent_threads:
            if parts:
                parts.append("")
            parts.append("Recent chats:")
            parts += [t.map_line() for t in self.recent_threads]
        return "\n".join(parts) if parts else "(No other chats yet.)"


def load_chat_map(current_sections: list[dict], recent: list[dict]) -> ChatMap:
    """
    current_sections: turn.summary_blocks(chat_service経由で既に読み込み済み)の
    sections(handle/title)をそのまま渡す(この会話用の追加クエリは不要)。
    recent: ChatThreadSource.recent_threads_with_trailの結果。
    """
    sections = [ChatSection(handle=f"S{sec['handle']}", title=sec["title"], turns=sec["turns"])
                for block in current_sections for sec in block.get("sections") or []]
    threads = [ChatThreadRef(handle=f"P{i}", id=t["id"], title=t["title"], date=t["date"], trail=t["trail"])
               for i, t in enumerate(recent, start=1)]
    return ChatMap.build(sections, threads)


def load_student_map(admin_client, user_id: str, tz: tzinfo = timezone.utc) -> StudentMap:
    """本人のコース・講義から地図を作る(同期関数。asyncio.to_threadで呼ぶ)。日付はtzで数える。"""
    courses_res = admin_client.table("courses").select(
        "id, course_title, course_code, term_id, year_id, created_at"
    ).eq("user_id", user_id).is_("deleted_at", "null").order("created_at").execute()
    course_rows = courses_res.data or []

    lectures_res = admin_client.table("lectures").select(
        "id, course_id, title, title_generated, lecture_datetime, sort_order, recording_language, display_language"
    ).eq("user_id", user_id).is_("deleted_at", "null").execute()
    lecture_rows = lectures_res.data or []

    attr_ids = {r[k] for r in course_rows for k in ("term_id", "year_id") if r.get(k)}
    attr_names: dict[str, str] = {}
    if attr_ids:
        attrs_res = admin_client.table("course_attributes").select("id, attribute_name") \
            .in_("id", list(attr_ids)).execute()
        attr_names = {a["id"]: (a.get("attribute_name") or "").strip() for a in (attrs_res.data or [])}

    by_course: dict[str, list[dict]] = {}
    for row in lecture_rows:
        if row.get("course_id"):
            by_course.setdefault(row["course_id"], []).append(row)

    courses: list[MapCourse] = []
    for i, row in enumerate(course_rows, start=1):
        code = (row.get("course_code") or "").strip()
        title = (row.get("course_title") or "").strip()
        if code and code.lower() not in title.lower():
            title = f"{code} {title}".strip()
        term_parts = [attr_names.get(row.get("year_id") or ""), attr_names.get(row.get("term_id") or "")]
        term = " ".join(p for p in term_parts if p) or None

        rows = sorted(by_course.get(row["id"], []),
                      key=lambda r: (r.get("sort_order") or 0, r.get("lecture_datetime") or ""))
        handle = f"C{i}"
        course = MapCourse(
            handle=handle, id=row["id"], title=title or "(untitled course)", term=term,
            recorded_language=_majority([r.get("recording_language") for r in rows]),
            notes_language=_majority([r.get("display_language") for r in rows]),
        )
        for j, lec in enumerate(rows, start=1):
            course.lectures.append(MapLecture(
                handle=f"{handle}/L{j}", id=lec["id"], course_handle=handle,
                title=(lec.get("title") or lec.get("title_generated") or "(untitled lecture)").strip(),
                date=_to_date(lec.get("lecture_datetime"), tz),
            ))
        courses.append(course)

    return StudentMap.build(courses)
