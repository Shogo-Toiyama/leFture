#!/usr/bin/env python3
"""Check experiment files for other people's data before committing them.

This repo is public. Experiment results may be committed, but only data that
belongs to the users in allowlist.json. Everything else must be removed:

- IDs only (a user ID, a RevenueCat customer, a lecture ID with no content):
  run with --redact. Each such UUID becomes `redacted-<kind>-<hash8>`, which
  stays stable across files and runs, so cross-references still line up.
- Content (lecture text, chat messages, titles, topic names): this cannot be
  redacted automatically. Write a summary that keeps the metrics and the
  conclusion, move the raw file to the private repo, and add its path to
  .gitignore.

Usage (stdlib only; reads SUPABASE_URL / SUPABASE_SECRET_KEY from
lefture_backend/.env):

    python3 tools/experiment_privacy/check_results.py            # new/staged files
    python3 tools/experiment_privacy/check_results.py PATH...    # files or dirs
    python3 tools/experiment_privacy/check_results.py --redact PATH...

Exit code 0 means nothing left to fix. 1 means something needs action.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ALLOWLIST = os.path.join(os.path.dirname(__file__), "allowlist.json")
TEXT_EXT = {".json", ".md", ".txt", ".log", ".html", ".csv", ".py", ".dart", ".yaml", ".yml"}

UUID_RE = re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b")
NIL_UUID = "00000000-0000-0000-0000-000000000000"
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
SECRET_RE = re.compile(
    r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"  # JWT
    r"|sk-ant-[A-Za-z0-9_-]{10,}|sk-[A-Za-z0-9]{20,}|sb_secret_[A-Za-z0-9_]+"
    r"|X-Amz-Signature=[0-9a-f]+|[?&]token=[A-Za-z0-9._-]{10,}"
)

# Tables whose rows are content (their IDs in a file usually come with text).
CONTENT_TABLES = {"lectures", "courses", "chat_threads", "chat_messages", "chat_attachments",
                  "knowledge_chunks", "lecture_topics"}


def load_env() -> tuple[str, str]:
    env = {}
    with open(os.path.join(ROOT, "lefture_backend", ".env"), encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip().strip('"').strip("'")
    return env["SUPABASE_URL"], env["SUPABASE_SECRET_KEY"]


class Supabase:
    def __init__(self) -> None:
        self.url, self.key = load_env()

    def _get(self, path: str):
        req = urllib.request.Request(f"{self.url}{path}",
                                     headers={"apikey": self.key, "Authorization": f"Bearer {self.key}"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            raise

    def rows(self, table: str, select: str, column: str, values: list[str]) -> list[dict]:
        out = []
        for i in range(0, len(values), 40):
            chunk = values[i:i + 40]
            q = urllib.parse.quote("(" + ",".join(chunk) + ")")
            out += self._get(f"/rest/v1/{table}?select={select}&{column}=in.{q}") or []
        return out

    def is_auth_user(self, uid: str) -> bool:
        r = self._get(f"/auth/v1/admin/users/{uid}")
        return isinstance(r, dict) and r.get("id") == uid


def resolve_owners(db: Supabase, ids: set[str]) -> dict[str, tuple[str, str | None]]:
    """uuid -> (kind, owner user_id or None if unknown)."""
    ids_l = sorted(ids)
    found: dict[str, tuple[str, str | None]] = {}
    for table in ("lectures", "courses", "chat_threads", "chat_attachments", "knowledge_chunks"):
        for r in db.rows(table, "id,user_id", "id", ids_l):
            found[r["id"]] = (table, r["user_id"])
    msgs = db.rows("chat_messages", "id,thread_id", "id", [i for i in ids_l if i not in found])
    threads = {r["id"]: r["user_id"] for r in
               db.rows("chat_threads", "id,user_id", "id", sorted({m["thread_id"] for m in msgs}))}
    for m in msgs:
        found[m["id"]] = ("chat_messages", threads.get(m["thread_id"]))
    topics = db.rows("lecture_topics", "id,lecture_id", "id", [i for i in ids_l if i not in found])
    lects = {r["id"]: r["user_id"] for r in
             db.rows("lectures", "id,user_id", "id", sorted({t["lecture_id"] for t in topics}))}
    for t in topics:
        found[t["id"]] = ("lecture_topics", lects.get(t["lecture_id"]))
    for uid in ids_l:
        if uid not in found and db.is_auth_user(uid):
            found[uid] = ("user", uid)
    return found


NEEDLE_MIN_LEN = 12


def _titles(db: Supabase, uid: str) -> dict[str, str]:
    """Lecture titles and topic names of one user (course names are too generic:
    every user has the same default course, and names like 'Machine Learning'
    show up in anyone's lecture text)."""
    out: dict[str, str] = {}
    lectures = db._get(f"/rest/v1/lectures?select=id,title,title_generated&user_id=eq.{uid}&limit=1000") or []
    for l in lectures:
        for k in ("title", "title_generated"):
            if l.get(k):
                out[l[k]] = "lecture title"
    for t in db.rows("lecture_topics", "topic_title", "lecture_id", [l["id"] for l in lectures]):
        if t.get("topic_title"):
            out[t["topic_title"]] = "topic name"
    return out


def content_needles(db: Supabase, owners: set[str], allowed: set[str]) -> dict[str, str]:
    """Distinctive strings of non-allowlisted users' content, minus anything that
    allowlisted users also have (those would be false positives)."""
    if not owners:
        return {}
    mine: set[str] = set()
    for uid in allowed:
        mine |= set(_titles(db, uid))
    needles: dict[str, str] = {}
    for uid in sorted(owners):
        for text, kind in _titles(db, uid).items():
            if len(text) >= NEEDLE_MIN_LEN and text not in mine:
                needles[text] = kind
    return needles


def target_files(paths: list[str]) -> list[str]:
    if not paths:
        out = subprocess.run(["git", "ls-files", "--others", "--exclude-standard"], cwd=ROOT,
                             capture_output=True, text=True).stdout.split()
        out += subprocess.run(["git", "diff", "--cached", "--name-only", "--diff-filter=AM"], cwd=ROOT,
                              capture_output=True, text=True).stdout.split()
        paths = [os.path.join(ROOT, p) for p in out if p.startswith(("contents_generation/", "scratch/"))]
    files = []
    for p in paths:
        if os.path.isdir(p):
            files += [os.path.join(r, f) for r, _, fs in os.walk(p) for f in fs]
        elif os.path.isfile(p):
            files.append(p)
    return sorted({f for f in files if os.path.splitext(f)[1].lower() in TEXT_EXT})


def pseudonym(kind: str, uid: str) -> str:
    return f"redacted-{kind.rstrip('s')}-{hashlib.sha256(uid.encode()).hexdigest()[:8]}"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--redact", action="store_true", help="replace non-allowlisted IDs in place")
    args = ap.parse_args()

    allowed = {u["user_id"] for u in json.load(open(ALLOWLIST, encoding="utf-8"))["users"]}
    files = target_files(args.paths)
    if not files:
        print("No experiment files to check.")
        return 0
    texts = {f: open(f, encoding="utf-8", errors="replace").read() for f in files}

    db = Supabase()
    all_ids = set().union(*(set(UUID_RE.findall(t)) for t in texts.values())) - {NIL_UUID}
    owners = resolve_owners(db, all_ids)
    outsiders = {o for (_, o) in owners.values() if o and o not in allowed}
    needles = content_needles(db, outsiders, allowed)

    problems = 0
    for f, t in texts.items():
        rel = os.path.relpath(f, ROOT)
        ids_here = set(UUID_RE.findall(t)) - {NIL_UUID}
        foreign = {i: owners[i] for i in ids_here if i in owners and owners[i][1] not in allowed}
        unknown = sorted(i for i in ids_here if i not in owners)
        content_ids = sorted(i for i, (k, _) in foreign.items() if k in CONTENT_TABLES)
        matched = [n for n in needles if n in t]
        # One match can be a coincidence; two different titles/topics cannot.
        content_text = len(matched) >= 2
        emails = sorted(set(EMAIL_RE.findall(t)))
        secrets = SECRET_RE.findall(t)

        notes = []
        if content_ids or content_text:
            notes.append(f"CONTENT of non-allowlisted users ({len(content_ids)} object IDs, "
                         f"{len(matched)} of their titles/topics) -> summarize, move raw to the "
                         "private repo, add to .gitignore")
        elif matched:
            notes.append(f"1 title/topic of a non-allowlisted user ({needles[matched[0]]}) -> "
                         "probably a coincidence, check by hand")
        id_only = {i: k for i, (k, _) in foreign.items() if k not in CONTENT_TABLES}
        if id_only:
            if args.redact:
                for i, k in id_only.items():
                    t = t.replace(i, pseudonym(k, i))
                notes.append(f"redacted {len(id_only)} ID(s)")
            else:
                notes.append(f"{len(id_only)} non-allowlisted ID(s) -> run with --redact")
        if secrets:
            notes.append(f"{len(secrets)} secret-like string(s) -> remove by hand")
        if emails:
            notes.append(f"email(s) {emails} -> confirm they are public or yours")
        if unknown:
            notes.append(f"{len(unknown)} UUID(s) not found in the DB -> check by hand")

        if args.redact and id_only:
            with open(f, "w", encoding="utf-8") as out:
                out.write(t)
        blocking = (content_ids or content_text or secrets or (id_only and not args.redact))
        if notes:
            print(f"{'ACTION' if blocking else 'note  '}  {rel}")
            for n in notes:
                print(f"          - {n}")
        problems += bool(blocking)

    print(f"\nChecked {len(files)} file(s); {problems} need action.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
