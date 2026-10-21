# app/services/chat_reasoning.py
"""
推論が要るターン(振り分け役の needs_reasoning=True)の答え方。

2026-10-03に決めた形(評価: contents_generation/test_codes/answer_reasoning_test/):
  二段構え = 確かめ役(GPT-6 Luna 推論low)が会話と最新の質問から「正しい答えと途中の値・生徒の発言の
  正誤・前の返答の誤り・会話の数え方」を英語のメモにする → 回答役(ふだんと同じGemini)がそれを
  <checked_work>として受け取り、いつもの口調で返事を書く。メモは生徒には見せない。
  - 回答役だけ(3.5 Flash-Lite・推論なし)だと、計算やコードの追跡で正しい解答を誤って「訂正」し、
    前の誤った返答に引っ張られた(27回中3回合格)。二段構えは14/26合格、誤りを含まない返答24/26で
    全構成で最多、消費は今の約1.3倍、最初の1文字まで約8秒。
  - Luna単体(16/27)や3.8 Flash medium(16/27、消費は約8倍)より、口調(励まし・寄り添い)を
    Geminiのまま保てる点でユーザーが選んだ。

2026-10-05: 回答役をLunaにしたので一段("single"、Luna推論low)に切り替えた。
2026-10-08: 回答役をClaude Haiku 5.5にしたので、推論が要るターンもHaiku 5.5(effort medium)で一段で答える
(ユーザー判断)。実際に失敗した3ターン(ネットワークの宿題のlag_code・bit4、LeetCodeの「できた！」)を
3回ずつ作り直して伏せて採点すると、Haiku medium 9/9、Luna low 5/9、Haiku low 5/9。lag_codeでは
Luna lowは正しい値を出さないか新しい誤りを言い、Haiku mediumは3回とも正しい表まで出した。代わりに
重い計算では最初の1文字まで17〜28秒かかる(Luna lowは2〜9秒)。1ターン約0.6〜2.5クレジット。

一段への切り替え: REASONING_CONFIG.mode を "single" にすると、確かめ役を呼ばずに single_model で
直接答える(将来、ユーザーが選んだプロバイダー・モデルで答える方式(BYOK)にするときのため)。
"""

import asyncio
import time
from dataclasses import dataclass
from typing import Literal, Optional

from app.services.helpers.helpers import _load_prompt
from app.services.helpers.llm_unified import LLMOptions, Message, UnifiedLLM

ReasoningEffort = Optional[Literal["none", "low", "medium", "high"]]


@dataclass(frozen=True)
class ReasoningConfig:
    # "two_stage": 確かめ役のメモ → 回答役 / "single": single_modelが一段で答える
    mode: Literal["two_stage", "single"]
    solver_model: str = "gpt-6-luna"
    solver_effort: ReasoningEffort = "low"
    # 一段のときに使うモデル。Noneなら回答役(ANSWER_MODEL)をそのまま使う
    single_model: Optional[str] = None
    single_effort: ReasoningEffort = None


# 2026-10-05に二段構えから一段へ(回答役をLunaにしたため。書き手もLunaなら、確かめ役のメモを
# 挟む意味が無い)。2026-10-08から、推論が要るターンは回答役(Haiku 5.5)がeffort mediumで直接答える
# (上の説明を参照)。二段構えに戻すときはmode="two_stage"。
REASONING_CONFIG = ReasoningConfig(mode="single", single_model=None, single_effort="high")

# 確かめ役の待ち時間の上限。超えたり失敗したりしたら、メモなしで回答役がそのまま答える
SOLVER_TIMEOUT_SECONDS = 40
SOLVER_MAX_COMPLETION_TOKENS = 8192


@dataclass
class CheckedWork:
    notes: Optional[str]
    model: str
    seconds: float
    input_tokens: int = 0
    output_tokens: int = 0
    error: Optional[str] = None

    def to_json(self) -> dict:
        return {
            "model": self.model,
            "seconds": round(self.seconds, 2),
            "input_tokens": self.input_tokens,
            "output_tokens": self.output_tokens,
            "error": self.error,
            # 原因を後から追えるように、渡したメモそのものも残す(返答と同じ本人のデータ)
            "notes": self.notes,
        }


def _solver_options(model: str, effort: ReasoningEffort) -> LLMOptions:
    # GPT-6系はtemperatureの既定値(1)以外とmax_tokensを受け付けない(2026-10-03に確認)
    if model.startswith("gpt-"):
        return LLMOptions(temperature=1.0, max_completion_tokens=SOLVER_MAX_COMPLETION_TOKENS,
                          reasoning_effort=effort)
    return LLMOptions(max_tokens=SOLVER_MAX_COMPLETION_TOKENS, reasoning_effort=effort)


def solver_messages(answer_messages: list[Message]) -> list[Message]:
    """
    回答役に渡すのと同じ会話(履歴と、出典・画面・質問を含む最新のメッセージ)を、
    systemだけ確かめ役のものに差し替えて渡す。
    """
    return [Message(role="system", content=_load_prompt("chat_solver_prompt.txt")), *answer_messages[1:]]


def with_checked_work(answer_messages: list[Message], notes: str) -> list[Message]:
    """最新のメッセージの末尾にメモを足す(回答役のsystemの「CHECKED WORK」節が扱い方を指示している)。"""
    last = answer_messages[-1]
    return [*answer_messages[:-1],
            Message(role=last.role, content=f"{last.content}\n\n<checked_work>\n{notes.strip()}\n</checked_work>",
                    images=last.images)]


async def check_work(llm: UnifiedLLM, answer_messages: list[Message],
                     config: ReasoningConfig = REASONING_CONFIG) -> CheckedWork:
    """確かめ役を呼ぶ。失敗・時間切れでも例外は投げず、notes=Noneで返す(呼び出し側はメモなしで答える)。"""
    start = time.perf_counter()
    try:
        result = await asyncio.wait_for(
            llm.generate(config.solver_model, solver_messages(answer_messages),
                         _solver_options(config.solver_model, config.solver_effort)),
            timeout=SOLVER_TIMEOUT_SECONDS,
        )
    except Exception as e:
        return CheckedWork(notes=None, model=config.solver_model, seconds=time.perf_counter() - start,
                           error=f"{type(e).__name__}: {e}"[:500])
    notes = (result.output_text or "").strip()
    return CheckedWork(
        notes=notes or None, model=config.solver_model, seconds=time.perf_counter() - start,
        input_tokens=result.input_tokens, output_tokens=result.output_tokens,
        error=None if notes else f"empty notes (finish_reason={result.finish_reason})",
    )
