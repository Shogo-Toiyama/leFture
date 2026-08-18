// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'live_asr_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// [LiveAsrController]が持つエンジンの稼働状況。認識テキスト本体
/// ([LiveAsrController]のstate)とは更新頻度も用途も違うため、別のproviderに
/// 分けている(テキストが増えないタイミングでも毎秒動く表示に使うため)。

@ProviderFor(LiveAsrStatus)
final liveAsrStatusProvider = LiveAsrStatusProvider._();

/// [LiveAsrController]が持つエンジンの稼働状況。認識テキスト本体
/// ([LiveAsrController]のstate)とは更新頻度も用途も違うため、別のproviderに
/// 分けている(テキストが増えないタイミングでも毎秒動く表示に使うため)。
final class LiveAsrStatusProvider
    extends $NotifierProvider<LiveAsrStatus, LiveAsrStatusState> {
  /// [LiveAsrController]が持つエンジンの稼働状況。認識テキスト本体
  /// ([LiveAsrController]のstate)とは更新頻度も用途も違うため、別のproviderに
  /// 分けている(テキストが増えないタイミングでも毎秒動く表示に使うため)。
  LiveAsrStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'liveAsrStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$liveAsrStatusHash();

  @$internal
  @override
  LiveAsrStatus create() => LiveAsrStatus();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LiveAsrStatusState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LiveAsrStatusState>(value),
    );
  }
}

String _$liveAsrStatusHash() => r'ae7492fa3d136a07a9a29731801e9eafacd8a7f2';

/// [LiveAsrController]が持つエンジンの稼働状況。認識テキスト本体
/// ([LiveAsrController]のstate)とは更新頻度も用途も違うため、別のproviderに
/// 分けている(テキストが増えないタイミングでも毎秒動く表示に使うため)。

abstract class _$LiveAsrStatus extends $Notifier<LiveAsrStatusState> {
  LiveAsrStatusState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<LiveAsrStatusState, LiveAsrStatusState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LiveAsrStatusState, LiveAsrStatusState>,
              LiveAsrStatusState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// 録音の開始/終了に同期してオンデバイスASRエンジンの起動/停止を行う
/// オーケストレーター。`RecordingController`の`onMasterDataReady`コールバックから
/// `acceptPcm16`が毎回呼ばれる想定。認識結果(確定した発話セグメント)を
/// Riverpodの状態として蓄積し、Liveタブが購読できるようにする。
///
/// このControllerはオンデバイス認識結果をそのまま蓄積するだけで、
/// サーバー版(`lecture_transcripts`)とのwatermark除外は行わない
/// (表示側の`_LiveTranscriptPanel`がサーバー側の最新start_timeより前の
/// セグメントを描画時にフィルタしている)。

@ProviderFor(LiveAsrController)
final liveAsrControllerProvider = LiveAsrControllerProvider._();

/// 録音の開始/終了に同期してオンデバイスASRエンジンの起動/停止を行う
/// オーケストレーター。`RecordingController`の`onMasterDataReady`コールバックから
/// `acceptPcm16`が毎回呼ばれる想定。認識結果(確定した発話セグメント)を
/// Riverpodの状態として蓄積し、Liveタブが購読できるようにする。
///
/// このControllerはオンデバイス認識結果をそのまま蓄積するだけで、
/// サーバー版(`lecture_transcripts`)とのwatermark除外は行わない
/// (表示側の`_LiveTranscriptPanel`がサーバー側の最新start_timeより前の
/// セグメントを描画時にフィルタしている)。
final class LiveAsrControllerProvider
    extends $NotifierProvider<LiveAsrController, List<AsrLiveSegment>> {
  /// 録音の開始/終了に同期してオンデバイスASRエンジンの起動/停止を行う
  /// オーケストレーター。`RecordingController`の`onMasterDataReady`コールバックから
  /// `acceptPcm16`が毎回呼ばれる想定。認識結果(確定した発話セグメント)を
  /// Riverpodの状態として蓄積し、Liveタブが購読できるようにする。
  ///
  /// このControllerはオンデバイス認識結果をそのまま蓄積するだけで、
  /// サーバー版(`lecture_transcripts`)とのwatermark除外は行わない
  /// (表示側の`_LiveTranscriptPanel`がサーバー側の最新start_timeより前の
  /// セグメントを描画時にフィルタしている)。
  LiveAsrControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'liveAsrControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$liveAsrControllerHash();

  @$internal
  @override
  LiveAsrController create() => LiveAsrController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<AsrLiveSegment> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<AsrLiveSegment>>(value),
    );
  }
}

String _$liveAsrControllerHash() => r'bb8b30be81c477b6d5936de89471732cafa7f21c';

/// 録音の開始/終了に同期してオンデバイスASRエンジンの起動/停止を行う
/// オーケストレーター。`RecordingController`の`onMasterDataReady`コールバックから
/// `acceptPcm16`が毎回呼ばれる想定。認識結果(確定した発話セグメント)を
/// Riverpodの状態として蓄積し、Liveタブが購読できるようにする。
///
/// このControllerはオンデバイス認識結果をそのまま蓄積するだけで、
/// サーバー版(`lecture_transcripts`)とのwatermark除外は行わない
/// (表示側の`_LiveTranscriptPanel`がサーバー側の最新start_timeより前の
/// セグメントを描画時にフィルタしている)。

abstract class _$LiveAsrController extends $Notifier<List<AsrLiveSegment>> {
  List<AsrLiveSegment> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<List<AsrLiveSegment>, List<AsrLiveSegment>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<AsrLiveSegment>, List<AsrLiveSegment>>,
              List<AsrLiveSegment>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
