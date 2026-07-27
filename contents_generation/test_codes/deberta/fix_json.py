"""
GeminiがLaTeX記法(\Delta, \mu, \fracなど)を貼り付けた際に生まれる
不正なJSONエスケープを直して整形し直すユーティリティ。

使い方:
  python3 fix_json.py labeled_transcripts_multilingual/Astronomy_1/ja.json
  python3 fix_json.py labeled_transcripts_multilingual/**/*.json  (シェルのglobで複数まとめて)
"""
import sys
import re
import json


def fix_invalid_backslashes(raw: str) -> str:
    # JSONの正規エスケープ(\" \\ \/ \b \f \n \r \t \uXXXX)以外の "\" を "\\" にする
    return re.sub(r'\\(?!["\\/bfnrtu])', r'\\\\', raw)


def fix_file(path: str) -> None:
    with open(path, encoding="utf-8") as f:
        raw = f.read()

    if not raw.strip():
        print(f"⏭️  skip (empty): {path}")
        return

    try:
        data = json.loads(raw)
        print(f"✅ already valid: {path}")
        return
    except json.JSONDecodeError:
        pass

    fixed = fix_invalid_backslashes(raw)
    try:
        data = json.loads(fixed)
    except json.JSONDecodeError as e:
        print(f"❌ still invalid after backslash fix: {path}\n   {e}")
        return

    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"🔧 fixed: {path} ({len(data.get('results', []))} sentences)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 fix_json.py <file1.json> [file2.json ...]")
        sys.exit(1)

    for path in sys.argv[1:]:
        fix_file(path)
