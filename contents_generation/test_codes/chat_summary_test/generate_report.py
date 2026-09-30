"""results/*.json から、評価レポートのHTML(report.html)を組み立てるだけのスクリプト。
Artifactとして公開する前に、ローカルで完成させておくためのもの。

実行: python generate_report.py
"""

import html
import json
from pathlib import Path

TEST_DIR = Path(__file__).resolve().parent
RESULTS_DIR = TEST_DIR / "results"

TIER_LABELS = {
    "raw": "直近の原文のまま",
}


def esc(s: str) -> str:
    return html.escape(s or "", quote=True)


def pre(s: str) -> str:
    return f'<pre class="answer-text">{esc(s)}</pre>'


def fact_list_html(results: list[dict], key_present: str, key_label_present: str, key_label_absent: str) -> str:
    items = []
    for r in results:
        ok = r[key_present]
        cls = "fact-ok" if ok else "fact-ng"
        label = key_label_present if ok else key_label_absent
        items.append(
            f'<li class="{cls}"><span class="fact-chip">{label}</span>'
            f'<span class="fact-text">{esc(r["fact"])}</span>'
            f'<span class="fact-note">{esc(r["note"])}</span></li>'
        )
    return "<ul class='fact-list'>" + "".join(items) + "</ul>" if items else ""


def render_condition(label: str, cls: str, cond: dict, context_note: str) -> str:
    judge = cond["judge"]
    overall = judge["overall_pass"]
    include_html = fact_list_html(judge["include_results"], "present", "含む", "含まない")
    violations = [r for r in judge["violation_results"] if r["violated"]]
    violation_html = ""
    if judge["violation_results"]:
        violation_html = fact_list_html(
            [{"fact": r["fact"], "present": not r["violated"], "note": r["note"]} for r in judge["violation_results"]],
            "present", "違反なし", "違反あり",
        )
    extra = ""
    if cond.get("summary_text") or cond.get("header_text"):
        extra = (
            "<details class='inner-details'><summary>この条件で回答役に渡した要約・前提</summary>"
            + (pre(cond.get("header_text", "")) if cond.get("header_text") else "")
            + (pre(cond.get("summary_text", "")) if cond.get("summary_text") else "")
            + "</details>"
        )
    status_cls = "pass" if overall else "fail"
    status_label = "合格" if overall else "不合格"
    return f"""
    <div class="condition condition-{cls}">
      <div class="condition-head">
        <span class="condition-label">{label}</span>
        <span class="status-chip status-{status_cls}">{status_label}</span>
      </div>
      <div class="context-note">{esc(context_note)}</div>
      {pre(cond["answer"])}
      {include_html}
      {violation_html}
      {extra}
    </div>
    """


def render_probe(probe: dict) -> str:
    ctx = probe["context_stats"]
    raw_note = f"文脈: 生の会話 {ctx['raw_condition_rounds']}往復をすべて渡した"
    sum_note = (
        f"文脈: 要約ブロック{ctx['summarized_condition_blocks']}個 + 直近の原文{ctx['summarized_condition_raw_rounds']}往復"
    )
    raw_html = render_condition("生の全履歴", "raw", probe["raw_condition"], raw_note)
    sum_html = render_condition("要約 + 直近の原文", "summarized", probe["summarized_condition"], sum_note)
    both_pass = probe["raw_condition"]["judge"]["overall_pass"] and probe["summarized_condition"]["judge"]["overall_pass"]
    probe_status = "pass" if both_pass else "fail"
    tier = probe.get("expected_tier")
    tier_html = f'<span class="tier-chip">扱う階層: {esc(tier)}</span>' if tier else ""
    return f"""
    <div class="probe probe-{probe_status}">
      <div class="probe-head">
        <h3>{esc(probe["probe_id"])}</h3>
        {tier_html}
      </div>
      <p class="probe-question"><strong>質問(round {esc(str(probe["history_through_round"] + 1))}):</strong> {esc(probe["probe_question"])}</p>
      <details class="inner-details"><summary>正解の目安(執筆時点の会話の流れの中の返答)</summary>{pre(probe["gold_reference_answer"])}</details>
      <p class="why-it-matters">{esc(probe.get("why_it_matters", ""))}</p>
      <div class="condition-grid">
        {raw_html}
        {sum_html}
      </div>
    </div>
    """


def render_blocks(blocks: list[dict]) -> str:
    if not blocks:
        return "<p class='muted'>このたたみでは、まだブロックは作られていない。</p>"
    parts = []
    for b in blocks:
        parts.append(f"<div class='block'><div class='block-label'>ブロック #{b['block_index']} (round {b['turn_start']}〜{b['turn_end']})</div>")
        for sec in b["sections"]:
            rounds_str = ", ".join(str(r) for r in sec["turns"])
            parts.append(f"<div class='section'><div class='section-title'>{esc(sec['title'])} <span class='muted'>(round {rounds_str})</span></div>")
            parts.append("<ul class='bullets'>" + "".join(f"<li>{esc(x)}</li>" for x in sec["bullets"]) + "</ul></div>")
        parts.append("</div>")
    return "".join(parts)


