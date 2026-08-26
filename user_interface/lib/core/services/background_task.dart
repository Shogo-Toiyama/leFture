import 'dart:io';

import 'package:flutter/services.dart';
import 'package:lefture/core/utils/dev_log.dart';

/// OSにアプリを止められては困る短い処理を、実行猶予で包むためのヘルパー。
///
/// ★ 背景:
/// 録音の保存処理は `AudioRecorderService.stop()` の時点でオーディオセッションが
/// 終わり、`UIBackgroundModes: audio` の保護が切れる。その直後に走る
/// FFmpegのエンコードは、画面ロック・アプリ切替が起きるとiOSに数秒で
/// 止められてしまう。エンコードが終わらないとアップロードジョブが1件も
/// 作られず、録音は端末に取り残されてサーバーへ一切届かない。
///
/// [protect]で包むと、iOSに明示的な実行猶予(概ね30秒)を要求する。実測では
/// 90分の講義でもエンコードは10秒前後なので、通常はこれで足りる。
/// 万一足りなかった場合は期限切れハンドラが走って処理は中断されるが、
/// その録音は次回起動時のサルベージが拾い直す。
///
/// AndroidではForeground Service(flutter_background)が同じ役割を果たすため、
/// ここは何もしない no-op になる。
class BackgroundTask {
  BackgroundTask._();

  static const MethodChannel _channel = MethodChannel('lefture/background_task');

  /// 実行猶予を要求する。取得できなければnull(呼び出し側は保護なしで続行してよい)。
  static Future<int?> begin(String name) async {
    if (!Platform.isIOS) return null;
    try {
      final id = await _channel.invokeMethod<int>('begin', {'name': name});
      if (id == null || id < 0) {
        DevLog.add('⚠️ [BackgroundTask] "$name": could not acquire background time.');
        return null;
      }
      return id;
    } catch (e) {
      // プラットフォーム側が応答しなくても、処理そのものは続けたい。
      DevLog.add('⚠️ [BackgroundTask] "$name": begin failed: $e');
      return null;
    }
  }

  /// 猶予を返上する。[id]がnull(取得できていない)なら何もしない。
  static Future<void> end(int? id) async {
    if (id == null || !Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('end', {'id': id});
    } catch (e) {
      DevLog.add('⚠️ [BackgroundTask] end failed: $e');
    }
  }

  /// 残りの実行猶予(秒)。フォアグラウンドでは事実上無制限を意味する巨大な値が
  /// 返るため、診断ログでは[formatRemaining]を通して読むこと。
  static Future<double?> remainingSeconds() async {
    if (!Platform.isIOS) return null;
    try {
      return await _channel.invokeMethod<double>('remainingSeconds');
    } catch (_) {
      return null;
    }
  }

  static String formatRemaining(double? seconds) {
    if (seconds == null) return 'n/a';
    // フォアグラウンドではDouble.greatestFiniteMagnitudeが返る。
    if (seconds > 60 * 60) return 'unlimited (foreground)';
    return '${seconds.toStringAsFixed(1)}s';
  }

  /// [action]を実行猶予で包んで実行する。成否にかかわらず必ず猶予を返上する。
  static Future<T> protect<T>(String name, Future<T> Function() action) async {
    final id = await begin(name);
    try {
      return await action();
    } finally {
      await end(id);
    }
  }
}
