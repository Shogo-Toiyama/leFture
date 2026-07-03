// presentation/pages/dev_tools/test_mode_flag.dart
//
// Tier 1 テストハーネス（dev_tools/フォルダ全体）を有効にするかどうかの
// コンパイル時フラグ。kDebugModeは使わない — デバッグモード(flutter run)は
// バックグラウンド実行の検証に使えない(実証済み)ため、リリースビルドのまま
// 明示的にオンにできる必要がある。
//
// 有効化する場合:
//   flutter run --release --dart-define=IS_TEST_MODE=true -d <device>
//
// 何も指定しなければ常にfalseになり、Testタブ関連のコードはtree-shakingで
// 実質バイナリから除去される。
const bool isTestMode = bool.fromEnvironment('IS_TEST_MODE', defaultValue: false);
