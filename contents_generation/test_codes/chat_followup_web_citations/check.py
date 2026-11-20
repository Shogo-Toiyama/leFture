"""Dry-run citation handoff with synthetic rows or read-only Supabase data."""

import argparse
import ast
import asyncio
from copy import deepcopy
import json
from pathlib import Path
import sys
from time import perf_counter
from types import ModuleType, SimpleNamespace
from typing import Optional
from urllib.parse import urlencode
from urllib.request import Request, urlopen


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SERVICES = ROOT / "lefture_backend" / "app" / "services"


def load_functions(path, names, namespace):
    tree = ast.parse(path.read_text())
    selected = [node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
                and node.name in names]
    exec(compile(ast.Module(body=selected, type_ignores=[]), str(path), "exec"), namespace)


def load_backend(directory):
    # The experiment needs the backend's actual estimate and citation code, without provider SDKs.
    sys.path.insert(0, str(ROOT / "lefture_backend"))
    attachments = ModuleType("app.services.chat_attachments")
    load_functions(SERVICES / "chat_attachments.py", {"estimate_tokens"}, vars(attachments))
    sys.modules[attachments.__name__] = attachments
    materials = ModuleType("app.services.chat_materials")
    sys.modules[materials.__name__] = materials
    path = directory / "chat_materials.py"
    exec(compile(path.read_text(), str(path), "exec"), vars(materials))
    namespace = {"asyncio": asyncio, "Optional": Optional}
    load_functions(directory / "chat_service.py",
                   {"_previous_completed_reply", "_fetch_previous_citations", "_previous_turn_refs"}, namespace)
    return materials, SimpleNamespace(**namespace)


class MessageQuery:
    def __init__(self, records):
        self.records = records
        self.filters = {}

    def table(self, table):
        assert table == "chat_messages"
        return self

    def select(self, columns):
        assert columns == "citations"
        return self

    def eq(self, key, value):
        self.filters[key] = value
        return self

    def is_(self, key, value):
        assert key == "deleted_at" and value == "null"
        self.filters[key] = None
        return self

    def limit(self, count):
        assert count == 1
        return self

    def execute(self):
        rows = [row for row in self.records if all(row.get(key) == value for key, value in self.filters.items())]
        return SimpleNamespace(data=[{"citations": row["citations"]} for row in rows[:1]])


def synthetic_cases(materials, backend):
    citation = {
        "source_type": "web",
        "url": "https://example.org/article",
        "label": "An article",
        "metadata": {"domain": "example.org"},
        "snippet": "A different section of the article.",
        "passages": {"4": {"text": "The quoted text supplies evidence for the claim."}},
    }
    history = [
        {"role": "assistant", "status": "complete", "id": "prior"},
        {"role": "assistant", "status": "stopped", "id": "stopped"},
        {"role": "user", "status": "complete", "id": "student"},
    ]
    db = MessageQuery([{"id": "prior", "thread_id": "thread", "citations": [citation]}])
    result = asyncio.run(backend._fetch_previous_citations(db, "thread", history))
    assert result == [citation]
    assert not asyncio.run(backend._fetch_previous_citations(db, "another-thread", history))
    assert not asyncio.run(backend._fetch_previous_citations(db, "thread", []))
    assert not asyncio.run(backend._fetch_previous_citations(
        MessageQuery([{**db.records[0], "deleted_at": "yesterday"}]), "thread", history))
    carried = materials.previous_web_materials(result, [])
    assert carried[0].content == citation["passages"]["4"]["text"]
    assert "previous reply" in materials.format_sources_block(carried)
    assert "‹W1.1›" in materials.format_sources_block(carried)
    extracted = materials.extract_citations("Answer. ⟦W1.1⟧", carried)
    assert extracted[0]["url"] == citation["url"]
    assert extracted[0]["metadata"] == citation["metadata"]
    assert extracted[0]["passages"]["1"]["text"] == carried[0].content
    assert materials.previous_web_materials(extracted, [carried[0]]) == []
    assert len(materials.previous_web_materials([citation, citation], [])) == 1
    assert materials.previous_web_materials([{**citation, "source_type": "lecture_summary"}], []) == []
    assert materials.previous_web_materials([{**citation, "passages": {}}], [])[0].content == citation["snippet"]
    assert materials.previous_web_materials([None, {"source_type": "web"}], []) == []
    large = [{**deepcopy(citation), "url": f"https://example.org/{index}", "passages": {
        "1": {"text": "同" * 900},
    }} for index in range(12)]
    bounded = materials.previous_web_materials(large, [])
    assert 1 <= len(bounded) <= materials.PREVIOUS_WEB_MAX_ITEMS
    assert materials.estimate_tokens(materials.format_sources_block(bounded)) <= materials.PREVIOUS_WEB_MAX_TOKENS
    fresh = materials.Material("current", "web", "Fresh", "Newer article.", url="https://example.org/fresh")
    assert "[W2] An article" in materials.format_sources_block([fresh, *carried])


def live_cases(materials, title, last_message_at, followup_text):
    env = {}
    for line in (ROOT / "lefture_backend" / ".env").read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            name, value = line.split("=", 1)
            env[name.strip()] = value.strip().strip("'\"")
    base = env["SUPABASE_URL"].rstrip("/") + "/rest/v1/"
    key = env["SUPABASE_SECRET_KEY"]

    def get(table, **params):
        request = Request(base + table + "?" + urlencode(params),
                          headers={"apikey": key, "Authorization": f"Bearer {key}"})
        with urlopen(request, timeout=20) as response:
            return json.load(response)

    threads = get("chat_threads", select="id", title="eq." + title,
                  last_message_at="eq." + last_message_at, limit=2)
    assert len(threads) == 1
    rows = get("chat_messages", select="role,content,status,citations", thread_id="eq." + threads[0]["id"],
               deleted_at="is.null", order="created_at.asc", limit=30)
    followup = next(index for index, row in enumerate(rows)
                    if row["role"] == "user" and followup_text in row["content"])
    for name, index in (("initial web reply", followup - 1), ("researched reply", followup + 3)):
        citations = rows[index]["citations"]
        started = perf_counter()
        carried = materials.previous_web_materials(citations, [])
        block = materials.format_sources_block(carried)
        elapsed_ms = (perf_counter() - started) * 1000
        assert carried and len(carried) <= materials.PREVIOUS_WEB_MAX_ITEMS
        assert "Waymo" in block
        assert materials.estimate_tokens(block) <= materials.PREVIOUS_WEB_MAX_TOKENS
        print(json.dumps({"case": name, "web_sources": len(carried), "estimated_prompt_tokens":
                          materials.estimate_tokens(block), "local_ms": round(elapsed_ms, 3)}))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", action="store_true")
    parser.add_argument("--live", nargs=3, metavar=("THREAD_TITLE", "LAST_MESSAGE_AT", "FOLLOWUP_TEXT"))
    args = parser.parse_args()
    materials, backend = load_backend(HERE / "patched" if args.candidate else SERVICES)
    synthetic_cases(materials, backend)
    print("Synthetic dry-run passed.")
    if args.live:
        live_cases(materials, *args.live)


if __name__ == "__main__":
    main()
