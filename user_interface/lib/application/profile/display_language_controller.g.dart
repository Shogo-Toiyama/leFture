// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'display_language_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// アプリ画面表示言語（Display Language）の状態管理。
/// 変更はすぐに [RecordingPreferences] に永続化される。
/// 今後 Flutter の Locale 連動等を実装する際はここを拡張する。

@ProviderFor(DisplayLanguageController)
final displayLanguageControllerProvider = DisplayLanguageControllerProvider._();

/// アプリ画面表示言語（Display Language）の状態管理。
/// 変更はすぐに [RecordingPreferences] に永続化される。
/// 今後 Flutter の Locale 連動等を実装する際はここを拡張する。
final class DisplayLanguageControllerProvider
    extends $NotifierProvider<DisplayLanguageController, String> {
  /// アプリ画面表示言語（Display Language）の状態管理。
  /// 変更はすぐに [RecordingPreferences] に永続化される。
  /// 今後 Flutter の Locale 連動等を実装する際はここを拡張する。
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
    r'50c8ff6e5dba7ea0910b3153a208d93ce3bd6706';

/// アプリ画面表示言語（Display Language）の状態管理。
/// 変更はすぐに [RecordingPreferences] に永続化される。
/// 今後 Flutter の Locale 連動等を実装する際はここを拡張する。

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
