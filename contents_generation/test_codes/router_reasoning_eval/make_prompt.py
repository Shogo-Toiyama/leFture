"""
本番の chat_router_prompt.txt から、needs_reasoning の基準だけを変えた版(prompts/router_v1.txt)を作る。
置き換え前の文字列が1回だけあることを確かめる(本番が変わっていたら止まる)。

変更の意図(2026-11-06): needs_reasoning=true が多すぎる(3.1 Flash Liteで13件中11件)。
「不変データ構造」スレッドでは、意味・用語・一言の理解の確認・説明・まとめ・「日本語で説明して」まで
trueになり、回答役がeffort highで考えて最初の1文字まで約8.5秒遅れていた。
- 「迷ったらtrue」を消す
- 「難しい・微妙な質問」を、具体的なコード・数・データの上で解くものに絞る
- 押し返しは計算・コード・問題の答えについてのものに絞る(事実への押し返しは検索の仕事)
- falseの例に、定義・用語の比較・一言の理解の確認・説明・例・まとめ・翻訳を足す
"""

from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE.parents[2] / "lefture_backend" / "app" / "services" / "prompts" / "chat_router_prompt.txt"
DST = HERE / "prompts" / "router_v1.txt"

s = SRC.read_text(encoding="utf-8")


def rep(old: str, new: str) -> None:
    global s
    assert s.count(old) == 1, (s.count(old), old[:70])
    s = s.replace(old, new)


rep("- a hard or subtle question: comparing approaches, a tricky concept or edge case, a question with a catch, or one that needs several facts put together;",
    "- a hard problem to work out on concrete code, numbers, or data: comparing approaches on a given case, an edge case in it, or a question with a catch;")
rep("- the student questions or pushes back on something said earlier in a way that needs re-checking (",
    "- the student questions or pushes back on an earlier calculation, code trace, or answer to a problem in a way that needs re-checking (")
rep("false for light messages: chitchat, thanks and reactions, feelings and support, a simple fact or word meaning, a short explanation of a basic concept, `blocked`, `crisis`. When unsure between the two, choose true.",
    "false for everything else, even when the topic is advanced: chitchat, thanks and reactions, feelings and support, a fact, a definition or word meaning, how two terms relate, confirming a one-line understanding of a concept (\"so X is the same as Y, right?\"), an explanation or example of a concept, a summary or overview, a translation or re-explaining in another language, `blocked`, `crisis`.")

DST.write_text(s, encoding="utf-8")
print("wrote", DST)
