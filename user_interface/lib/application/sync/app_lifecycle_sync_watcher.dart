import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:lefture/application/app_config/app_config_provider.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/core/utils/connectivity_utils.dart';
import 'package:lefture/core/utils/dev_log.dart';
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
@Riverpod(
  keepAlive: true,
  dependencies: [LectureController, AppConfigController],
)
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
      // ★ デバッグ用: バックグラウンド転送(継続エンコード/background_downloader
      // のアップロード)が「本当にロック/バックグラウンド中も裏で動き続けて
      // いるか」を、他のログと突き合わせて確認できるようにする。
      // resumed: フォアグラウンド表示中。inactive: フォアグラウンドだが
      // 一時的に非アクティブ(通知センターを開いた・電話がかかってきた等、
      // 画面ロックの一瞬もここを通る)。paused: バックグラウンドへ完全に
      // 退避(画面ロック・ホームに戻る等はここに落ち着く)。
      onStateChange: (state) {
        DevLog.add('📱 [AppLifecycle] $state');
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
