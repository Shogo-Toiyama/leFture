import re
import json
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict, Any

from app.core.config import PROMPTS_DIR

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

def _load_prompt(filename: str) -> str:
    prompt_path = PROMPTS_DIR / filename
    if not prompt_path.exists():
        raise FileNotFoundError(f"Prompt file not found: {filename}")
        
    return prompt_path.read_text(encoding="utf-8")


def _sid_to_int(sid: Optional[str]) -> Optional[int]:
    SID_NUM = re.compile(r"s(\d+)")
    if not sid:
        return None
    m = SID_NUM.fullmatch(sid)
    return int(m.group(1)) if m else None


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
    - summary: タイトル(H1)のすぐ下にある1-3文のミニサマリー
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

    # H1 の次の行からスキャン開始
    in_summary = False
    for i in range(title_idx + 1, len(lines)):
        line = lines[i]
        stripped = line.strip()

        # 次の見出し (## または #) が来たらサマリー区切り
        if stripped.startswith('##') or stripped.startswith('# '):
            content_start_idx = i
            break

        if stripped:
            in_summary = True
            summary_lines.append(line)
        else:
            # 空行だった場合
            if in_summary:
                # すでにサマリー読み込み中で次の非空行が見出し(##)なら、そこでサマリー終了
                next_non_empty = ""
                next_non_empty_idx = -1
                for j in range(i + 1, len(lines)):
                    if lines[j].strip():
                        next_non_empty = lines[j].strip()
                        next_non_empty_idx = j
                        break
                if next_non_empty.startswith('##') or next_non_empty.startswith('# '):
                    content_start_idx = next_non_empty_idx
                    break
                else:
                    # 見出しでなければ改行としてサマリーに含める
                    summary_lines.append(line)

    summary = "\n".join(summary_lines).strip()

    # コンテンツ本体の切り出し
    if content_start_idx != -1:
        clean_contents = "\n".join(lines[content_start_idx:]).strip()
    else:
        remaining_lines = lines[title_idx + 1 + len(summary_lines):]
        clean_contents = "\n".join(remaining_lines).strip()

    return summary, clean_contents


def _merge_graph_mutation(current_graph: dict, mutations: dict, todays_topics: list[dict]) -> dict:
    """
    Topic Mapping (LLM) から出力された差分(mutations)を、
    現在の Full Map 状態(current_graph)に適用し、最新の Full Map 状態を返します。
    """
    import copy
    new_graph = copy.deepcopy(current_graph)
    
    # 1. クラスターのアクション (create / rename / remove)
    cluster_actions = mutations.get("cluster_actions", [])
    for action_item in cluster_actions:
        action = action_item.get("action")
        cluster_id = action_item.get("cluster_id")
        name = action_item.get("name")
        if not cluster_id:
            continue
            
        if action == "create":
            if not any(c.get("id") == cluster_id for c in new_graph.get("clusters", [])):
                if "clusters" not in new_graph:
                    new_graph["clusters"] = []
                new_graph["clusters"].append({
                    "id": cluster_id,
                    "name": name
                })
        elif action == "rename":
            for c in new_graph.get("clusters", []):
                if c.get("id") == cluster_id:
                    c["name"] = name
                    break
        elif action == "remove":
            new_graph["clusters"] = [c for c in new_graph.get("clusters", []) if c.get("id") != cluster_id]

    # 2. ノードの配置 (今日のトピックノードの追加・配置)
    todays_topics_map = {t.get("topic_id"): t for t in todays_topics}
    
    node_placements = mutations.get("node_placements", [])
    for placement in node_placements:
        topic_id = placement.get("topic_id")
        cluster_id = placement.get("cluster_id")
        if not topic_id:
            continue
            
        if "nodes" not in new_graph:
            new_graph["nodes"] = []
            
        existing_node = next((n for n in new_graph["nodes"] if n.get("id") == topic_id), None)
        
        if existing_node:
            existing_node["cluster_id"] = cluster_id
        else:
            topic_info = todays_topics_map.get(topic_id, {})
            new_graph["nodes"].append({
                "id": topic_id,
                "title": topic_info.get("title", f"Topic {topic_id}"),
                "cluster_id": cluster_id,
                "topic_type": topic_info.get("topic_type", "ACADEMIC")
            })

    # 3. エッジのアクション (add / remove)
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
            if not any(e.get("source") == source_id and e.get("target") == target_id for e in new_graph["edges"]):
                new_graph["edges"].append({
                    "source": source_id,
                    "target": target_id,
                    "relation_type": relation_type
                })
        elif action == "remove":
            new_graph["edges"] = [
                e for e in new_graph["edges"] 
                if not (e.get("source") == source_id and e.get("target") == target_id)
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
            if not any(g.get("id") == ghost_id for g in new_graph["ghost_nodes"]):
                new_graph["ghost_nodes"].append({
                    "id": ghost_id,
                    "name": name,
                    "cluster_id": cluster_id
                })
        elif action in ("resolve", "remove"):
            new_graph["ghost_nodes"] = [g for g in new_graph["ghost_nodes"] if g.get("id") != ghost_id]
        
    return new_graph