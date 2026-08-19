// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'display_language_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// アプリ画面表示言語（Display Language）の状態管理。
/// 変更はすぐに [RecordingPreferences] に永続化され、[userProfileRepositoryProvider] 経由で
/// user_profiles の metadata (display_language) および Supabase Auth へ同期される。

@ProviderFor(DisplayLanguageController)
final displayLanguageControllerProvider = DisplayLanguageControllerProvider._();

/// アプリ画面表示言語（Display Language）の状態管理。
/// 変更はすぐに [RecordingPreferences] に永続化され、[userProfileRepositoryProvider] 経由で
/// user_profiles の metadata (display_language) および Supabase Auth へ同期される。
final class DisplayLanguageControllerProvider
    extends $NotifierProvider<DisplayLanguageController, String> {
  /// アプリ画面表示言語（Display Language）の状態管理。
  /// 変更はすぐに [RecordingPreferences] に永続化され、[userProfileRepositoryProvider] 経由で
  /// user_profiles の metadata (display_language) および Supabase Auth へ同期される。
  DisplayLanguageControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'displayLanguageControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$displayLanguageControllerHash();

  @$internal
  @override
  DisplayLanguageController create() => DisplayLanguageController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$displayLanguageControllerHash() =>
    r'a59c8b47362022117737c3b64a5b8f26b97eb52a';

/// アプリ画面表示言語（Display Language）の状態管理。
/// 変更はすぐに [RecordingPreferences] に永続化され、[userProfileRepositoryProvider] 経由で
/// user_profiles の metadata (display_language) および Supabase Auth へ同期される。

abstract class _$DisplayLanguageController extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
