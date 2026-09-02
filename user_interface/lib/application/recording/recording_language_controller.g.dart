// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recording_language_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 録音言語(オンデバイスASRモデル選択)の設定。永続化と状態管理のみを行う。
/// モデルのダウンロードはここでは行わない — Realtime Recordingが有効な
/// 場合のみ、呼び出し側(言語ピッカーのUI/HomePageの自動チェック)が
/// `AsrModelManager.ensureModelReady`を明示的に呼ぶ(無効なら無駄な
/// ダウンロードを避ける)。

@ProviderFor(RecordingLanguageController)
final recordingLanguageControllerProvider =
    RecordingLanguageControllerProvider._();

/// 録音言語(オンデバイスASRモデル選択)の設定。永続化と状態管理のみを行う。
/// モデルのダウンロードはここでは行わない — Realtime Recordingが有効な
/// 場合のみ、呼び出し側(言語ピッカーのUI/HomePageの自動チェック)が
/// `AsrModelManager.ensureModelReady`を明示的に呼ぶ(無効なら無駄な
/// ダウンロードを避ける)。
final class RecordingLanguageControllerProvider
    extends $NotifierProvider<RecordingLanguageController, String> {
  /// 録音言語(オンデバイスASRモデル選択)の設定。永続化と状態管理のみを行う。
  /// モデルのダウンロードはここでは行わない — Realtime Recordingが有効な
  /// 場合のみ、呼び出し側(言語ピッカーのUI/HomePageの自動チェック)が
  /// `AsrModelManager.ensureModelReady`を明示的に呼ぶ(無効なら無駄な
  /// ダウンロードを避ける)。
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
    r'22c41349f7f64ffcabc0e61c82fe046ab583d6a9';

/// 録音言語(オンデバイスASRモデル選択)の設定。永続化と状態管理のみを行う。
/// モデルのダウンロードはここでは行わない — Realtime Recordingが有効な
/// 場合のみ、呼び出し側(言語ピッカーのUI/HomePageの自動チェック)が
/// `AsrModelManager.ensureModelReady`を明示的に呼ぶ(無効なら無駄な
/// ダウンロードを避ける)。

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
