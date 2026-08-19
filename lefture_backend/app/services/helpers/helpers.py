import re
import json
import hashlib
import uuid
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional, List, Dict, Any

from app.core.config import PROMPTS_DIR
from app.core.supabase import get_supabase_client

def _strip_code_fence(text: str) -> str:
    if text.lstrip().startswith("```"):
        lines = [ln.rstrip("\n") for ln in text.splitlines()]
        # 先頭の```を落とす
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        # 末尾の```を落とす
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        text = "\n".join(lines)
    return text

def extract_json_string(text: str) -> str:
    text_stripped = text.strip()
    if not text_stripped:
        return ""
    
    # Check for Together AI GPT-OSS Harmony/JSON Mode corruption prefixes
    # e.g., {"final{": {"key": "value"}} -> {"key": "value"}
    # e.g., {"final{\": {"key": "value"}} -> {"key": "value"}
    # e.g., {"final": {"key": "value"}}  -> {"key": "value"}
    if text_stripped.startswith('{"final'):
        colon_idx = text_stripped.find(':')
        if colon_idx != -1:
            inner_idx = -1
            # Find the first true opening brace/bracket after the first colon
            for idx in range(colon_idx + 1, len(text_stripped)):
                if text_stripped[idx] in ('{', '['):
                    inner_idx = idx
                    break
            
            if inner_idx != -1:
                # Find matching ending brace by removing one outer '}' at the end
                last_idx = text_stripped.rfind('}')
                if last_idx > inner_idx:
                    text_stripped = text_stripped[inner_idx:last_idx]
    
    # 最初に見つかる { または [ を探す
    first_idx = -1
    first_char = ''
    for idx, char in enumerate(text_stripped):
        if char in ('{', '['):
            first_idx = idx
            first_char = char
            break
            
    if first_idx == -1:
        return text_stripped
        
    last_char = '}' if first_char == '{' else ']'
    last_idx = text_stripped.rfind(last_char)
    
    if last_idx != -1 and last_idx > first_idx:
        return text_stripped[first_idx:last_idx + 1]
        
    return text_stripped



def _load_prompt(filename: str) -> str:
    prompt_path = PROMPTS_DIR / filename
    if not prompt_path.exists():
        raise FileNotFoundError(f"Prompt file not found: {filename}")

    return prompt_path.read_text(encoding="utf-8")


_COND_BLOCK_RE = re.compile(
    r"<!--IF:(?P<name>\w+)-->(?P<if_branch>.*?)(?:<!--ELSE-->(?P<else_branch>.*?))?<!--END_IF-->",
    re.DOTALL,
)


def _render_conditional_sections(template: str, conditions: dict[str, bool]) -> str:
    """
    プロンプト内の <!--IF:NAME-->...<!--ELSE-->...<!--END_IF--> ブロックを、
    conditions[NAME]の真偽で分岐させて片方だけ残す(ELSEは省略可)。名前付きに
    しているのは、例えば「最終トピックかどうか」と「最初のトピックかどうか」の
    ように複数の独立した条件が同時に真になり得る(トピックが1個しか無い講義)
    ケースを、単一のbool引数では表現できないため。各条件はコード側で確定させた
    事実であり、LLMに無関係な分岐の指示文を読ませてトークンを無駄にしないためのもの。
    """
    def _replace(m: "re.Match[str]") -> str:
        is_true = conditions.get(m.group("name"), False)
        return m.group("if_branch") if is_true else (m.group("else_branch") or "")
    return _COND_BLOCK_RE.sub(_replace, template)


def _sid_to_int(sid: Optional[str]) -> Optional[int]:
    """
    'sXXXXXX' 形式のSID文字列を数値へ変換する。LLMが返しがちな軽微な
    フォーマット崩れ（大文字S、sプレフィックス無し、ゼロ埋め桁数の過不足）も
    許容する。int()変換自体がゼロ埋めの過不足を自然に吸収してくれるため、
    ここで拾う必要があるのは「sの有無・大文字小文字」だけ。
    """
    SID_NUM = re.compile(r"[sS]?(\d+)")
    if not sid:
        return None
    m = SID_NUM.fullmatch(sid.strip())
    return int(m.group(1)) if m else None


def _int_to_sid(n: int) -> str:
    """数値を正規形のSID文字列（s + ゼロ埋め6桁）に変換する。"""
    return f"s{n:06d}"


