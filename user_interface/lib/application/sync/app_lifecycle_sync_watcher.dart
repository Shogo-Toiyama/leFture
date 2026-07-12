import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_lifecycle_sync_watcher.g.dart';

/// バックグラウンド復帰・オフライン→オンライン復帰を検知し、
/// LectureControllerのdifferential pullを再発火させるウォッチャー。
///
/// これが無いと、Pull同期はUIイベント(Home画面表示・Pull-to-Refresh等)
/// にしか駆動されず、アプリを開かないユーザーに対してサーバー側の変更が
/// 届かない期間が任意に長くなってしまう。
@Riverpod(keepAlive: true)
AppLifecycleSyncWatcher appLifecycleSyncWatcher(Ref ref) {
  final watcher = AppLifecycleSyncWatcher(ref);
  watcher.initialize();
  ref.onDispose(watcher.dispose);
  return watcher;
}

class AppLifecycleSyncWatcher {
  AppLifecycleSyncWatcher(this._ref);

  final Ref _ref;
  AppLifecycleListener? _lifecycleListener;
  StreamSubscription? _connectivitySubscription;
  bool _wasOffline = false;

  void initialize() {
    _lifecycleListener = AppLifecycleListener(
      onResume: _triggerBootstrap,
    );

    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((event) {
      final isOffline = _isOffline(event);
      if (_wasOffline && !isOffline) {
        _triggerBootstrap();
      }
      _wasOffline = isOffline;
    });
  }

  void dispose() {
    _lifecycleListener?.dispose();
    _connectivitySubscription?.cancel();
  }

  void _triggerBootstrap() {
    _ref.read(lectureControllerProvider.notifier).bootstrapIfNeeded();
  }

  bool _isOffline(dynamic results) {
    if (results is List<ConnectivityResult>) {
      return results.contains(ConnectivityResult.none);
    }
    if (results is ConnectivityResult) {
      return results == ConnectivityResult.none;
    }
    return false;
  }
}
