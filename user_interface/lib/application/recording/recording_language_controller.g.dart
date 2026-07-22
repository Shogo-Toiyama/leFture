// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recording_language_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 録音言語(オンデバイスASRモデル選択)の設定。変更した瞬間にその言語の
/// モデルダウンロード/バージョン整合性チェックをキックする(プロアクティブ
/// ダウンロード)。もう1つのチェックポイント(RecordingPage入場時)は
/// RecordingController.requestMicPermissionEarly() 側から呼ぶ。

@ProviderFor(RecordingLanguageController)
final recordingLanguageControllerProvider =
    RecordingLanguageControllerProvider._();

/// 録音言語(オンデバイスASRモデル選択)の設定。変更した瞬間にその言語の
/// モデルダウンロード/バージョン整合性チェックをキックする(プロアクティブ
/// ダウンロード)。もう1つのチェックポイント(RecordingPage入場時)は
/// RecordingController.requestMicPermissionEarly() 側から呼ぶ。
final class RecordingLanguageControllerProvider
    extends $NotifierProvider<RecordingLanguageController, String> {
  /// 録音言語(オンデバイスASRモデル選択)の設定。変更した瞬間にその言語の
  /// モデルダウンロード/バージョン整合性チェックをキックする(プロアクティブ
  /// ダウンロード)。もう1つのチェックポイント(RecordingPage入場時)は
  /// RecordingController.requestMicPermissionEarly() 側から呼ぶ。
  RecordingLanguageControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recordingLanguageControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recordingLanguageControllerHash();

  @$internal
  @override
  RecordingLanguageController create() => RecordingLanguageController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$recordingLanguageControllerHash() =>
    r'53af728f5dc27024c2bad9b92783c1d2bbb8d9d2';

/// 録音言語(オンデバイスASRモデル選択)の設定。変更した瞬間にその言語の
/// モデルダウンロード/バージョン整合性チェックをキックする(プロアクティブ
/// ダウンロード)。もう1つのチェックポイント(RecordingPage入場時)は
/// RecordingController.requestMicPermissionEarly() 側から呼ぶ。

abstract class _$RecordingLanguageController extends $Notifier<String> {
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
