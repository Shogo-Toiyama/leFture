"""
実験のときだけ、本番の app.services.chat_navigator の代わりに patched/chat_navigator.py を読み込ませる。
chat_service を import する前に install() を呼ぶこと(chat_service は import 時に navigate 等を取り込むため)。

本番に入れるときの変更(このファイルでモンキーパッチしているもの):
- chat_navigator.py: patched/chat_navigator.py と本番の差分
- prompts/chat_navigator_prompt.txt: patched/chat_navigator_prompt.txt と本番の差分
- prompts/chat_answer_prompt.txt: patched/chat_answer_prompt.txt と本番の差分(内部の呼び名を書かない)
- chat_materials.PRIORITY に "lecture_range": 3
- chat_service._answer_max_tokens: 材料に lecture_range があれば長く書けるようにする(course と同じ扱い)
"""

import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
sys.path.insert(0, str(REPO_ROOT / "lefture_backend"))

from dotenv import load_dotenv  # noqa: E402

load_dotenv(REPO_ROOT / "lefture_backend" / ".env")


def install():
    import app.services  # noqa: F401  (パッケージを先に読み込む)

    spec = importlib.util.spec_from_file_location("app.services.chat_navigator", HERE / "patched" / "chat_navigator.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["app.services.chat_navigator"] = mod
    spec.loader.exec_module(mod)

    prompt_path = HERE / "patched" / "chat_navigator_prompt.txt"
    orig_load = mod._load_prompt
    mod._load_prompt = lambda name: prompt_path.read_text(encoding="utf-8") if name == "chat_navigator_prompt.txt" else orig_load(name)

    from app.services import chat_materials
    chat_materials.PRIORITY["lecture_range"] = 3

    from app.services import chat_service as cs
    answer_prompt = HERE / "patched" / "chat_answer_prompt.txt"
    orig_cs_load = cs._load_prompt
    cs._load_prompt = lambda name: answer_prompt.read_text(encoding="utf-8") if name == "chat_answer_prompt.txt" else orig_cs_load(name)
    orig_max = cs._answer_max_tokens

    def answer_max_tokens(navigation, materials):
        if any(m.kind == "lecture_range" for m in materials):
            return cs.ANSWER_MAX_OUTPUT_TOKENS_WIDE
        return orig_max(navigation, materials)
    cs._answer_max_tokens = answer_max_tokens
    assert cs.navigate is mod.navigate, "chat_service must use the patched navigator"
    return mod, cs
