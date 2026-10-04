"""
results/<tag>/*.json から、人が読むためのレポート(report.html)を作る。

実行:
  python generate_report.py               # results/ 直下
  python generate_report.py --tag smoke   # results/smoke/
"""

import argparse
import html
import json
from pathlib import Path

TEST_DIR = Path(__file__).resolve().parent

CSS = """
:root{--bg:#f7f5f0;--surface:#fff;--line:#e2ddd2;--text:#2b2620;--muted:#6e6558;--ok:#2e8a58;--ok-bg:rgba(46,138,88,.09);
--ng:#c2463b;--ng-bg:rgba(194,70,59,.08);--warn:#a86f00;--warn-bg:rgba(204,141,0,.10);--hid:#3d6aa3;--hid-bg:rgba(61,106,163,.07)}
@media (prefers-color-scheme: dark){:root{--bg:#111422;--surface:#171b2b;--line:rgba(255,255,255,.12);--text:#f2f2f2;--muted:#9aa4b2;
--ok:#5cc08a;--ok-bg:rgba(92,192,138,.12);--ng:#ef7d73;--ng-bg:rgba(239,125,115,.12);--warn:#ffb300;--warn-bg:rgba(255,179,0,.12);
--hid:#7ea7d8;--hid-bg:rgba(126,167,216,.10)}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px/1.7 'Hiragino Sans','Noto Sans JP',system-ui,sans-serif}
.wrap{max-width:1040px;margin:0 auto;padding:32px 20px 80px}h1{font-size:26px;margin:0 0 6px}h2{font-size:20px;margin:40px 0 6px}
h3{font-size:15px;margin:0}.muted{color:var(--muted)}code{font:12px ui-monospace,Menlo,monospace}
table{border-collapse:collapse;width:100%;font-size:13px}th,td{border-bottom:1px solid var(--line);padding:6px 8px;text-align:left;vertical-align:top}
th{color:var(--muted);font-weight:600}.tbl{overflow-x:auto;border:1px solid var(--line);border-radius:10px;background:var(--surface)}
.chip{display:inline-block;font-size:11.5px;padding:1px 8px;border-radius:999px;border:1px solid var(--line);color:var(--muted);margin-right:4px;white-space:nowrap}
.chip.ok{color:var(--ok);border-color:var(--ok);background:var(--ok-bg)}.chip.ng{color:var(--ng);border-color:var(--ng);background:var(--ng-bg)}
.chip.warn{color:var(--warn);border-color:var(--warn);background:var(--warn-bg)}
.ev{border:1px solid var(--line);border-radius:12px;background:var(--surface);padding:12px 14px;margin:10px 0}
.ev.thread{border-left:3px solid var(--hid)}.ev.consolidate{border-left:3px solid var(--ok)}.ev.cover{border-left:3px solid var(--warn)}
.ev.user_action{border-left:3px solid var(--ng)}
.obs{border:1px dashed var(--hid);background:var(--hid-bg);border-radius:8px;padding:6px 10px;margin:6px 0;font-size:13px}
.res{font-size:13px;margin:3px 0}.res.ng{color:var(--ng)}.res .n{color:var(--muted);font-size:12px}
details summary{cursor:pointer;color:var(--muted);font-size:12.5px}
.item{font-size:13px;padding:3px 0}.item .cat{color:var(--muted)}
"""


def esc(x) -> str:
    return html.escape("" if x is None else str(x))


def chips_summary(s: dict) -> str:
    def c(label, n, bad=True):
        cls = "ok" if n == 0 else ("ng" if bad else "warn")
        return f'<span class="chip {cls}">{label} {n}</span>'
    return (f'<span class="chip">passed {s["passed"]}/{s["total"]}</span>'
            + c("間違って上げた", s["false_promotions"]) + c("上げそこね", s["missed"])
            + c("観察の一般化", s["observation_violations"]) + c("観察の取りこぼし", s["observation_misses"])
            + c("機械チェック", s["mechanical_failures"]) + c("根拠の不足(警告)", s["evidence_warnings"], bad=False)
            + c("想定外の項目", s["unexplained_items"], bad=False))


