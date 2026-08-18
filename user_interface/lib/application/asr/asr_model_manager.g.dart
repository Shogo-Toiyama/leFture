// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'asr_model_manager.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 録音言語ごとのオンデバイスASRモデルのダウンロード/バージョン整合性を管理する。
/// RecordingPageに入った瞬間と、録音言語の設定を変更した瞬間の2箇所から
/// `ensureModelReady`が呼ばれる想定(プロアクティブダウンロード)。
///
/// マニフェストの`engineCompatVersion`(モデル形式に影響する変更があった時だけ
/// 上げる)と`modelVersion`(モデル本体だけ差し替えたい時に上げる)を、ローカル
/// キャッシュ(LocalAsrModels)のタグと突き合わせて再ダウンロードが必要か判定する。
/// 失敗時は既存のreadyなモデルを壊さない(新しいダウンロードが成功するまで
/// 古いモデルを使い続けられるようにする、堅牢性優先)。
///
/// 全言語が共有Whisper(+共有VAD)の2アセットのみを使うため、常にこの2つだけを
/// 常駐させればよく、複数言語モデルを退避するLRU管理は不要。

@ProviderFor(AsrModelManager)
final asrModelManagerProvider = AsrModelManagerProvider._();

/// 録音言語ごとのオンデバイスASRモデルのダウンロード/バージョン整合性を管理する。
/// RecordingPageに入った瞬間と、録音言語の設定を変更した瞬間の2箇所から
/// `ensureModelReady`が呼ばれる想定(プロアクティブダウンロード)。
///
/// マニフェストの`engineCompatVersion`(モデル形式に影響する変更があった時だけ
/// 上げる)と`modelVersion`(モデル本体だけ差し替えたい時に上げる)を、ローカル
/// キャッシュ(LocalAsrModels)のタグと突き合わせて再ダウンロードが必要か判定する。
/// 失敗時は既存のreadyなモデルを壊さない(新しいダウンロードが成功するまで
/// 古いモデルを使い続けられるようにする、堅牢性優先)。
///
/// 全言語が共有Whisper(+共有VAD)の2アセットのみを使うため、常にこの2つだけを
/// 常駐させればよく、複数言語モデルを退避するLRU管理は不要。
final class AsrModelManagerProvider
    extends
        $NotifierProvider<AsrModelManager, Map<String, AsrLanguageModelState>> {
  /// 録音言語ごとのオンデバイスASRモデルのダウンロード/バージョン整合性を管理する。
  /// RecordingPageに入った瞬間と、録音言語の設定を変更した瞬間の2箇所から
  /// `ensureModelReady`が呼ばれる想定(プロアクティブダウンロード)。
  ///
  /// マニフェストの`engineCompatVersion`(モデル形式に影響する変更があった時だけ
  /// 上げる)と`modelVersion`(モデル本体だけ差し替えたい時に上げる)を、ローカル
  /// キャッシュ(LocalAsrModels)のタグと突き合わせて再ダウンロードが必要か判定する。
  /// 失敗時は既存のreadyなモデルを壊さない(新しいダウンロードが成功するまで
  /// 古いモデルを使い続けられるようにする、堅牢性優先)。
  ///
  /// 全言語が共有Whisper(+共有VAD)の2アセットのみを使うため、常にこの2つだけを
  /// 常駐させればよく、複数言語モデルを退避するLRU管理は不要。
  AsrModelManagerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'asrModelManagerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$asrModelManagerHash();

  @$internal
  @override
  AsrModelManager create() => AsrModelManager();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, AsrLanguageModelState> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, AsrLanguageModelState>>(
        value,
      ),
    );
  }
}

String _$asrModelManagerHash() => r'd6e42107c609734b9aeab7fec6cd26d81a656fd7';

/// 録音言語ごとのオンデバイスASRモデルのダウンロード/バージョン整合性を管理する。
/// RecordingPageに入った瞬間と、録音言語の設定を変更した瞬間の2箇所から
/// `ensureModelReady`が呼ばれる想定(プロアクティブダウンロード)。
///
/// マニフェストの`engineCompatVersion`(モデル形式に影響する変更があった時だけ
/// 上げる)と`modelVersion`(モデル本体だけ差し替えたい時に上げる)を、ローカル
/// キャッシュ(LocalAsrModels)のタグと突き合わせて再ダウンロードが必要か判定する。
/// 失敗時は既存のreadyなモデルを壊さない(新しいダウンロードが成功するまで
/// 古いモデルを使い続けられるようにする、堅牢性優先)。
///
/// 全言語が共有Whisper(+共有VAD)の2アセットのみを使うため、常にこの2つだけを
/// 常駐させればよく、複数言語モデルを退避するLRU管理は不要。

abstract class _$AsrModelManager
    extends $Notifier<Map<String, AsrLanguageModelState>> {
  Map<String, AsrLanguageModelState> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<
              Map<String, AsrLanguageModelState>,
              Map<String, AsrLanguageModelState>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, AsrLanguageModelState>,
                Map<String, AsrLanguageModelState>
              >,
              Map<String, AsrLanguageModelState>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
