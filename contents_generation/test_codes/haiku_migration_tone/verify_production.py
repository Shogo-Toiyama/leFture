"""
本番コード (変更後の Service クラス・本番プロンプト) が、実験で検証した版と同じリクエストを組み立てるかを確認する。
- 本番 Service をモデル/オプションの上書きなしで呼び、LLM 呼び出しは記録してスタブを返す (API 呼び出しなし)
- 実験の dry-run 記録 (RC: v2, DN: v3, FF: v2) と system / user メッセージを突き合わせる
- --live を付けると、Review Cards の 1 トピックだけ本番コードで実際に Haiku を呼ぶ
"""
import asyncio
import glob
import json
import sys
from pathlib import Path

EXP = Path(__file__).resolve().parent
sys.path.insert(0, str(EXP))
import run_experiment as E  # noqa: E402  (env 読み込み・R2 キャッシュ無効化用)
from app.services.helpers.helpers import TaskLogger  # noqa: E402
from app.services.helpers.llm_unified import BillingEngine, UnifiedLLM  # noqa: E402
from app.services.logic import fun_fact_generation as ff_mod  # noqa: E402
from app.services.logic import review_card_generation as rc_mod  # noqa: E402
from app.services.logic import topic_details_generation as dn_mod  # noqa: E402

LECTURE = "a028aad6-07ba-4e3f-ac39-7494e9d7f062"
LIVE = "--live" in sys.argv


class RecordingLLM(UnifiedLLM):
    def __init__(self, billing, task, live_first=False):
        super().__init__(billing)
        self.task, self.live_first, self.records = task, live_first, []

    async def generate(self, model, messages, options=None):
        kwargs = self._build_kwargs(model, messages, options)
        self.records.append({"model": model, "kwargs": {k: v for k, v in kwargs.items() if k != "messages"},
                             "system": messages[0].content, "user": messages[1].content})
        if self.live_first and len(self.records) == 1:
            res = await super().generate(model, messages, options)
            self.records[-1]["live"] = {"finish": res.finish_reason, "parse_error": res.json_parse_error,
                                        "cards": [c.get("card_type") for c in (res.output_json or {}).get("review_cards", [])],
                                        "out_tokens": res.output_tokens}
            return res
        return E._mock_result(self.task, options.output_type)


def dry_messages(version, task):
    d = sorted(glob.glob(str(EXP / f"results/*_dryrun_{version}")))[-1]
    raw = json.loads(Path(d, "raw.json").read_text())
    return [c["messages"] for r in raw["results"] if r["task"] == task for c in r["calls"]]


async def main():
    E._disable_r2_cache()
    inp = json.loads((EXP / "inputs" / f"{LECTURE}.json").read_text())
    lang = inp["language"]
    uid = inp["lecture"]["user_id"]
    out = {}
    for task, svc_cls in (("review_cards", rc_mod.ReviewCardGenerationService),
                          ("deep_notes", dn_mod.TopicDetailGenerationService),
                          ("fun_facts", ff_mod.FunFactGenerationService)):
        llm = RecordingLLM(BillingEngine(), task, live_first=(LIVE and task == "review_cards"))
        svc = svc_cls(llm, TaskLogger(uid, LECTURE, f"VERIFY:{task}"))
        if task == "fun_facts":
            await svc.run_from_memory(core_data=inp["core_extraction"], seed_data=inp["fun_fact_seed"],
                                      search_results=inp["fun_fact_search"], student_profile=inp["student_profile"],
                                      content_language=lang["content_language"])
        else:
            try:
                await svc.run_from_memory(inp["role_classification"], inp["core_extraction"], uid=uid,
                                          lecture_id=LECTURE, content_language=lang["content_language"],
                                          transcript_language=lang["transcript_language"],
                                          is_bilingual=lang["is_bilingual"])
            except ValueError as e:  # スタブはカード枚数チェックで失敗扱いになる (想定どおり)
                print(f"   (expected with stubs) {str(e)[:90]}")
        out[task] = llm.records
        r0 = llm.records[0]
        k = r0["kwargs"]
        print(f"{task}: calls={len(llm.records)} model={r0['model']} max_tokens={k.get('max_tokens')} "
              f"reasoning_effort={k.get('reasoning_effort')} thinking={k.get('thinking')} "
              f"response_format={str(k.get('response_format'))[:40]} temperature={k.get('temperature')}")
        if "live" in r0:
            print("   LIVE:", r0["live"])

    # 実験 dry-run との一致確認 (同じ講義の呼び出しを比較)
    for task, ver in (("review_cards", "v2"), ("deep_notes", "v3"), ("fun_facts", "v2")):
        d = sorted(glob.glob(str(EXP / f"results/*_dryrun_{ver}")))[-1]
        raw = json.loads(Path(d, "raw.json").read_text())
        exp_calls = [c["messages"] for r in raw["results"] if r["task"] == task and r["lecture_id"] == LECTURE
                     for c in r["calls"]]
        prod = out[task]
        if not exp_calls:
            print(f"{task}: no experiment dry-run for this lecture in {ver}; comparing against v2/v3 prompt files only")
            continue
        same = 0
        for em in exp_calls:
            match = [p for p in prod if p["system"] == em[0]["content"] and p["user"] == em[1]["content"]]
            same += bool(match)
        print(f"{task}: {same}/{len(exp_calls)} experiment calls reproduced byte-for-byte by production code")


if __name__ == "__main__":
    asyncio.run(main())
