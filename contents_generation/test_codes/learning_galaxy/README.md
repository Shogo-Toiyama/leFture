# Learning Galaxy workspace

現在は飾りでしかない「銀河」を、学習データと結びついた意味のある **Learning Galaxy** に作り変えるための、計画・設計・実験の専用ワークスペース。
大規模な計画なので、小さく試しながら進める。本番コードは、ここで検証してから触る（AGENTS.md の実験ルールに従う）。

## 構成

| パス | 役割 |
|---|---|
| `concept/00_concept.md` | コンセプト原本。ユーザーの説明を、言葉を変えずに保存する場所 |
| `concept/01_open_questions.md` | コンセプトのうち、まだ決まっていない点・確認が必要な点 |
| `01_current_state.md` | 現行の銀河の実装状況（コードで確認した事実のみ） |
| `02_plan.md` | 段階的な計画（フェーズ・各フェーズの完了条件） |
| `03_design.md` | 設計（データモデル、描画、API、UI） |
| `04_decisions.md` | 決定ログ（日付・決めたこと・理由・却下した案） |
| `experiments/<日付_名前>/` | 個別実験。1実験1フォルダ |
| `results/` | 実験の結果と要約（タイムスタンプ付き） |

## 運用ルール

- コンセプトの説明を受けたら、まず `concept/00_concept.md` に原文のまま追記し、要約・解釈は別に書く。
- 事実と推測を区別する。不明な点は「不明」と書き、`concept/01_open_questions.md` に積む。
- 実験は本番と同じ Supabase データ・バックエンドコードを使い、API を呼ぶ前に必ず dry-run する。
- 結果のコミット前に `python3 tools/experiment_privacy/check_results.py` を実行する（他人の講義内容はコミットしない）。
- 決まったことは `04_decisions.md` に必ず残す。
