# 名前のある星・名前のない星の数を数える実験（2026-11-22）

問い: 開発者本人のチャット（ほぼ宿題とテスト勉強）から、名前のある星は何個生まれるか。それぞれに、案2（`../../03_design.md`）の5種類の根拠で数えた名前のない星はいくつ付くか。

| ファイル | 役割 |
|---|---|
| `star_finder_prompt.txt` | 名前のある星と根拠を抽出するプロンプト（英語） |
| `run.py` | Supabase から読み、抽出・引用の検証・根拠の集計・embedding まで行う。`--dry-run` で API を呼ばずに確認 |
| `inputs/` | チャットの生データ（git 管理外） |
| `results/` | 結果（`*_stars.json`）と要約（`*_summary.md`） |

実行: `.venv/bin/python contents_generation/test_codes/learning_galaxy/experiments/2026-11-22_named_star_count/run.py [--dry-run] [--refresh]`

対象は allowlist の developer のみ。