# =========================================================
# 📝 新しいロギング・システム (TaskLogger)
# =========================================================

class TaskLogger:
    """
    タスクごとに独立してログを保持するクラス。
    グローバル変数の競合を防ぎ、Cloud Runでの並列処理を安全にします。
    """
    def __init__(self, uid: str, lecture_id: str, task_name: str):
        self.uid = uid
        self.lecture_id = lecture_id
        self.task_name = task_name
        self.logs: List[Dict[str, str]] = []
        
    def log(self, *args):
        """コンソールに出力しつつ、メモリ内のリストに保存"""
        message = " ".join(map(str, args))
        
        # コンソールではどのタスクのログか分かりやすいようにプレフィックスをつける
        print(f"[{self.task_name}] {message}") 
        
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        self.logs.append({
            "timestamp": timestamp,
            "message": message
        })
        
    def save_to_r2(self, storage_service) -> str:
        """
        タスクの最後に呼び出し、R2にコンソールログJSONを保存する。
        """
        if not self.logs:
            return ""
        
        final_data = {
            "task_name": self.task_name, 
            "logs": self.logs
        }
        
        # 例: uid/lecture_id/pipeline_logs/core_extraction_console.json に保存
        r2_path = storage_service.save_json_log(
            self.uid, 
            self.lecture_id, 
            f"{self.task_name}_console", 
            final_data
        )
        return r2_path


# ---------------------------------------------------------
# 下位互換性用のヘルパー (※一部の職人クラスでまだ呼ばれている場合のため)
# ---------------------------------------------------------
def print_log(*args):
    """
    [非推奨] 
    今後は各タスク内で生成した logger.log() を使用してください。
    この関数は純粋なコンソール出力のみを行い、ファイルには保存されません。
    """
    print(" ".join(map(str, args)))


def _parse_detail_contents(content: str) -> tuple[str, str]:
    """
    Detailed Contents (Markdown) から、以下の2つを抽出して返す:
    - summary: タイトル(H1)のすぐ下にある1-3文のミニサマリー (最初の段落)
    - clean_contents: タイトルとミニサマリーを抜いた、H2以降の純粋なコンテンツ
    """
    lines = content.strip().splitlines()
    if not lines:
        return "", ""

    # H1 タイトル行を探す
    title_idx = -1
    for i, line in enumerate(lines):
        if line.strip().startswith('# '):
            title_idx = i
            break

    if title_idx == -1:
        # H1 が見つからない場合はサマリーを空、全体をコンテンツとする
        return "", content

    summary_lines = []
    content_start_idx = -1

    def _is_heading_line(line_str: str) -> bool:
        s = line_str.strip()
        if not s:
            return False
        # 標準的なMarkdown見出し (#, ##, ###)
        if s.startswith('#'):
            return True
        # 太字で始まる単独行 (例: **タイトル** または 🦁 **タイトル**)
        if (s.startswith('**') and s.endswith('**')) or s.startswith('* ') or s.startswith('- '):
            return True
        # 絵文字から始まる短めの行（見出しとみなす）
        if len(s) < 60 and re.match(r'^[\U00010000-\U0010ffff\u2600-\u27ff\u2300-\u23ff]', s):
            return True
        return False

    # H1 の次の行からスキャン開始
    for i in range(title_idx + 1, len(lines)):
        line = lines[i]
        stripped = line.strip()

        # 空行だった場合
        if not stripped:
            if summary_lines:
                # すでにサマリー（最初の段落）を読み込み済みなら、空行に達した時点でサマリー抽出終了
                content_start_idx = i + 1
                break
            continue  # H1直後の空行はスキップ

        # 見出しとみなせる行が来たらサマリー抽出終了
        if _is_heading_line(stripped):
            content_start_idx = i
            break

        summary_lines.append(line)

    summary = "\n".join(summary_lines).strip()

    # コンテンツ本体の切り出し
    if content_start_idx != -1 and content_start_idx < len(lines):
        clean_contents = "\n".join(lines[content_start_idx:]).strip()
    else:
        remaining_lines = lines[title_idx + 1 + len(summary_lines):]
        clean_contents = "\n".join(remaining_lines).strip()

    # セイフティネット: 万が一サマリーが400文字を超えて長大化している場合は最初の段落のみを強制抽出
    if len(summary) > 400:
        summary_paragraphs = [p.strip() for p in summary.split('\n\n') if p.strip()]
        if len(summary_paragraphs) > 1:
            summary = summary_paragraphs[0]
            overflow_text = "\n\n".join(summary_paragraphs[1:])
            clean_contents = f"{overflow_text}\n\n{clean_contents}".strip()

    return summary, clean_contents