def render_grades(grades: list[dict], event_id: str) -> str:
    out = []
    for g in grades:
        if g["event"] != event_id:
            continue
        for r in g["results"]:
            mark = "✓" if r["ok"] else "✗"
            label = "あるべき" if r["type"] == "must" else "あってはいけない"
            out.append(f'<div class="res {"" if r["ok"] else "ng"}">{mark} <b>[{esc(g["target"])}·{label}]</b> {esc(r["expectation"])}'
                       f' <span class="n">— {esc(r["note"])}</span></div>')
        for m in g.get("mechanical", []):
            mark = "✓" if m["ok"] else ("!" if m["severity"] == "warn" else "✗")
            cls = "" if m["ok"] or m["severity"] != "fail" else "ng"
            out.append(f'<div class="res {cls}">{mark} <b>[機械]</b> {esc(m["check"])} <span class="n">{esc(m["note"])}</span></div>')
        for u in g.get("unexplained_items", []):
            out.append(f'<div class="res">? <b>[想定外の項目]</b> {esc(u)}</div>')
    return "".join(out)


def render_obs(o: dict) -> str:
    flags = f'{o["certainty"]} · {o["initiative"]} · {o["context"]} · {o["kind_hint"]} · {o["reaction"]}'
    if o["sensitive"] != "none":
        flags += f' · <b>sensitive={esc(o["sensitive"])}</b>'
    return (f'<div class="obs"><span class="muted">{flags}</span><br>{esc(o["note"])}'
            f'<br><b>惹かれた点:</b> {esc(o["hook"] or "(不明)")}'
            + (f'<br><b>但し書き:</b> {esc(o["caveat"])}' if o.get("caveat") else "")
            + (f'<br><span class="muted">occurred_at {esc(o["occurred_at"])}</span>' if o["kind_hint"] == "record" else "")
            + "</div>")


def render_state(st: dict) -> str:
    by_cat: dict[str, list] = {}
    for it in st["items"]:
        by_cat.setdefault(it["category"], []).append(it)
    rows = []
    for cat, items in by_cat.items():
        rows.append(f'<div class="item"><b>{esc(cat)}</b></div>')
        for it in items:
            st_chip = {"active": "ok", "pending_confirm": "warn", "rejected": "ng"}.get(it["status"], "")
            date = f' ({esc(it["occurred_at"])})' if it["kind"] == "record" and it.get("occurred_at") else ""
            hist = f' <span class="muted">← 旧: {esc(it["versions"][-1]["content"])}</span>' if it["versions"] else ""
            rows.append(f'<div class="item">　<span class="chip {st_chip}">{esc(it["status"])}</span><span class="chip">{esc(it["kind"])}</span>'
                        f'<span class="chip">{esc(it["origin"])}</span>{esc(it["content"])}{date}'
                        f' <span class="muted">根拠: {esc(", ".join(it["evidence_threads"]))}</span>{hist}</div>')
    memos = "".join(f'<div class="item"><span class="chip {"ok" if m["active"] else ""}">{esc(m["kind"])}</span>{esc(m["content"])}'
                    + (f' <span class="muted">〜{esc(m["expires_at"])}</span>' if m["expires_at"] else "") + "</div>" for m in st["memos"])
    hyps = "".join(f'<div class="item"><span class="chip">{esc(h["status"])}</span>{esc(h["content"])}</div>' for h in st["hypotheses"])
    blocked = f'<div class="item">ブロックした分野: {esc(", ".join(st["blocked_areas"]))}</div>' if st["blocked_areas"] else ""
    return (("".join(rows) or '<div class="muted">項目なし</div>')
            + (f'<div style="margin-top:6px"><b>覚え書き</b>{memos}</div>' if memos else "")
            + (f'<div style="margin-top:6px"><b>仮説</b>{hyps}</div>' if hyps else "") + blocked)


