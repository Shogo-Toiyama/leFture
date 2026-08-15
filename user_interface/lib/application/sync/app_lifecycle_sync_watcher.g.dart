// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_lifecycle_sync_watcher.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// バックグラウンド復帰・オフライン→オンライン復帰を検知し、
/// LectureControllerのdifferential pullと、AppConfig(メンテナンス/
/// 強制アップデート状態)の再取得を再発火させるウォッチャー。
///
/// これが無いと、Pull同期はUIイベント(Home画面表示・Pull-to-Refresh等)
/// にしか駆動されず、アプリを開かないユーザーに対してサーバー側の変更が
/// 届かない期間が任意に長くなってしまう。AppConfigについても同様に、
/// Realtime購読のような常時接続を持たない代わりに、このタイミングで
/// 定期的に最新状態を確認する。

@ProviderFor(appLifecycleSyncWatcher)
final appLifecycleSyncWatcherProvider = AppLifecycleSyncWatcherProvider._();

/// バックグラウンド復帰・オフライン→オンライン復帰を検知し、
/// LectureControllerのdifferential pullと、AppConfig(メンテナンス/
/// 強制アップデート状態)の再取得を再発火させるウォッチャー。
///
/// これが無いと、Pull同期はUIイベント(Home画面表示・Pull-to-Refresh等)
/// にしか駆動されず、アプリを開かないユーザーに対してサーバー側の変更が
/// 届かない期間が任意に長くなってしまう。AppConfigについても同様に、
/// Realtime購読のような常時接続を持たない代わりに、このタイミングで
/// 定期的に最新状態を確認する。

final class AppLifecycleSyncWatcherProvider
    extends
        $FunctionalProvider<
          AppLifecycleSyncWatcher,
          AppLifecycleSyncWatcher,
          AppLifecycleSyncWatcher
        >
    with $Provider<AppLifecycleSyncWatcher> {
  /// バックグラウンド復帰・オフライン→オンライン復帰を検知し、
  /// LectureControllerのdifferential pullと、AppConfig(メンテナンス/
  /// 強制アップデート状態)の再取得を再発火させるウォッチャー。
  ///
  /// これが無いと、Pull同期はUIイベント(Home画面表示・Pull-to-Refresh等)
  /// にしか駆動されず、アプリを開かないユーザーに対してサーバー側の変更が
  /// 届かない期間が任意に長くなってしまう。AppConfigについても同様に、
  /// Realtime購読のような常時接続を持たない代わりに、このタイミングで
  /// 定期的に最新状態を確認する。
  AppLifecycleSyncWatcherProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appLifecycleSyncWatcherProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appLifecycleSyncWatcherHash();

  @$internal
  @override
  $ProviderElement<AppLifecycleSyncWatcher> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AppLifecycleSyncWatcher create(Ref ref) {
    return appLifecycleSyncWatcher(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppLifecycleSyncWatcher value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppLifecycleSyncWatcher>(value),
    );
  }
}

String _$appLifecycleSyncWatcherHash() =>
    r'ae87db6d13ba28920522aaaf1a255c9e8939bac9';
