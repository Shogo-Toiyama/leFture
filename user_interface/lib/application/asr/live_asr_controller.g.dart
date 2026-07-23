// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'live_asr_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 録音の開始/終了に同期してオンデバイスASRエンジンの起動/停止を行う
/// オーケストレーター。`RecordingController`の`onMasterDataReady`コールバックから
/// `acceptPcm16`が毎回呼ばれる想定。認識結果(確定した発話セグメント)を
/// Riverpodの状態として蓄積し、Liveタブが購読できるようにする。
///
/// サーバー版(`lecture_transcripts`)とのwatermarkマージはまだ行わない
/// (今回はオンデバイス認識結果をそのまま蓄積するだけ)。

@ProviderFor(LiveAsrController)
final liveAsrControllerProvider = LiveAsrControllerProvider._();

/// 録音の開始/終了に同期してオンデバイスASRエンジンの起動/停止を行う
/// オーケストレーター。`RecordingController`の`onMasterDataReady`コールバックから
/// `acceptPcm16`が毎回呼ばれる想定。認識結果(確定した発話セグメント)を
/// Riverpodの状態として蓄積し、Liveタブが購読できるようにする。
///
/// サーバー版(`lecture_transcripts`)とのwatermarkマージはまだ行わない
/// (今回はオンデバイス認識結果をそのまま蓄積するだけ)。
final class LiveAsrControllerProvider
    extends $NotifierProvider<LiveAsrController, List<AsrLiveSegment>> {
  /// 録音の開始/終了に同期してオンデバイスASRエンジンの起動/停止を行う
  /// オーケストレーター。`RecordingController`の`onMasterDataReady`コールバックから
  /// `acceptPcm16`が毎回呼ばれる想定。認識結果(確定した発話セグメント)を
  /// Riverpodの状態として蓄積し、Liveタブが購読できるようにする。
  ///
  /// サーバー版(`lecture_transcripts`)とのwatermarkマージはまだ行わない
  /// (今回はオンデバイス認識結果をそのまま蓄積するだけ)。
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

String _$liveAsrControllerHash() => r'870a4f359b7d78eb368b87031961870215414b31';

/// 録音の開始/終了に同期してオンデバイスASRエンジンの起動/停止を行う
/// オーケストレーター。`RecordingController`の`onMasterDataReady`コールバックから
/// `acceptPcm16`が毎回呼ばれる想定。認識結果(確定した発話セグメント)を
/// Riverpodの状態として蓄積し、Liveタブが購読できるようにする。
///
/// サーバー版(`lecture_transcripts`)とのwatermarkマージはまだ行わない
/// (今回はオンデバイス認識結果をそのまま蓄積するだけ)。

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