def _generate_topic_node_id(lecture_id: str, topic_index_in_lecture: int) -> str:
    """
    Topic MapのノードIDを、Lecture ID + Lecture内トピック番号から決定的に生成する。
    タイトル文字列やLecture番号（位置）は使わない: タイトルは長文かつLLMに
    一字一句コピーさせるのは事故りやすく、位置(lecture_num)はLecture削除・移動で
    変わりうるため、IDに焼き込むと過去ノードの参照が腐る。lecture_id自体は
    不変なので、同じトピックは常に同じIDになる（パイプラインがリトライされても
    重複ノードを作らない）。
    """
    digest = hashlib.sha1(f"{lecture_id}:{topic_index_in_lecture}".encode("utf-8")).hexdigest()
    return f"node_{digest[:10]}"


def _fetch_live_lecture_order_sync(supabase, course_id: str) -> list[str]:
    """
    course_id内の非削除Lectureを created_at 昇順で並べた Lecture ID のリストを返す。
    Topic Map上の「Lecture N」という順序は保存時点のスナップショットではなく、
    呼び出しの都度これで計算する。こうすることで、過去に削除・移動があっても
    LLMや画面表示に渡す順序は常に現在の状態を反映する（自己修復する）。
    """
    res = supabase.table("lectures").select("id")\
        .eq("course_id", course_id)\
        .is_("deleted_at", "null")\
        .order("created_at")\
        .execute()
    return [l["id"] for l in (res.data or [])]


def _course_has_running_job_sync(supabase, course_id: str) -> bool:
    """
    このCourse配下のいずれかのLectureに、まだ完了していない(RUNNING状態の)
    processing_jobsが無いかを確認する。TOPIC_MAPPINGはこのJobのDAGタスクの
    1つとして走るため、個別のタスク種別ではなくJob単位でRUNNINGかどうかを見る
    方が安全(録音パイプラインに将来タスクが増えても網羅できる)。
    Topic MapのRecreate(手動/Patrol)は、この間だけmap書き込みが競合し得る
    ウィンドウを避けるために、開始前にこれをチェックしてブロックする。
    """
    lec_res = supabase.table("lectures").select("id")\
        .eq("course_id", course_id)\
        .is_("deleted_at", "null")\
        .execute()
    lecture_ids = [l["id"] for l in (lec_res.data or [])]
    if not lecture_ids:
        return False

    job_res = supabase.table("processing_jobs").select("id")\
        .in_("lecture_id", lecture_ids)\
        .eq("status", "RUNNING")\
        .limit(1)\
        .execute()
    return len(job_res.data or []) > 0


# Recreate/Patrolが同じCourseに対して二重に走るのを防ぐための、topic_maps.metadata
# (jsonb, 他に用途の無い列)を使った簡易ロックの有効期限。プロセスクラッシュ等で
# 解放漏れが起きても、この時間が経てば次の呼び出しが自動的に回収できる。
RECONSTRUCTION_LOCK_STALE_MINUTES = 10


def _try_acquire_reconstruction_lock_sync(supabase, course_id: str) -> str | None:
    """
    topic_maps行に対する簡易的な排他ロックをCAS(compare-and-swap)的に取得する。
    専用のロックテーブルや行ロックが無いため、「ロックが無い、または
    RECONSTRUCTION_LOCK_STALE_MINUTES以上前の古いロックが残っている」場合だけ
    更新できる条件付きUPDATEにして、実際に更新できたか(0件 or 1件)で判定する。
    取得できればロックID(自分だけが知っている値)を返し、取れなければNoneを返す。
    """
    lock_id = str(uuid.uuid4())
    now_iso = datetime.now(timezone.utc).isoformat()
    stale_before_iso = (datetime.now(timezone.utc) - timedelta(minutes=RECONSTRUCTION_LOCK_STALE_MINUTES)).isoformat()

    res = supabase.table("topic_maps").update({
        "metadata": {"reconstruction_lock_id": lock_id, "reconstruction_locked_at": now_iso}
    }).eq("course_id", course_id).or_(
        f"metadata->>reconstruction_locked_at.is.null,"
        f"metadata->>reconstruction_locked_at.lt.{stale_before_iso}"
    ).execute()

    return lock_id if (res.data or []) else None