def render_header(header: dict) -> str:
    labels = {
        "style_preferences": "回答スタイルの指定",
        "context": "この会話の前提",
        "purpose": "この会話の目的",
        "unresolved": "未解決の約束・質問",
    }
    parts = []
    any_item = False
    for key, label in labels.items():
        items = header.get(key) or []
        if not items:
            continue
        any_item = True
        parts.append(f"<div class='header-row'><span class='header-label'>{label}</span><ul class='header-items'>")
        for it in items:
            parts.append(f"<li>{esc(it['text'])} <span class='muted'>(round {it['source_turn']}生まれ)</span></li>")
        parts.append("</ul></div>")
    if not any_item:
        return "<p class='muted'>ヘッダーはまだ空。</p>"
    return "".join(parts)


def render_conversation(conv: dict) -> str:
    probes_html = "".join(render_probe(p) for p in conv["probe_results"])
    all_pass = all(
        p["raw_condition"]["judge"]["overall_pass"] and p["summarized_condition"]["judge"]["overall_pass"]
        for p in conv["probe_results"]
    )
    lang_label = "JA" if conv["language"] == "ja" else "EN"
    qual_html = ""
    if conv.get("qualitative_checks"):
        qual_items = "".join(f"<li>{esc(q)}</li>" for q in conv["qualitative_checks"])
        qual_html = f"<div class='qualitative'><div class='qualitative-title'>人が読んで確認するポイント</div><ul>{qual_items}</ul></div>"

    return f"""
    <section class="conversation">
      <div class="conversation-head">
        <span class="lang-chip">{lang_label}</span>
        <h2>{esc(conv["id"])}</h2>
        <span class="status-chip status-{'pass' if all_pass else 'fail'}">{'全probe合格' if all_pass else '要確認'}</span>
      </div>
      {probes_html}
      {qual_html}
      <details class="block-details">
        <summary>実際に生成された要約の中身を見る(この会話の最終状態)</summary>
        <div class="block-details-inner">
          <div class="header-box">
            <div class="header-box-title">ヘッダー(①会話の前提)</div>
            {render_header(conv["final_header"])}
          </div>
          {render_blocks(conv["final_blocks"])}
        </div>
      </details>
    </section>
    """


