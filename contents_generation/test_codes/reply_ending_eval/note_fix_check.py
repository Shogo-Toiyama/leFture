"""
A48 の締めの質問が、会話ノートの誤った言い換え(「概念を理解できているかを確認する方針で説明する」)から
来ているかの切り分け。ノートの一行だけを元の発言の意味に直し、新プロンプト(v3)で A48 を再生する。
  .venv/bin/python contents_generation/test_codes/reply_ending_eval/note_fix_check.py [--dry-run]
"""
import asyncio, dataclasses, json, os, sys
from datetime import datetime
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import replay as r  # noqa: E402
from supabase import create_client  # noqa: E402

OLD = "言語ごとの性質の暗記より、概念を理解できているかを確認する方針で説明する。"
NEW = "テストは言語ごとの性質の暗記ではなく概念の理解を問うので、暗記より概念の理解に重点を置いて説明する。"


async def main():
    dry = "--dry-run" in sys.argv
    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    case = next(k for k in r.CASES if k["id"] == "A48_type_inference")
    b = await r.build_case(c, case)
    sys_msg = b["messages_variant"][0]
    assert OLD in sys_msg.content, "note text not found"
    b["messages_variant"] = [dataclasses.replace(sys_msg, content=sys_msg.content.replace(OLD, NEW))] + b["messages_variant"][1:]
    assert NEW in b["messages_variant"][0].content
    if dry:
        print("DRY RUN OK"); return
    billing = r.BillingEngine(task_type="reply_ending_eval")
    llm = r.UnifiedLLM(billing)
    results = [await r.run_once(llm, billing, b, case, i) for i in range(2)]
    r.finish(billing, results, "v3_notefix")

asyncio.run(main())
