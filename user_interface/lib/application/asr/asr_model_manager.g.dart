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
/// 言語は3段構成: `manifest.languages`にエントリがあればTier1(streaming_zipformer)
/// またはTier2(sense_voice、あわせて共有VADも必要)。無ければTier3として
/// 共有Whisper(+共有VAD)にフォールバックする。
///
/// ストレージは、VADを除く(Whisperは含む)グループを最大[_maxResidentGroups]個
/// までしか同時保持しない。3個目をダウンロードする際は、最も長く使われて
/// いない(lastUsedAt基準)グループを自動的に退避する。

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
/// 言語は3段構成: `manifest.languages`にエントリがあればTier1(streaming_zipformer)
/// またはTier2(sense_voice、あわせて共有VADも必要)。無ければTier3として
/// 共有Whisper(+共有VAD)にフォールバックする。
///
/// ストレージは、VADを除く(Whisperは含む)グループを最大[_maxResidentGroups]個
/// までしか同時保持しない。3個目をダウンロードする際は、最も長く使われて
/// いない(lastUsedAt基準)グループを自動的に退避する。
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
  /// 言語は3段構成: `manifest.languages`にエントリがあればTier1(streaming_zipformer)
  /// またはTier2(sense_voice、あわせて共有VADも必要)。無ければTier3として
  /// 共有Whisper(+共有VAD)にフォールバックする。
  ///
  /// ストレージは、VADを除く(Whisperは含む)グループを最大[_maxResidentGroups]個
  /// までしか同時保持しない。3個目をダウンロードする際は、最も長く使われて
  /// いない(lastUsedAt基準)グループを自動的に退避する。
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

String _$asrModelManagerHash() => r'153da0b864e49f66a4904dbc8fadde20c9223a0a';

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
/// 言語は3段構成: `manifest.languages`にエントリがあればTier1(streaming_zipformer)
/// またはTier2(sense_voice、あわせて共有VADも必要)。無ければTier3として
/// 共有Whisper(+共有VAD)にフォールバックする。
///
/// ストレージは、VADを除く(Whisperは含む)グループを最大[_maxResidentGroups]個
/// までしか同時保持しない。3個目をダウンロードする際は、最も長く使われて
/// いない(lastUsedAt基準)グループを自動的に退避する。

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
