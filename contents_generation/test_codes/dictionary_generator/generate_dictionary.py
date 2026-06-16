import re
from collections import defaultdict

def parse_prefix(p):
    parts = p.split('-')
    val = []
    for part in parts:
        try:
            val.append(int(part))
        except ValueError:
            val.append(part)
    return tuple(val)

def process_dictionary(input_file, output_file):
    # 1. ファイルの読み込み
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"エラー: {input_file} が見つかりません。")
        return

    # 単語ごとにプレフィックスをセットで格納 (重複排除)
    word_to_prefixes = defaultdict(set)
    # 単語の出現順を保持しつつ、ユニークな単語リストを作る
    words_seen = []

    for line in lines:
        line = line.strip()
        if not line:
            continue
        
        # 2. プレフィックス (例: "1-1:") と単語本体を分離する
        # パターン: 先頭の「数字-数字:」または「数字:」とその後のスペース
        match = re.match(r'^(\d+-\d+|\d+):\s*(.*)$', line)
        if match:
            prefix = match.group(1)
            word_part = match.group(2)
        else:
            prefix = ""
            word_part = line

        # 3. [cite...] とその直前の空白を正規表現で削除
        cleaned_word = re.sub(r'\s*\[cite.*?\]', '', word_part, flags=re.IGNORECASE).strip()
        
        if not cleaned_word:
            continue

        if cleaned_word not in word_to_prefixes:
            words_seen.append(cleaned_word)
        
        if prefix:
            word_to_prefixes[cleaned_word].add(prefix)

    # 4. 出力用のリストを組み立てる
    processed_entries = []
    for word in words_seen:
        prefixes = word_to_prefixes[word]
        if prefixes:
            # プレフィックスを数値的にソート (例: 8-2, 16-5, 16-10)
            sorted_prefixes = sorted(list(prefixes), key=parse_prefix)
            prefixes_str = ", ".join(sorted_prefixes)
            formatted_entry = f"{word} ...... {prefixes_str}"
        else:
            formatted_entry = word
        processed_entries.append((word, formatted_entry))

    # 5. 大文字・小文字を区別せずにアルファベット順にソート (比較用単語の小文字でソート)
    processed_entries.sort(key=lambda x: x[0].lower())

    # 6. 頭文字ごとにグループ化
    grouped_entries = defaultdict(list)
    for cleaned_word, formatted_entry in processed_entries:
        # 頭文字を取得 (空文字列の場合は適当に処理)
        first_char = cleaned_word[0].upper() if cleaned_word else ''
        # アルファベットのA〜Zであればその文字、記号などは 'Symbols' に分類
        if 'A' <= first_char <= 'Z':
            grouped_entries[first_char].append(formatted_entry)
        else:
            grouped_entries['Symbols'].append(formatted_entry)

    # 7. 出力用のテキストを組み立てる
    output_lines = []

    # まず 'Symbols' を出力
    if 'Symbols' in grouped_entries:
        output_lines.append("Symbols")
        output_lines.extend(grouped_entries['Symbols'])
        output_lines.append("")  # グループ間の空行

    # AからZまで順番に出力
    for char in sorted(k for k in grouped_entries.keys() if k != 'Symbols'):
        output_lines.append(char)
        output_lines.extend(grouped_entries[char])
        output_lines.append("")  # グループ間の空行

    # 8. ファイルへの書き込み
    with open(output_file, 'w', encoding='utf-8') as f:
        # 最後の余分な改行を削ってから書き込み
        f.write('\n'.join(output_lines).strip() + '\n')
        
    print(f"処理が完了しました！結果は {output_file} に保存されています。")

# 実行部分
if __name__ == "__main__":
    process_dictionary('input.txt', 'output.txt')