def _release_reconstruction_lock_sync(supabase, course_id: str, lock_id: str) -> None:
    """
    自分が取得したロックだけを解放する。stale判定で既に他プロセスに奪われていた
    場合、その新しいロックを誤って消さないよう lock_id が一致する行だけを対象にする。
    """
    supabase.table("topic_maps").update({
        "metadata": {"reconstruction_lock_id": None, "reconstruction_locked_at": None}
    }).eq("course_id", course_id).eq("metadata->>reconstruction_lock_id", lock_id).execute()


def _annotate_nodes_with_live_lecture_num(nodes: list[dict], lecture_num_by_id: dict[str, int]) -> list[dict]:
    """
    ノード群のコピーに、現時点のLecture順序(lecture_num)を一時的に注記する。
    これはLLMへの入力としてのみ使う揮発的な値で、topic_maps.mapには保存しない
    （保存すると位置が固定化され、削除・移動のたびに腐っていくため）。
    削除済み・見つからないLectureに属するノードは source_lecture_id が
    現在のLecture一覧に無いため lecture_num=None になる。
    """
    annotated = []
    for n in nodes:
        n_copy = dict(n)
        n_copy["lecture_num"] = lecture_num_by_id.get(n.get("source_lecture_id"))
        annotated.append(n_copy)
    return annotated


def _prune_lecture_nodes(graph: dict, source_lecture_id: str, logger=None) -> dict:
    """
    Phase A: 指定Lectureに属するノードを、LLMを介さず決定的にグラフから除去する。
    - source_lecture_id が一致するノードを nodes から削除
    - どちらかの端点が消えたエッジを削除
    - derived_from_topic_id が消えたノードを指していた ghost_node は削除
      （どのトピックから予測されたか分からなくなったGhostは残さない方針）
    - この除去の結果、どのノード/ghost_nodeからも参照されなくなった
      （空になった）クラスターも削除する。
    """
    import copy
    new_graph = copy.deepcopy(graph)

    def _log(msg: str) -> None:
        if logger is not None:
            logger.log(msg)

    all_nodes = new_graph.get("nodes", [])
    removed_ids = {n.get("topic_id") for n in all_nodes if n.get("source_lecture_id") == source_lecture_id}

    if not removed_ids:
        return new_graph

    new_graph["nodes"] = [n for n in all_nodes if n.get("topic_id") not in removed_ids]
    new_graph["edges"] = [
        e for e in new_graph.get("edges", [])
        if e.get("source_id") not in removed_ids and e.get("target_id") not in removed_ids
    ]
    new_graph["ghost_nodes"] = [
        g for g in new_graph.get("ghost_nodes", [])
        if g.get("derived_from_topic_id") not in removed_ids
    ]

    remaining_cluster_ids = {n.get("cluster_id") for n in new_graph["nodes"] if n.get("cluster_id")}
    remaining_cluster_ids |= {g.get("cluster_id") for g in new_graph["ghost_nodes"] if g.get("cluster_id")}
    emptied_clusters = [
        c.get("cluster_id") for c in new_graph.get("clusters", [])
        if c.get("cluster_id") not in remaining_cluster_ids
    ]
    if emptied_clusters:
        new_graph["clusters"] = [
            c for c in new_graph.get("clusters", []) if c.get("cluster_id") in remaining_cluster_ids
        ]
        _log(f"🧹 Removed {len(emptied_clusters)} now-empty cluster(s): {emptied_clusters}")

    _log(f"🧹 Pruned {len(removed_ids)} node(s) for lecture {source_lecture_id} (and their edges/derived ghosts).")
    return new_graph


