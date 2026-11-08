"""Post-process a graphify extraction to repair two Dart extractor issues.

1. `_` collisions: a Dart parameter named `_` normalizes to an empty entity, so
   its node id is either "" or the enclosing file's id. When it collides with the
   file node, the file's label is overwritten with "_". We drop those `_`/empty
   nodes, edges touching an empty id, and the self-loops they produce.
2. Unresolved Riverpod providers: references to `fooProvider` point either at a
   bare id (`fooprovider`) or at a sourceless placeholder (`none_fooprovider`).
   When exactly one real node (with a source_file) carries that label, we rewire
   the edge to it and drop the placeholder.

Usage (from the repo root):
  $(cat graphify-out/.graphify_python) tools/graphify/postprocess_dart.py graphify-out/.graphify_extract.json [--write]
Without --write it only prints what would change (dry run). Running it twice is
safe: a second run finds nothing to change.

Healthy result after --write: `underscore_nodes_dropped` items are gone and
`provider_edges_still_dangling: 0`.
"""
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path


def norm(label: str) -> str:
    return (label or "").lower().rstrip("()")


def run(path: Path, write: bool) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    nodes, edges = data["nodes"], data["edges"]
    stats = Counter()

    # --- 1. `_` collisions -------------------------------------------------
    bad_ids = set()
    kept_nodes = []
    for n in nodes:
        if n.get("label") in ("_", "") or n.get("id") == "":
            stats["underscore_nodes_dropped"] += 1
            if n.get("id") == "":
                bad_ids.add("")
            continue
        kept_nodes.append(n)
    nodes = kept_nodes

    # --- 2. Provider resolution -------------------------------------------
    real_by_label = defaultdict(list)
    for n in nodes:
        if n.get("source_file") and not n["id"].startswith("none_"):
            real_by_label[norm(n.get("label"))].append(n["id"])
    ids = {n["id"] for n in nodes}

    def resolve(node_id: str):
        key = node_id[5:] if node_id.startswith("none_") else node_id
        if not key.endswith("provider"):
            return None
        cands = real_by_label.get(key, [])
        return cands[0] if len(cands) == 1 else None

    redirect = {}
    for n in nodes:
        if n["id"].startswith("none_") and n["id"].endswith("provider"):
            target = resolve(n["id"])
            if target:
                redirect[n["id"]] = target
            else:
                stats["placeholder_unresolved"] += 1

    new_edges = []
    for e in edges:
        s, t = e["source"], e["target"]
        if s in bad_ids or t in bad_ids:
            stats["edges_to_empty_id_dropped"] += 1
            continue
        changed = False
        for end in ("source", "target"):
            v = e[end]
            if v in redirect:
                e[end] = redirect[v]
                changed = True
            elif v not in ids:
                r = resolve(v)
                if r:
                    e[end] = r
                    changed = True
        if changed:
            stats["provider_edges_rewired"] += 1
            e["confidence"] = "INFERRED"
            e["confidence_score"] = 0.95
            e["_postprocess"] = "provider_resolution"
        if e["source"] == e["target"] and e.get("relation") == "defines":
            stats["defines_self_loops_dropped"] += 1
            continue
        new_edges.append(e)

    before = len(nodes)
    nodes = [n for n in nodes if n["id"] not in redirect]
    stats["placeholder_nodes_merged"] = before - len(nodes)

    ids = {n["id"] for n in nodes}
    remaining = Counter(
        (e["target"] if e["target"] not in ids else e["source"])
        for e in new_edges
        if (e["source"] not in ids or e["target"] not in ids)
        and str(e.get("source_file") or "").endswith(".dart")
        and (e["target"].endswith("provider") or e["source"].endswith("provider"))
    )
    stats["provider_edges_still_dangling"] = sum(remaining.values())

    for k, v in stats.items():
        print(f"{k}: {v}")
    if remaining:
        print("still dangling providers:", remaining.most_common(10))

    if write:
        data["nodes"], data["edges"] = nodes, new_edges
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"written: {len(nodes)} nodes, {len(new_edges)} edges")
    else:
        print("dry run - nothing written")


if __name__ == "__main__":
    run(Path(sys.argv[1]), "--write" in sys.argv[2:])
