---
name: todo
description: Add, list or complete items on the developer's private TODO list (things to do later). Use when the user runs /todo or says to remember something as a TODO / "あとでやる".
argument-hint: "[text to add] | list | done <number>"
---

The TODO list lives outside the repo (it is private, the repo is public):
`~/.claude/projects/-Users-shogo-Documents-Programming-leFture/memory/todo.md`

Read that file first, then act on the arguments: `$ARGUMENTS`

- **No arguments or `list`**: show the Open items as a short numbered list (title only, one line each). Do not change the file.
- **`done <number>`** (or "N終わった" etc.): move that item from Open to Done, prefix it with today's date, and renumber Open.
- **Anything else**: it is a new item. Append it to Open as
  `N. **[area] short title** (added YYYY-MM-DD)` with one or two sub-bullets only if the user gave details or the current conversation has useful context (file names, IDs, what was observed). Pick `area` from what it touches (e.g. billing, pipeline, chat, notes, webapp, app, infra). Do not investigate or start the work.

Keep it simple: no priorities, no extra sections. Write entries in English (same as other memory files), reply to the user in Japanese with just what changed and the current open count.