def _merge_graph_mutation(current_graph: dict, mutations: dict, todays_topics: list[dict], logger=None) -> dict:
    """
    Topic Mapping (LLM) から出力された差分(mutations)を、
    現在の Full Map 状態(current_graph)に適用し、最新の Full Map 状態を返します。
    """
    import copy
    new_graph = copy.deepcopy(current_graph)

    def _log(msg: str) -> None:
        if logger is not None:
            logger.log(msg)
    
    # 1. クラスターのアクション (create / rename / remove)
    cluster_actions = mutations.get("cluster_actions", [])
    for action_item in cluster_actions:
        action = action_item.get("action")
        cluster_id = action_item.get("cluster_id")
        name = action_item.get("name")
        if not cluster_id:
            continue
            
        if action == "create":
            if not any(c.get("cluster_id") == cluster_id for c in new_graph.get("clusters", [])):
                if "clusters" not in new_graph:
                    new_graph["clusters"] = []
                new_graph["clusters"].append({
                    "cluster_id": cluster_id,
                    "name": name
                })
        elif action == "rename":
            for c in new_graph.get("clusters", []):
                if c.get("cluster_id") == cluster_id:
                    c["name"] = name
                    break
        elif action == "remove":
            new_graph["clusters"] = [c for c in new_graph.get("clusters", []) if c.get("cluster_id") != cluster_id]
            # このクラスタに属していたノード/ゴーストノードを放置すると、
            # (このmutation内のnode_placementsで再配置されない限り)存在しない
            # クラスタを指したまま残ってしまう -- node_placements側で直した
            # バグの鏡像。ここで一旦「未分類」に戻しておき、この後のnode_placements
            # が同じmutation内で再配置すればそちらが優先される(下で上書きされる)。
            orphaned = 0
            for n in new_graph.get("nodes", []):
                if n.get("cluster_id") == cluster_id:
                    n["cluster_id"] = None
                    orphaned += 1
            for g in new_graph.get("ghost_nodes", []):
                if g.get("cluster_id") == cluster_id:
                    g["cluster_id"] = None
            if orphaned:
                _log(f"⚠️ Cluster '{cluster_id}' removed while {orphaned} node(s) still referenced it: reset to unclustered.")

    # 2. ノードの配置 (今日のトピックノードの追加・配置)
    todays_topics_map = {t.get("topic_id"): t for t in todays_topics}

    # cluster_actionsを適用した後の既知クラスタ集合。node_placementsが参照する
    # cluster_idがここに無い場合(LLMがcluster_actions側のcreateを出し忘れた等)、
    # ノードだけが宙に浮いたクラスタ参照を持つことになり、フロントの力学
    # シミュレーションがそのノードを配置できずクラッシュする(cluster_map_view側は
    # `clusters`に無いcluster_idのノードを一切ケアしない前提で書かれているため)。
    # edge_actions/ghost_node_actionsと同じ「情報は失わずフォールバックする」方針で、
    # 参照先クラスタが無ければその場で作ってしまう。
    known_cluster_ids = {c.get("cluster_id") for c in new_graph.get("clusters", [])}

    node_placements = mutations.get("node_placements", [])
    for placement in node_placements:
        topic_id = placement.get("topic_id")
        cluster_id = placement.get("cluster_id")
        if not topic_id:
            continue

        if cluster_id is not None and cluster_id not in known_cluster_ids:
            _log(
                f"⚠️ Topic Mapping referenced an unknown cluster_id in node_placements "
                f"({cluster_id}): auto-creating a fallback cluster so the node isn't orphaned."
            )
            new_graph.setdefault("clusters", []).append({
                "cluster_id": cluster_id,
                "name": cluster_id,
            })
            known_cluster_ids.add(cluster_id)

        if "nodes" not in new_graph:
            new_graph["nodes"] = []

        existing_node = next((n for n in new_graph["nodes"] if n.get("topic_id") == topic_id), None)

        if existing_node:
            existing_node["cluster_id"] = cluster_id
        else:
            topic_info = todays_topics_map.get(topic_id, {})
            if not topic_info:
                # todays_topicsに無いtopic_id（ハルシネーションの可能性）。
                # ノード自体は情報を失わないよう保存するが、タイトルはtopic_idを
                # そのまま出すフォールバックになるため、後で気づけるようログに残す。
                _log(f"⚠️ Topic Mapping referenced an unknown topic_id in node_placements: {topic_id}")
            new_graph["nodes"].append({
                "topic_id": topic_id,
                "title": topic_info.get("title", f"Topic {topic_id}"),
                "cluster_id": cluster_id,
                "topic_type": topic_info.get("topic_type", "ACADEMIC"),
                "source_lecture_id": topic_info.get("source_lecture_id"),
                "topic_index_in_lecture": topic_info.get("topic_index_in_lecture")
            })

    # 3. エッジのアクション (add / remove)
    # add時は、source/targetが実在するノードかどうかを検証する。存在しないノードを
    # 参照するエッジは繋ぎようがない（宙に浮いた線になる）ため、そのエッジだけを
    # 無視する。ノードやクラスターなど他の情報はここでは一切失われない。
    known_node_ids = {n.get("topic_id") for n in new_graph.get("nodes", [])}

    edge_actions = mutations.get("edge_actions", [])
    for action_item in edge_actions:
        action = action_item.get("action")
        source_id = action_item.get("source_id")
        target_id = action_item.get("target_id")
        relation_type = action_item.get("relation_type", "builds_on")
        if not source_id or not target_id:
            continue

        if "edges" not in new_graph:
            new_graph["edges"] = []

        if action == "add":
            if source_id not in known_node_ids or target_id not in known_node_ids:
                _log(
                    f"⚠️ Skipped edge referencing a non-existent node "
                    f"(source={source_id}, target={target_id}): could not be connected."
                )
                continue
            if not any(
                e.get("source_id") == source_id and e.get("target_id") == target_id
                for e in new_graph["edges"]
            ):
                new_graph["edges"].append({
                    "source_id": source_id,
                    "target_id": target_id,
                    "relation_type": relation_type
                })
        elif action == "remove":
            new_graph["edges"] = [
                e for e in new_graph["edges"]
                if not (e.get("source_id") == source_id and e.get("target_id") == target_id)
            ]

    # 4. ゴーストノードのアクション (create / resolve / remove)
    ghost_actions = mutations.get("ghost_node_actions", [])
    for action_item in ghost_actions:
        action = action_item.get("action")
        ghost_id = action_item.get("ghost_id")
        name = action_item.get("name")
        cluster_id = action_item.get("cluster_id")
        
        if not ghost_id:
            continue
            
        if "ghost_nodes" not in new_graph:
            new_graph["ghost_nodes"] = []
            
        if action == "create":
            derived_from_topic_id = action_item.get("derived_from_topic_id")
            if derived_from_topic_id not in known_node_ids:
                _log(
                    f"⚠️ Ghost node '{ghost_id}' referenced a non-existent "
                    f"derived_from_topic_id ({derived_from_topic_id}): storing as null."
                )
                derived_from_topic_id = None
            if cluster_id is not None and cluster_id not in known_cluster_ids:
                # node_placementsと同じフォールバック: 参照先クラスタが無ければ
                # その場で作る(ghost_nodeのcluster_idはこれまで一切検証されて
                # いなかった)。
                _log(
                    f"⚠️ Ghost node '{ghost_id}' referenced an unknown cluster_id "
                    f"({cluster_id}): auto-creating a fallback cluster so it isn't orphaned."
                )
                new_graph.setdefault("clusters", []).append({
                    "cluster_id": cluster_id,
                    "name": cluster_id,
                })
                known_cluster_ids.add(cluster_id)
            if not any(g.get("ghost_id") == ghost_id for g in new_graph["ghost_nodes"]):
                new_graph["ghost_nodes"].append({
                    "ghost_id": ghost_id,
                    "name": name,
                    "cluster_id": cluster_id,
                    "derived_from_topic_id": derived_from_topic_id
                })
        elif action in ("resolve", "remove"):
            new_graph["ghost_nodes"] = [g for g in new_graph["ghost_nodes"] if g.get("ghost_id") != ghost_id]
        
    return new_graph


