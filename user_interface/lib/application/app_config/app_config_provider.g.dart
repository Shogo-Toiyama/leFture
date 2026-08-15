// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_config_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// アプリ全体のメンテナンス/強制アップデート状態を保持する。
/// [AppLifecycleSyncWatcher]から起動時・バックグラウンド復帰時に
/// [refresh]される想定。取得に失敗した場合は直前の状態を維持する
/// (フェイルオープン) — Supabase側の一時的な不調だけで
/// 全ユーザーをロックしてしまわないため。

@ProviderFor(AppConfigController)
final appConfigControllerProvider = AppConfigControllerProvider._();

/// アプリ全体のメンテナンス/強制アップデート状態を保持する。
/// [AppLifecycleSyncWatcher]から起動時・バックグラウンド復帰時に
/// [refresh]される想定。取得に失敗した場合は直前の状態を維持する
/// (フェイルオープン) — Supabase側の一時的な不調だけで
/// 全ユーザーをロックしてしまわないため。
final class AppConfigControllerProvider
    extends $NotifierProvider<AppConfigController, AppConfig> {
  /// アプリ全体のメンテナンス/強制アップデート状態を保持する。
  /// [AppLifecycleSyncWatcher]から起動時・バックグラウンド復帰時に
  /// [refresh]される想定。取得に失敗した場合は直前の状態を維持する
  /// (フェイルオープン) — Supabase側の一時的な不調だけで
  /// 全ユーザーをロックしてしまわないため。
  AppConfigControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appConfigControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appConfigControllerHash();

  @$internal
  @override
  AppConfigController create() => AppConfigController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppConfig>(value),
    );
  }
}

String _$appConfigControllerHash() =>
    r'9c6e6efe7652eff9c3ebd96ae9738cf1d09ca273';

/// アプリ全体のメンテナンス/強制アップデート状態を保持する。
/// [AppLifecycleSyncWatcher]から起動時・バックグラウンド復帰時に
/// [refresh]される想定。取得に失敗した場合は直前の状態を維持する
/// (フェイルオープン) — Supabase側の一時的な不調だけで
/// 全ユーザーをロックしてしまわないため。

abstract class _$AppConfigController extends $Notifier<AppConfig> {
  AppConfig build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AppConfig, AppConfig>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AppConfig, AppConfig>,
              AppConfig,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
