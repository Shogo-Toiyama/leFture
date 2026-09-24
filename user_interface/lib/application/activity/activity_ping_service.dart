import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'activity_ping_service.g.dart';

/// 「ユーザーがアプリを使っている」ことをSupabaseに記録する(ping)。
///
/// ■ なぜこれが要るのか
/// アクティブユーザーを auth.users.last_sign_in_at から測ることはできない。
/// GoTrueがあれを更新するのは明示的なサインイン(パスワード/OAuth/OTP)の
/// ときだけで、リフレッシュトークンによるセッション更新では更新されないため、
/// 「毎日使っているのに最終ログインは3ヶ月前」が普通に起きる。
/// かといって lectures や review_cards の updated_at から推測すると、機能が
/// 増えるたびに集計の定義を更新し続けることになり、更新し忘れた機能は静かに
/// 計測から漏れる。だから「使っている」を明示的に1経路で記録する。
///
/// ■ なぜ10分おきなのか
/// サーバー側(user_activity_hours)は (user_id, 時, platform) が主キーなので、
/// 10分おきに打っても同じ1時間の行にUPSERTで畳み込まれる —— つまり行数は
/// 「実際に触った時間数」しか増えない。増えるのは ping_count で、これが
/// 「その1時間をどれだけ使ったか」(最大6)を表す。起動時だけのpingだと
/// 2時間の授業が「開始時刻の1行」に潰れてしまう。
///
/// ■ フォアグラウンドのときだけ打つ
/// バックグラウンドに退避したアプリを「使っている」と数えると、利用時間帯の
/// 分布が意味を失う。AppLifecycleListenerでresume/pauseに追従する
/// (app_lifecycle_sync_watcher.dart と同じパターン)。
@Riverpod(keepAlive: true)
ActivityPingService activityPingService(Ref ref) {
  final service = ActivityPingService();
  service.initialize();
  ref.onDispose(service.dispose);
  return service;
}

class ActivityPingService {
  static const _interval = Duration(minutes: 10);

  /// 直前のpingからこれだけ経っていなければ送らない。インターバルより少し
  /// 短くしてあるのは、タイマーの発火がわずかに遅れただけでスキップされるのを
  /// 避けるため。アプリを短時間に何度も起動し直した場合の重複もここで抑える。
  static const _throttle = Duration(minutes: 9);

  Timer? _timer;
  AppLifecycleListener? _lifecycleListener;
  StreamSubscription<AuthState>? _authSubscription;
  DateTime? _lastPingAt;

  void initialize() {
    _lifecycleListener = AppLifecycleListener(
      onResume: _start,
      onPause: _stopTimer,
      onHide: _stopTimer,
    );

    _authSubscription = supabase.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedOut) {
        _stopTimer();
      } else if (state.event == AuthChangeEvent.signedIn) {
        _start();
      }
    });

    // コールドスタート時。セッションが復元済みならこの時点で1回打つ。
    _start();
  }

  void dispose() {
    _stopTimer();
    _lifecycleListener?.dispose();
    _authSubscription?.cancel();
  }

  void _start() {
    if (supabase.auth.currentSession == null) return;
    unawaited(_send());
    _timer ??= Timer.periodic(_interval, (_) => unawaited(_send()));
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _send() async {
    if (supabase.auth.currentSession == null) return;

    final now = DateTime.now();
    final last = _lastPingAt;
    if (last != null && now.difference(last) < _throttle) return;
    // 先に記録してから送る(応答待ちの間に重複して送らないため)。
    _lastPingAt = now;

    try {
      await supabase.rpc(
        'touch_activity',
        params: {
          'p_platform': _platform,
          // Dartの timeZoneOffset は「UTCからどれだけ進んでいるか」(東京=+540)。
          // サーバー側も東が正なので、こちらは符号をそのまま渡してよい
          // (符号を反転する必要があるのはJavaScriptのgetTimezoneOffset()の方)。
          'p_tz_offset_minutes': now.timeZoneOffset.inMinutes,
        },
      );
    } catch (e) {
      // 計測であって機能ではない。失敗してもユーザーの操作を妨げない。
      DevLog.add('⚠️ Failed to send activity ping: $e');
    }
  }

  /// dart:io の Platform ではなく defaultTargetPlatform を使う ——
  /// dart:io はWebビルドでコンパイルできないため(このアプリはweb/も持っている)。
  String get _platform {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return 'unknown';
    }
  }
}