_UNKNOWN_RECORDING_LANGUAGE_LABEL = "the same language as the original spoken audio (do not translate under any circumstances)"


def _find_previous_lecture_id_sync(supabase, course_id: str | None, created_at: str | None) -> str | None:
    """
    同じcourse_id内で、created_atより古く・最新の(=直前の)Lecture IDを返す。
    削除済みLectureは対象外。course_id/created_atが無ければ判定不能としてNone。
    """
    if not course_id or not created_at:
        return None
    prev_res = supabase.table("lectures")\
        .select("id")\
        .eq("course_id", course_id)\
        .is_("deleted_at", "null")\
        .lt("created_at", created_at)\
        .order("created_at", desc=True)\
        .limit(1)\
        .execute()
    return prev_res.data[0]["id"] if prev_res.data else None


def _get_previous_lecture_id(lecture_id: str) -> str | None:
    """lecture_idだけから、直前のLecture IDを引く(course_id/created_atの取得込み)。"""
    supabase = get_supabase_client()
    lec_res = supabase.table("lectures").select("course_id, created_at").eq("id", lecture_id).single().execute()
    if not lec_res.data:
        return None
    return _find_previous_lecture_id_sync(supabase, lec_res.data.get("course_id"), lec_res.data.get("created_at"))


def _get_previous_lecture_topics(lecture_id: str) -> list[dict]:
    """
    直前講義の lecture_topics (ACADEMICのみ、削除済み除く) を index 順で返す。
    直前講義が無い/まだ lecture_topics が書き込まれていない(DETAIL_CONTENTS_GENERATION
    未到達)場合は空リスト。呼び出し側はこれを「無理に埋めない」判断に使う。
    """
    prev_lecture_id = _get_previous_lecture_id(lecture_id)
    if not prev_lecture_id:
        return []
    supabase = get_supabase_client()
    res = supabase.table("lecture_topics").select("topic_title, summary")\
        .eq("lecture_id", prev_lecture_id)\
        .eq("topic_type", "ACADEMIC")\
        .is_("deleted_at", "null")\
        .order("index")\
        .execute()
    return res.data or []


