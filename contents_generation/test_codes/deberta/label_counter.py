import json
import os
from collections import Counter
from pathlib import Path

# スクリプトと同じ階層の labeled_transcripts フォルダを参照
base_dir = Path(__file__).parent
target_dir = base_dir / "labeled_transcripts"

if not target_dir.exists():
    print(f"❌ フォルダが見つかりません: {target_dir}")
    exit(1)

json_files = list(target_dir.glob("*.json"))
if not json_files:
    print(f"❌ JSONファイルが見つかりません: {target_dir}")
    exit(1)

print(f"📂 対象フォルダ: {target_dir}")
print(f"📄 JSONファイル数: {len(json_files)} 件\n")

label_counter = Counter()
total_entries = 0
error_files = []

for json_file in sorted(json_files):
    try:
        with open(json_file, "r", encoding="utf-8") as f:
            data = json.load(f)

        results = data.get("results", [])
        for entry in results:
            label = entry.get("label")
            if label is not None:
                label_counter[label] += 1
                total_entries += 1

    except Exception as e:
        error_files.append((json_file.name, str(e)))

# 結果表示
print("=" * 50)
print(f"{'ラベル':<20} {'件数':>8} {'割合':>8}")
print("=" * 50)

for label, count in label_counter.most_common():
    pct = count / total_entries * 100 if total_entries > 0 else 0
    print(f"{label:<20} {count:>8,} {pct:>7.1f}%")

print("=" * 50)
print(f"{'合計':<20} {total_entries:>8,} {'100.0%':>8}")

if error_files:
    print(f"\n⚠️  読み込みエラー ({len(error_files)} 件):")
    for name, err in error_files:
        print(f"  - {name}: {err}")