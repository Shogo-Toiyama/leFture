// core/utils/dev_log.dart
//
// dart:developerのlog()はターミナル/DevToolsが繋がっていないと見えないため、
// 実機単体でも診断できるよう、直近のログをメモリ上に保持しておく軽量な
// リングバッファ。中身自体はテスト機能に依存しない汎用ユーティリティなので
// dev_tools/には置かない（見た目のオーバーレイ表示だけがisTestMode限定）。
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

class DevLog {
  DevLog._();

  static const int maxLines = 300;

  static final ValueNotifier<List<String>> lines = ValueNotifier<List<String>>([]);

  static void add(String message) {
    developer.log(message);

    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final timestamp = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';

    final updated = [...lines.value, '$timestamp $message'];
    if (updated.length > maxLines) {
      updated.removeRange(0, updated.length - maxLines);
    }
    lines.value = updated;
  }
}
