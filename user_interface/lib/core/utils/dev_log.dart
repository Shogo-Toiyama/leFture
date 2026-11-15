// core/utils/dev_log.dart
//
// dart:developerのlog()は、DevToolsのLoggingページを開いて能動的に見ていないと
// 中身が見えない(`flutter run`の素のターミナルには出てこない)。それだけだと
// ターミナル出力をそのまま貼って診断する普段の使い方と噛み合わないため、
// debugPrint()でも同じ内容を出す(`flutter run`のターミナルにそのまま出る)。
// 加えて、実機単体でも診断できるよう、直近のログをメモリ上に保持しておく
// 軽量なリングバッファも維持する。中身自体はテスト機能に依存しない汎用
// ユーティリティなので dev_tools/ には置かない(見た目のオーバーレイ表示だけが
// isTestMode限定)。
import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

class DevLog {
  DevLog._();

  static const int maxLines = 300;

  static final ValueNotifier<List<String>> lines = ValueNotifier<List<String>>([]);

  /// 整形済みの1行を同期的に受け取るフック。リングバッファと違い、
  /// アプリが止められても残したいログ(UploadTrace)をディスクへ流すために使う。
  /// フック側が例外を投げてもログ呼び出し元には影響させない。
  static void Function(String line)? tap;

  // Keep useful pre-upload context even during hours of per-second timer logs.
  static final List<String> _diagnosticLines = [];
  static List<String> get diagnosticLines => List.unmodifiable(_diagnosticLines);

  static void add(String message) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final timestamp = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    final line = '$timestamp $message';

    // debugPrint()は名前に反してRelease/Profileビルドでも出力されてしまう
    // (assertで保護された処理ではないため)。端末の実ログ(adb logcat /
    // Xcode Console)にuidなどの内部情報が残らないよう、Debugビルドに限定する。
    if (kDebugMode) {
      developer.log(message);
      debugPrint('[DevLog] $line');
    }

    if (!line.contains('[Timer] Tick')) {
      _diagnosticLines.add(line);
      if (_diagnosticLines.length > maxLines) _diagnosticLines.removeAt(0);
    }

    try {
      tap?.call(line);
    } catch (_) {}

    // Widgetツリーのbuildフェーズ中にDevLog.addが呼ばれても
    // setState() or markNeedsBuild() during build例外が起きないよう、
    // ValueNotifierのUI更新はmicrotaskで遅延通知する。
    scheduleMicrotask(() {
      final updated = [...lines.value, line];
      if (updated.length > maxLines) {
        updated.removeRange(0, updated.length - maxLines);
      }
      lines.value = updated;
    });
  }
}
