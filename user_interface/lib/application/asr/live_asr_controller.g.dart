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

String _$liveAsrControllerHash() => r'5ded3958d4e632d7c17a461df84740adae4bc819';

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