def render_scenario(r: dict) -> str:
    parts = [f'<h2 id="{esc(r["scenario_id"])}">{esc(r["scenario_id"])}</h2>',
             f'<p class="muted">{esc(r["description"])}</p>', f'<p>{chips_summary(r["summary"])}'
             f' <span class="chip">原価 ${r["cost_usd"]["pipeline_tokens"]:.4f}</span></p>']
    for e in r["events"]:
        if e["type"] == "thread":
            body = "".join(render_obs(o) for o in e["observations"]) or '<div class="muted">観察なし</div>'
            body += "".join(f'<div class="res">仮説の更新: {esc(u["status"])} — {esc(u["hypothesis"])}</div>' for u in e["hypothesis_updates"])
            head = f'<h3>👀 {esc(e["id"])} <span class="muted">{esc(e["date"])}</span></h3>'
        elif e["type"] == "consolidate":
            dropped = "".join(f'<div class="res n">落とした操作: {esc(d["reason"])} — {esc((d["op"] or {}).get("content") or (d["op"] or {}).get("name") or "")}</div>'
                              for d in e["dropped"])
            guard = "".join(f'<div class="res n">違う項目との近さ {g["similarity"]}: {esc(g["content"])} ↔ {esc(g["nearest_rejected"])}'
                            f'{" → 落とした" if g["blocked"] else ""}</div>' for g in e.get("rejected_guard", []))
            reasons = "".join(f'<div class="res n">理由: {esc(c.get("content"))} — {esc(c.get("reason"))}</div>'
                              for c in e["plan"]["item_creates"] + e["plan"]["item_updates"] if c.get("reason"))
            body = render_state(e["state"]) + (f"<details><summary>判断の理由・落とした操作</summary>{reasons}{dropped}{guard}</details>"
                                               if reasons or dropped or guard else "")
            head = f'<h3>🧱 {esc(e["id"])} まとめ役 <span class="muted">今日={esc(e["today"])} · 新しい観察 {e["input_counts"]["new"]} · 近い過去 {e["input_counts"]["related"]}</span></h3>'
        elif e["type"] == "user_action":
            body = f'<div class="res">{esc(e.get("item_content") or e["target"])}{" (評価側で差し込み)" if e.get("injected") else ""}'
            body += f' → ブロック: {esc(e["blocked_area"])}' if e.get("blocked_area") else ""
            body += "</div>"
            head = f'<h3>🙋 {esc(e["id"])} 本人の操作: {esc(e["action"])}</h3>'
        else:
            rows = "".join(f'<tr><td>{esc(f)}</td><td>{esc(e["before"][f].get("text") or "(空)")}<br><span class="muted">{esc(e["before"][f].get("origin"))}</span></td>'
                           f'<td>{esc(e["after"][f].get("text") or "(空)")}<br><span class="muted">{esc(e["after"][f].get("origin"))}</span></td>'
                           f'<td>{esc(e["proposals"].get(f) or "")}</td></tr>' for f in e["before"])
            body = f'<div class="tbl"><table><tr><th>欄</th><th>前</th><th>後</th><th>書き直し案</th></tr>{rows}</table></div>'
            head = f'<h3>📇 {esc(e["id"])} 表紙</h3>'
        parts.append(f'<div class="ev {esc(e["type"])}">{head}{body}{render_grades(r["grades"], e["id"])}</div>')
    return "".join(parts)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="")
    args = ap.parse_args()
    res_dir = TEST_DIR / "results" / args.tag if args.tag else TEST_DIR / "results"
    results = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(res_dir.glob("p*.json"))]
    if not results:
        raise SystemExit(f"no results in {res_dir}")
    models = results[0]["models"]
    toc = "".join(f'<tr><td><a href="#{esc(r["scenario_id"])}">{esc(r["scenario_id"])}</a></td><td>{chips_summary(r["summary"])}</td></tr>' for r in results)
    total_cost = sum(r["cost_usd"]["pipeline_tokens"] for r in results)
    doc = (f'<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
           f'<title>自分像プロフィール評価</title><style>{CSS}</style></head><body><div class="wrap">'
           f'<h1>自分像プロフィール 評価レポート</h1><p class="muted">モデル: 観察役 {esc(models["observer"])} / まとめ役 {esc(models["consolidator"])}'
           f' (推論 {esc(models["consolidator_reasoning"])}) / 表紙 {esc(models["cover"])} · 原価合計 ${total_cost:.4f}</p>'
           f'<div class="tbl"><table>{toc}</table></div>' + "".join(render_scenario(r) for r in results) + "</div></body></html>")
    out = res_dir / "report.html"
    out.write_text(doc, encoding="utf-8")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