def _get_sentence_review_context(lecture_id: str) -> tuple[str, str, str]:
    """
    Sentence Review タスク用に、コースタイトル・直前講義のキーワード一覧・
    録音言語(プロンプト埋め込み用に解決済みの文字列)を取得します。
    """
    supabase = get_supabase_client()

    # 1. 今回の講義の course_id と created_at と recording_language を取得
    lec_res = supabase.table("lectures").select("course_id, created_at, recording_language").eq("id", lecture_id).single().execute()
    if not lec_res.data:
        return "University Lecture", "", _UNKNOWN_RECORDING_LANGUAGE_LABEL

    course_id = lec_res.data.get("course_id")
    created_at = lec_res.data.get("created_at")
    # 未設定(Whisperの自動言語判定に任せた講義)ならプロンプトにそのまま埋め込める
    # フォールバック文言にしておく(nullをそのままformatに渡せないため)。
    recording_language = lec_res.data.get("recording_language") or _UNKNOWN_RECORDING_LANGUAGE_LABEL

    # 2. courses から course_title を取得
    course_title = "University Lecture"
    if course_id:
        course_res = supabase.table("courses").select("course_title").eq("id", course_id).single().execute()
        if course_res.data and course_res.data.get("course_title"):
            course_title = course_res.data["course_title"]

    # 3. 直前の講義（同じ course_id 内で今回の講義より古く、最新のもの）の ID を取得
    prev_lecture_id = _find_previous_lecture_id_sync(supabase, course_id, created_at)

    # 4. 直前講義のキーワード一覧を取得
    keywords_list = ""
    if prev_lecture_id:
        kw_res = supabase.table("keywords")\
            .select("keyword")\
            .eq("lecture_id", prev_lecture_id)\
            .execute()
        if kw_res.data:
            keywords = [item["keyword"] for item in kw_res.data if item.get("keyword")]
            keywords_list = ", ".join(keywords)

    return course_title, keywords_list, recording_language


# user_interface/lib/domain/entities/app_language.dart の言語コードと対応させる。
_LANGUAGE_CODE_TO_NAME = {
    "en": "English",
    "ja": "Japanese",
    "fr": "French",
    "es": "Spanish",
    "de": "German",
    "zh": "Chinese",
    "yue": "Cantonese",
    "ko": "Korean",
    "pt": "Portuguese",
    "it": "Italian",
    "ru": "Russian",
    "ar": "Arabic",
    "hi": "Hindi",
}


def _resolve_language_name(code: str | None) -> str | None:
    if not code:
        return None
    return _LANGUAGE_CODE_TO_NAME.get(code, code)


def _majority_detected_language(supabase, lecture_id: str) -> str | None:
    """
    リアルタイム講義の実際のトランスクリプト言語を、チャンクごとに保存された
    lecture_transcripts.detected_languageの多数決で解決する。1チャンクだけ誤検出
    しても(短い/ノイズの多いチャンクでは起こり得る)講義全体の判定がブレないように、
    最頻値を採用する。
    """
    rows_res = supabase.table("lecture_transcripts")\
        .select("detected_language")\
        .eq("lecture_id", lecture_id)\
        .execute()
    codes = [r["detected_language"] for r in (rows_res.data or []) if r.get("detected_language")]
    if not codes:
        return None
    return Counter(codes).most_common(1)[0][0]


