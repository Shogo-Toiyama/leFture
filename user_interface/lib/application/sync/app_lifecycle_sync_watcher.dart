import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:lefture/application/app_config/app_config_provider.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/core/utils/connectivity_utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_lifecycle_sync_watcher.g.dart';

/// バックグラウンド復帰・オフライン→オンライン復帰を検知し、
/// LectureControllerのdifferential pullと、AppConfig(メンテナンス/
/// 強制アップデート状態)の再取得を再発火させるウォッチャー。
///
/// これが無いと、Pull同期はUIイベント(Home画面表示・Pull-to-Refresh等)
/// にしか駆動されず、アプリを開かないユーザーに対してサーバー側の変更が
/// 届かない期間が任意に長くなってしまう。AppConfigについても同様に、
/// Realtime購読のような常時接続を持たない代わりに、このタイミングで
/// 定期的に最新状態を確認する。
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
    // コールドスタート時にも一度確認しておく。
    _triggerAppConfigRefresh();

    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        _triggerBootstrap();
        _triggerAppConfigRefresh();
      },
    );

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      event,
    ) {
      final isOffline = isConnectivityOffline(event);
      if (_wasOffline && !isOffline) {
        _triggerBootstrap();
        _triggerAppConfigRefresh();
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

  void _triggerAppConfigRefresh() {
    _ref.read(appConfigControllerProvider.notifier).refresh();
  }
}