def main() -> None:
    conversations = []
    for path in sorted(RESULTS_DIR.glob("*.json")):
        if path.name == "_all_results.json":
            continue
        conversations.append(json.loads(path.read_text(encoding="utf-8")))

    total_probes = sum(len(c["probe_results"]) for c in conversations)
    passed_probes = sum(
        1
        for c in conversations
        for p in c["probe_results"]
        if p["raw_condition"]["judge"]["overall_pass"] and p["summarized_condition"]["judge"]["overall_pass"]
    )

    body = "\n".join(render_conversation(c) for c in conversations)

    html_doc = f"""<title>チャット要約評価</title>
<style>
:root {{
  --bg: #f6f4ef;
  --surface: #ffffff;
  --surface-2: #f0ede5;
  --border: #ddd7c9;
  --text: #23211c;
  --text-muted: #6b6558;
  --accent: #3c6e71;
  --accent-2: #b3541e;
  --raw: #b3541e;
  --raw-bg: #fbeee2;
  --sum: #3c6e71;
  --sum-bg: #e6f0ef;
  --pass: #2f7a3d;
  --pass-bg: #e5f3e6;
  --fail: #b3261e;
  --fail-bg: #fbe6e4;
  --mono: 'JetBrains Mono', ui-monospace, monospace;
  --display: 'Zen Kaku Gothic New', 'Noto Sans JP', sans-serif;
  --body-font: 'Noto Sans JP', sans-serif;
  color-scheme: light;
}}
@media (prefers-color-scheme: dark) {{
  :root:not([data-theme="light"]) {{
    --bg: #17181a;
    --surface: #202225;
    --surface-2: #26282c;
    --border: #37393e;
    --text: #eceae4;
    --text-muted: #9a978d;
    --accent: #7fb8ba;
    --accent-2: #e08a52;
    --raw: #e08a52;
    --raw-bg: #33261c;
    --sum: #7fb8ba;
    --sum-bg: #1c2c2b;
    --pass: #6fcf7d;
    --pass-bg: #1c2e1f;
    --fail: #ef6f66;
    --fail-bg: #33201e;
    color-scheme: dark;
  }}
}}
:root[data-theme="dark"] {{
  --bg: #17181a;
  --surface: #202225;
  --surface-2: #26282c;
  --border: #37393e;
  --text: #eceae4;
  --text-muted: #9a978d;
  --accent: #7fb8ba;
  --accent-2: #e08a52;
  --raw: #e08a52;
  --raw-bg: #33261c;
  --sum: #7fb8ba;
  --sum-bg: #1c2c2b;
  --pass: #6fcf7d;
  --pass-bg: #1c2e1f;
  --fail: #ef6f66;
  --fail-bg: #33201e;
  color-scheme: dark;
}}
* {{ box-sizing: border-box; }}
body {{
  background: var(--bg);
  color: var(--text);
  font-family: var(--body-font);
  padding: 0 16px 64px;
  line-height: 1.7;
}}
.page {{ max-width: 900px; margin: 0 auto; }}
.masthead {{ padding: 40px 0 24px; border-bottom: 1px solid var(--border); }}
.masthead h1 {{
  font-family: var(--display);
  font-size: 28px;
  margin: 0 0 8px;
  letter-spacing: 0.01em;
}}
.masthead p.lede {{ color: var(--text-muted); margin: 0 0 20px; max-width: 62ch; }}
.stat-row {{ display: flex; gap: 12px; flex-wrap: wrap; }}
.stat-tile {{
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 12px 18px;
  min-width: 120px;
}}
.stat-tile .num {{ font-family: var(--mono); font-size: 22px; font-weight: 600; }}
.stat-tile .label {{ font-size: 12px; color: var(--text-muted); margin-top: 2px; }}
.methodology {{ margin-top: 20px; color: var(--text-muted); font-size: 13px; }}
.methodology summary {{ cursor: pointer; color: var(--accent); }}

.conversation {{ margin-top: 40px; padding-top: 8px; }}
.conversation-head {{ display: flex; align-items: center; gap: 10px; flex-wrap: wrap; margin-bottom: 12px; }}
.conversation-head h2 {{
  font-family: var(--mono);
  font-size: 17px;
  margin: 0;
  font-weight: 600;
}}
.lang-chip {{
  font-family: var(--mono);
  font-size: 11px;
  background: var(--surface-2);
  border: 1px solid var(--border);
  border-radius: 5px;
  padding: 2px 7px;
  color: var(--text-muted);
}}
.status-chip {{
  font-size: 12px;
  border-radius: 999px;
  padding: 3px 11px;
  font-weight: 600;
}}
.status-pass {{ background: var(--pass-bg); color: var(--pass); }}
.status-fail {{ background: var(--fail-bg); color: var(--fail); }}

.probe {{
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 14px;
  padding: 20px 22px;
  margin-bottom: 16px;
}}
.probe-head {{ display: flex; align-items: baseline; gap: 10px; flex-wrap: wrap; }}
.probe-head h3 {{ font-family: var(--mono); font-size: 14px; margin: 0; color: var(--accent); }}
.tier-chip {{
  font-size: 11px; color: var(--text-muted); background: var(--surface-2);
  border-radius: 5px; padding: 2px 8px; font-family: var(--mono);
}}
.probe-question {{ margin: 10px 0 6px; }}
.why-it-matters {{ color: var(--text-muted); font-size: 13px; font-style: italic; margin: 6px 0 14px; }}

.condition-grid {{ display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin-top: 10px; }}
@media (max-width: 720px) {{ .condition-grid {{ grid-template-columns: 1fr; }} }}
.condition {{ border-radius: 10px; padding: 14px; border: 1px solid var(--border); }}
.condition-raw {{ background: var(--raw-bg); border-color: color-mix(in srgb, var(--raw) 35%, var(--border)); }}
.condition-summarized {{ background: var(--sum-bg); border-color: color-mix(in srgb, var(--sum) 35%, var(--border)); }}
.condition-head {{ display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px; }}
.condition-label {{ font-weight: 700; font-size: 13px; }}
.condition-raw .condition-label {{ color: var(--raw); }}
.condition-summarized .condition-label {{ color: var(--sum); }}
.context-note {{ font-size: 11.5px; color: var(--text-muted); margin-bottom: 8px; }}
.answer-text {{
  font-family: var(--body-font);
  font-size: 13.5px;
  white-space: pre-wrap;
  word-break: break-word;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 10px 12px;
  margin: 0 0 8px;
  max-height: 340px;
  overflow-y: auto;
}}
.fact-list {{ list-style: none; margin: 0 0 6px; padding: 0; display: flex; flex-direction: column; gap: 4px; }}
.fact-list li {{ font-size: 12px; display: flex; gap: 6px; align-items: baseline; flex-wrap: wrap; }}
.fact-chip {{ font-family: var(--mono); font-size: 10px; border-radius: 4px; padding: 1px 6px; flex-shrink: 0; }}
.fact-ok .fact-chip {{ background: var(--pass-bg); color: var(--pass); }}
.fact-ng .fact-chip {{ background: var(--fail-bg); color: var(--fail); }}
.fact-text {{ font-weight: 600; }}
.fact-note {{ color: var(--text-muted); }}

.inner-details {{ margin-top: 8px; }}
.inner-details summary {{ cursor: pointer; font-size: 12px; color: var(--text-muted); }}
.inner-details .answer-text {{ margin-top: 6px; }}

.qualitative {{
  background: var(--surface-2);
  border: 1px dashed var(--border);
  border-radius: 10px;
  padding: 12px 16px;
  margin-bottom: 16px;
  font-size: 13px;
}}
.qualitative-title {{ font-weight: 700; margin-bottom: 6px; }}
.qualitative ul {{ margin: 0; padding-left: 20px; color: var(--text-muted); }}

.block-details {{ margin-top: 6px; }}
.block-details > summary {{
  cursor: pointer; font-weight: 600; font-size: 13px; color: var(--accent);
  padding: 10px 0;
}}
.block-details-inner {{ padding: 6px 0 4px; }}
.header-box {{
  background: var(--surface-2); border: 1px solid var(--border); border-radius: 10px;
  padding: 12px 16px; margin-bottom: 14px;
}}
.header-box-title {{ font-weight: 700; font-size: 13px; margin-bottom: 6px; }}
.header-row {{ margin-bottom: 6px; font-size: 13px; }}
.header-label {{ font-weight: 600; margin-right: 6px; }}
.header-items {{ display: inline; list-style: none; margin: 0; padding: 0; }}
.header-items li {{ display: inline; }}
.header-items li:not(:last-child)::after {{ content: " / "; color: var(--text-muted); }}

.block {{ border: 1px solid var(--border); border-radius: 10px; padding: 12px 16px; margin-bottom: 10px; background: var(--surface); }}
.block-label {{ font-family: var(--mono); font-size: 11px; color: var(--text-muted); margin-bottom: 8px; }}
.section {{ margin-bottom: 10px; }}
.section:last-child {{ margin-bottom: 0; }}
.section-title {{ font-weight: 700; font-size: 13.5px; margin-bottom: 4px; }}
.bullets {{ margin: 0; padding-left: 20px; font-size: 13px; color: var(--text); }}
.bullets li {{ margin-bottom: 2px; }}
.muted {{ color: var(--text-muted); font-weight: 400; font-size: 12px; }}

footer {{ margin-top: 48px; padding-top: 20px; border-top: 1px solid var(--border); color: var(--text-muted); font-size: 12px; }}
</style>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Zen+Kaku+Gothic+New:wght@500;700&family=Noto+Sans+JP:wght@400;500;600;700&family=JetBrains+Mono:wght@400;600&display=swap">

<div class="page">
  <div class="masthead">
    <h1>チャット要約評価</h1>
    <p class="lede">
      スレッド要約パイプライン(ロードマップ ステップ2)を、5本の会話・{total_probes}個のprobeに通した結果。
      各probeについて「生の全履歴」と「要約(GPT-6 Luna) + 直近の原文」の2条件で
      同じ回答役(gemini-3.1-flash-lite)に答えさせ、要点が保てているかをLLM審判(gemini-2.5-flash-lite)で判定した。
    </p>
    <div class="stat-row">
      <div class="stat-tile"><div class="num">{len(conversations)}</div><div class="label">会話</div></div>
      <div class="stat-tile"><div class="num">{total_probes}</div><div class="label">probe</div></div>
      <div class="stat-tile"><div class="num">{passed_probes} / {total_probes}</div><div class="label">両条件とも合格</div></div>
      <div class="stat-tile"><div class="num">$0.02</div><div class="label">評価にかかった費用</div></div>
    </div>
    <details class="methodology">
      <summary>台本とprobeの作り方について</summary>
      <p>
        各probeは会話の自然な流れに埋め込まれた質問で、別途不自然な確認問題は作っていない。
        その往復で執筆時に書いた回答が「正解の目安」。要約の実装は
        contents_generation/test_codes/chat_summary_test/ 以下(build_conversations.py,
        run_eval.py)。要約役・回答役は本番のコード(chat_summary.py / chat_service.py)をそのまま呼んでいる。
      </p>
    </details>
  </div>

  {body}

  <footer>chat_summary_test — docs/chatbot_context_and_retrieval_roadmap.md ステップ2の評価</footer>
</div>
"""
    out_path = TEST_DIR / "report.html"
    out_path.write_text(html_doc, encoding="utf-8")
    print(f"wrote {out_path}")


if __name__ == "__main__":
    main()