def _get_content_language_context(lecture_id: str) -> tuple[str, str, bool]:
    """
    コンテンツ生成タスク(Core Extraction, Review Cards, Deep Notesなど)向けに、
    「何語で書くか(content_language)」と「トランスクリプトの原語(transcript_language)」
    を解決します。

    - content_language: lectures.display_language が優先。無ければ後述の
      transcript_languageにフォールバックする(Flutter側 app_database.dart の
      コメント通りの設計)。
    - transcript_language: 実際にWhisperが検出した言語を優先する
      (lectures.detected_recording_language、無ければ
      lecture_transcriptsの多数決)。ユーザーが選んだ(または選ばなかった)
      recording_languageは、実際の音声内容と食い違うことがある
      (選択ミス、日英混在の授業、録音言語「自動判定」など)ため、
      あくまで検出結果が無い場合の最終フォールバックとしてのみ使う。
    - is_bilingual: 表示言語と実際のトランスクリプト言語が異なり、
      専門用語の原語併記が必要なケースかどうか。
    """
    supabase = get_supabase_client()

    lec_res = supabase.table("lectures")\
        .select("recording_language, display_language, detected_recording_language")\
        .eq("id", lecture_id).single().execute()
    if not lec_res.data:
        return "English", "English", False

    display_code = lec_res.data.get("display_language")

    # 実際に検出された言語を優先する。プレレコはlectures側に1値、
    # リアルタイムはlecture_transcripts側にチャンクごとの値がある。
    detected_code = lec_res.data.get("detected_recording_language")
    if not detected_code:
        detected_code = _majority_detected_language(supabase, lecture_id)

    # 検出結果がまだ無い(文字起こし前、または取得失敗)場合のみ、
    # ユーザーが選んだrecording_languageにフォールバックする。
    transcript_code = detected_code or lec_res.data.get("recording_language")

    transcript_language = _resolve_language_name(transcript_code) or "English"
    content_language = _resolve_language_name(display_code) or transcript_language

    is_bilingual = bool(transcript_code) and bool(display_code) and transcript_code != display_code

    return content_language, transcript_language, is_bilingual


def _build_language_instruction(content_language: str) -> str:
    """announcement/topic mapping系のような、原語併記が不要な単純な出力言語指示。"""
    return f"Write all output text in {content_language}."


def _build_bilingual_gloss_instruction(
    content_language: str, transcript_language: str, is_bilingual: bool
) -> str:
    """
    Core Extraction/Review Cards/Deep Notesのように、専門用語をトランスクリプトの
    原語から抽出しつつ出力自体は表示言語で書く必要があるタスク向けの言語指示。
    表示言語と録音言語が同じ場合は原語併記ルールを省き、無駄な指示でプロンプトを
    汚さないようにする。
    """
    base = f"Write all output text in {content_language}."
    if not is_bilingual:
        return base
    return (
        f"{base} The source transcript is in {transcript_language}, which is a "
        f"different language from {content_language}. For any technical term, "
        f"keyword, or jargon that a student would want to recognize in its "
        f"original form, write it in {content_language} first and then include "
        f"the original {transcript_language} term in parentheses on first "
        f"mention (e.g. \"Address Translation (アドレス変換)\"). Do not do this "
        f"for every word — only for genuine technical/academic terms, not for "
        f"ordinary sentence content."
    )


def _get_student_profile(uid: str) -> str:
    """
    user_profiles から学生のプロフィール情報を取得し、LLMに渡すコンテキスト文字列を構築します。
    """
    supabase = get_supabase_client()
    try:
        res = supabase.table("user_profiles").select("profile, interests, future_goals").eq("id", uid).single().execute()
        if not res.data:
            return "A university student majoring in Computer Science interested in software engineering."
            
        p_text = res.data.get("profile") or ""
        i_text = res.data.get("interests") or ""
        g_text = res.data.get("future_goals") or ""
        
        parts = []
        if p_text:
            parts.append(p_text)
        if i_text:
            parts.append(f"Interests: {i_text}")
        if g_text:
            parts.append(f"Future Goals: {g_text}")
            
        if not parts:
            return "A university student majoring in Computer Science interested in software engineering."
            
        return " ".join(parts)
    except Exception:
        # DBエラー時の安全なフォールバック
        return "A university student majoring in Computer Science interested in software engineering."