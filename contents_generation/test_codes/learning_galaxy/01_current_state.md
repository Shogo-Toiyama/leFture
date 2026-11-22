# 現行の銀河の実装状況（2026-11-20 時点、コードで確認）

## 結論
現行の銀河は **見た目だけの装飾**。星は乱数（seed=42）から生成され、講義・コース・学習履歴のデータとは接続されていない
（`galaxy` 関連の Flutter コードを `lecture` / `course` で grep して参照なしを確認）。

## 場所
| 領域 | ファイル |
|---|---|
| Flutter 画面 | `user_interface/lib/presentation/pages/learning_galaxy/learning_galaxy_page.dart`（203行）, route `/learning_galaxy`（`app/routes.dart`） |
| Flutter 描画 | `user_interface/lib/presentation/widgets/galaxy/galaxy_view.dart`（538行） |
| Flutter 状態 | `user_interface/lib/application/galaxy/galaxy_data_provider.dart`（生成済みデータ、379行）, `galaxy_state_provider.dart`（カメラ・自動回転） |
| Flutter 利用箇所 | `home_page.dart`, `combined_header.dart`, `intro_slide_hero.dart`, `goal_tree_page.dart`, `spaceship_announcement_modal.dart`, `plan_theme.dart`, `change_avatar_sheet.dart` |
| Webapp | `webapp/src/components/GalaxyView.tsx`（Home のミニ銀河、website の GalaxyCanvas の移植） |
| Website | `website/src/components/home/GalaxyCanvas.tsx`, `GalaxyScreenshotPage.tsx` |
| 動画 | `video/test/galaxy/` |

## 生成の仕組み
- `GalaxyData` = stars（pos/size/bright/type）, nebula puffs, 背景星, スプライト。アプリ全体で1回だけ生成してキャッシュ。
- `GalaxyConfig`: seed=42, bulgeStarCount=5000, diskStarCount=15000, arms=3 ほか。`copyWith` で上書き可能。
- 動的状態（カメラ回転・ズーム・自動回転）は `galaxyStateProvider`。

## 追加で確認済み（2026-11-21）
- 星の元データ側の部品は既にある: 自己像プロフィール（`profile_observations`、migration `20261007000000_add_self_portrait_profile.sql`）、768次元の pgvector 埋め込み。

## まだ調べていないこと
- 各利用箇所で銀河がどう使われているか（タップ動作の有無など）
- Supabase 側に銀河専用のテーブル・カラムがあるか
- 描画性能（実機での FPS・星の数の上限）
