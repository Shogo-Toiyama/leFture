// core/config/error_visibility.dart
//
// 「生の例外文字列を画面に出してよいビルドか」を表すコンパイル時定数。
//
// なぜ2つをORするか:
//   - kDebugMode ... 素の `flutter run` で開発しているとき。
//   - isTestMode ... `flutter run --release --dart-define=IS_TEST_MODE=true`。
//     デバッグモードはバックグラウンド実行の検証に使えない(実証済み)ため、
//     このプロジェクトではリリースビルドのまま診断機能を開けられるように
//     しており、DevLogOverlayも同じフラグで出している。
//
// どちらもコンパイル時定数なので、App Store提出ビルド
// (--dart-define を渡さない release)では `false` に畳まれ、
// 技術詳細を描画するコードごとtree-shakingでバイナリから消える。
// = 配信版のユーザーには、生の例外文字列は一切到達しない。
import 'package:flutter/foundation.dart' show kDebugMode;

import 'package:lefture/presentation/pages/dev_tools/test_mode_flag.dart';

/// 生の例外文字列・スタックトレース・fingerprintを画面に出してよいか。
/// **ユーザー向けの分岐には絶対に使わないこと** — これは「開発者が自分の
/// 端末で見るための窓」を開けるかどうかだけを表す。
const bool showTechnicalErrorDetails = kDebugMode || isTestMode;
